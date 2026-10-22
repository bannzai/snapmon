// 写真から被写体を切り出す。マスクは、クライアントが送ったもの (手で決めた範囲) か、サーバーで作ったもの (自動) のどちらか。
// どちらの経路でも、切り出しは検査済みの元の写真にサーバーが適用する (ADR 0002)。
// 自動のマスクは IS-Net (DIS) の general-use の重み (Apache-2.0。https://github.com/xuebinqin/DIS ) を rembg が ONNX にしたもの
// ( https://github.com/danielgatis/rembg/releases/tag/v0.0.0 の isnet-general-use.onnx) を onnxruntime-node で動かして作る。
// モデルは functions/scripts/fetch-segmentation-model.mjs がビルド時に取得する (リポジトリには置かない。178 MB あるため)。

import path from "node:path";

import type { InferenceSession } from "onnxruntime-node";
import sharp from "sharp";

/**
 * 切り出しに使う写真の長辺の上限 (px)。モデルの入力 (1024 × 1024) より細かくしても輪郭は細かくならず、
 * 端末の写真 (12 MP 前後) のままだとマスクの適用と art.png (PvP・共有カードで他人も読む) が重くなるため、モデルの入力に揃えた。
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

/** 写真のマスク (被写体が白・背景が黒のグレースケール PNG。大きさは写真と同じ) を作る関数。テストではモックに差し替える。 */
export type SegmentSubject = (photo: Buffer) => Promise<Buffer>;

/** モデルの入力の一辺 (isnet-general-use は 1024 × 1024 で書き出されている)。 */
const MODEL_INPUT_SIZE = 1024;
/** 入力の正規化 (rembg の DIS のセッションと同じ値: 平均 0.5・標準偏差 1.0)。 */
const MODEL_INPUT_MEAN = 0.5;
const MODEL_INPUT_STANDARD_DEVIATION = 1.0;

/** モデルのファイルの置き場 (functions/models/。fetch-segmentation-model.mjs が置く)。 */
export const SEGMENTATION_MODEL_PATH = path.join(__dirname, "..", "..", "models", "isnet-general-use.onnx");

/**
 * IS-Net で自動のマスクを作る関数を作る。モデルは最初に呼ばれた時に読む
 * (デプロイ時の関数の検出と Emulator の起動は、モデルが無い環境でもモジュールを読むため)。
 * 推論の出力は 0〜1 の確率で、rembg のように最小・最大で引き伸ばさない (単色の写真の弱い反応を被写体として拾わないため)。
 */
export function createSegmentSubject({ modelPath }: { modelPath: string }): SegmentSubject {
  let session: Promise<InferenceSession> | undefined;
  return async (photo) => {
    // onnxruntime-node はネイティブのモジュールのため、使う時に読む (Emulator のテストと関数の検出で読み込まないため)。
    const onnxRuntime = await import("onnxruntime-node");
    session ??= onnxRuntime.InferenceSession.create(modelPath);
    const loadedSession = await session;
    const { data: pixels } = await sharp(photo)
      .rotate()
      .removeAlpha()
      .resize(MODEL_INPUT_SIZE, MODEL_INPUT_SIZE, { fit: "fill", kernel: "lanczos3" })
      .raw()
      .toBuffer({ resolveWithObject: true });
    // 画素数が多く、展開して Math.max に渡すと呼び出しの引数の上限を超えるため、reduce で求める。
    const maximumPixel = pixels.reduce((maximum, pixel) => Math.max(maximum, pixel), 1);
    const area = MODEL_INPUT_SIZE * MODEL_INPUT_SIZE;
    const input = new Float32Array(3 * area);
    for (let index = 0; index < area; index++) {
      for (let channel = 0; channel < 3; channel++) {
        input[channel * area + index] = (pixels[index * 3 + channel] / maximumPixel - MODEL_INPUT_MEAN) / MODEL_INPUT_STANDARD_DEVIATION;
      }
    }
    const outputs = await loadedSession.run({
      [loadedSession.inputNames[0]]: new onnxRuntime.Tensor("float32", input, [1, 3, MODEL_INPUT_SIZE, MODEL_INPUT_SIZE]),
    });
    const prediction = outputs[loadedSession.outputNames[0]].data as Float32Array;
    const mask = Buffer.alloc(area);
    for (let index = 0; index < area; index++) {
      mask[index] = Math.round(Math.min(1, Math.max(0, prediction[index])) * 255);
    }
    const { width, height } = await sharp(photo).rotate().metadata();
    return sharp(mask, { raw: { width: MODEL_INPUT_SIZE, height: MODEL_INPUT_SIZE, channels: 1 } })
      .resize(width, height, { fit: "fill" })
      .extractChannel(0)
      .png()
      .toBuffer();
  };
}

/** 被写体とみなすマスクの値 (0〜255 の半分。モデルの確率 0.5 に当たる)。 */
const SUBJECT_ALPHA_THRESHOLD = 128;

/**
 * 被写体の面積が写真に占める割合の下限。実測 (ADR 0002) で、単色の写真は 0%、見本の物の写真は 5.0〜49% だったため、
 * その間で、小さく写った物を拒否しにくい 1% にした。
 */
export const MINIMUM_SUBJECT_COVERAGE = 0.01;

/** 切り出した絵の周りに残す余白 (被写体の外接矩形の長辺に対する割合)。輪郭線とオーラを描く余地として置く。 */
const CUTOUT_MARGIN_RATIO = 0.04;

/** 切り出しの結果。 */
export interface CutoutResult {
  /** 背景を透明にし、被写体の外接矩形 (と余白) で切り詰めた PNG。被写体が無ければ undefined。 */
  cutoutPng: Buffer | undefined;
  /** 被写体の面積が写真に占める割合 (0〜1)。 */
  coverage: number;
}

/**
 * 写真にマスクを適用して被写体を切り出す。マスクは写真と大きさが違ってもよい (手で決めた範囲を端末の表示の大きさで送る場合)。
 * 被写体の割合が `MINIMUM_SUBJECT_COVERAGE` に満たない時は `cutoutPng` を返さない (切り出せない写真として拒否する)。
 */
export async function applyMask({ photo, mask }: { photo: Buffer; mask: Buffer }): Promise<CutoutResult> {
  const { data: rgb, info } = await sharp(photo).rotate().removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const { width, height } = info;
  const alpha = await sharp(mask).rotate().removeAlpha().resize(width, height, { fit: "fill" }).extractChannel(0).raw().toBuffer();
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
  const coverage = subjectPixels / (width * height);
  if (coverage < MINIMUM_SUBJECT_COVERAGE) {
    return { cutoutPng: undefined, coverage };
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
    coverage,
  };
}

/** Claude に渡すため、切り出した PNG の透明な部分を白で塗った JPEG にする (プロンプトが「背景は白」と伝えているため)。 */
export function flattenCutoutForDescription(cutoutPng: Buffer): Promise<Buffer> {
  return sharp(cutoutPng).flatten({ background: "#ffffff" }).jpeg({ quality: 90 }).toBuffer();
}
