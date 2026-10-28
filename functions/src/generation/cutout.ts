// 写真から被写体を切り出す。マスクは端末が決めて送ったもの (iOS の OS の切り出しか、ユーザーが crop で決めた範囲) だけで、
// サーバーではマスクを作らない。マスクが無い時は写真全体を切り出した絵として扱う。
// どの経路でも、切り出しは検査済みの元の写真にサーバーが適用する (ADR 0002)。

import sharp from "sharp";

/**
 * 切り出しに使う写真の長辺の上限 (px)。端末が送る写真の長辺 (lib/features/capture/photo_preparation.dart の 1024px) と同じにし、
 * 古い版の端末や手で置かれた大きな写真でも、マスクの適用と art.png (PvP・共有カードで他人も読む) が重くならないようにした。
 */
const CUTOUT_PHOTO_LONG_SIDE_MAXIMUM = 1024;

/** 写真の向きを EXIF のとおりに直し、長辺を `CUTOUT_PHOTO_LONG_SIDE_MAXIMUM` 以下に縮めた JPEG を返す (小さい写真は拡大しない)。 */
export function downscalePhoto(photo: Buffer): Promise<Buffer> {
  return sharp(photo)
    .rotate()
    .resize({ width: CUTOUT_PHOTO_LONG_SIDE_MAXIMUM, height: CUTOUT_PHOTO_LONG_SIDE_MAXIMUM, fit: "inside", withoutEnlargement: true })
    .jpeg({ quality: 92 })
    .toBuffer();
}

/**
 * マスクを展開してよい画素数の上限。端末が送るマスクは送った写真と同じ大きさ (長辺 1024px、
 * lib/features/capture/subject_mask.dart と ios/Runner/AppDelegate.swift) で、正方形でも 1024 × 1024 のため、その 4 倍を上限にした。
 * Storage の 1 MB の制限は圧縮後の大きさで、展開後の画素数を抑えない (sharp の既定の上限は約 2.7 億画素で、RGBA で約 1 GiB になり
 * Functions のメモリを使い切る) ため。超えるマスクは展開せずに失敗させる。
 */
const MASK_INPUT_PIXEL_LIMIT = 1024 * 1024 * 4;

/** 被写体とみなすマスクの値 (0〜255 の半分。OS の切り出しの境界のぼかしの中ほど)。 */
const SUBJECT_ALPHA_THRESHOLD = 128;

/** 切り出した絵の周りに残す余白 (被写体の外接矩形の長辺に対する割合)。輪郭線とオーラを描く余地として置く。 */
const CUTOUT_MARGIN_RATIO = 0.04;

/** 切り出しの結果。 */
export interface CutoutResult {
  /** 背景を透明にし、被写体の外接矩形 (と余白) で切り詰めた PNG。マスクが無い・被写体の画素が無い時は写真全体の PNG。 */
  cutoutPng: Buffer;
  /** 被写体の面積が写真に占める割合 (0〜1)。写真全体を使った時は 1。 */
  coverage: number;
}

/**
 * 写真にマスクを適用して被写体を切り出す。マスクは写真と大きさが違ってもよい (写真と同じ縦横比なら、写真に合わせて引き伸ばす)。
 * マスクが無い時と、マスクに被写体の画素が 1 つも無い時は、写真全体を返す (切り出せない写真を拒否せず生成を続けるため。
 * DIRECTION.md「決めたこと」2026-10-28)。
 */
export async function applyMask({ photo, mask }: { photo: Buffer; mask: Buffer | undefined }): Promise<CutoutResult> {
  const { data: rgb, info } = await sharp(photo).rotate().removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const { width, height } = info;
  const wholePhoto = async (): Promise<CutoutResult> => ({
    cutoutPng: await sharp(rgb, { raw: { width, height, channels: 3 } }).png().toBuffer(),
    coverage: 1,
  });
  if (!mask) {
    return wholePhoto();
  }
  const alpha = await sharp(mask, { limitInputPixels: MASK_INPUT_PIXEL_LIMIT }).rotate().removeAlpha().resize(width, height, { fit: "fill" }).extractChannel(0).raw().toBuffer();
  let subjectPixels = 0;
  let left = width;
  let top = height;
  let right = -1;
  let bottom = -1;
  // 被写体でない画素は RGB も 0 にする (透明でも RGB が残ると、art.png のアルファを外すだけで背景、つまり元の写真が見えてしまうため)。
  // 境界の半透明は被写体とみなした画素 (マスクの値が半分以上) にだけ残す。
  const rgba = Buffer.alloc(width * height * 4);
  for (let index = 0; index < width * height; index++) {
    if (alpha[index] >= SUBJECT_ALPHA_THRESHOLD) {
      rgba[index * 4] = rgb[index * 3];
      rgba[index * 4 + 1] = rgb[index * 3 + 1];
      rgba[index * 4 + 2] = rgb[index * 3 + 2];
      rgba[index * 4 + 3] = alpha[index];
      subjectPixels++;
      const x = index % width;
      const y = Math.floor(index / width);
      left = Math.min(left, x);
      right = Math.max(right, x);
      top = Math.min(top, y);
      bottom = Math.max(bottom, y);
    }
  }
  if (subjectPixels === 0) {
    return wholePhoto();
  }
  const margin = Math.round(Math.max(right - left + 1, bottom - top + 1) * CUTOUT_MARGIN_RATIO);
  const extractLeft = Math.max(0, left - margin);
  const extractTop = Math.max(0, top - margin);
  return {
    cutoutPng: await sharp(rgba, { raw: { width, height, channels: 4 } })
      .extract({
        left: extractLeft,
        top: extractTop,
        width: Math.min(width, right + margin + 1) - extractLeft,
        height: Math.min(height, bottom + margin + 1) - extractTop,
      })
      .png()
      .toBuffer(),
    coverage: subjectPixels / (width * height),
  };
}

/** Claude に渡すため、切り出した PNG の透明な部分を白で塗った JPEG にする (プロンプトが「背景は白」と伝えているため)。 */
export function flattenCutoutForDescription(cutoutPng: Buffer): Promise<Buffer> {
  return sharp(cutoutPng).flatten({ background: "#ffffff" }).jpeg({ quality: 90 }).toBuffer();
}
