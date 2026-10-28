// 見本のモンスター (assets/samples/sample_monsters.json) の切り出した絵を、Wikimedia Commons の CC0 / Public domain の写真から作り、
// assets/samples/art/{見本のモンスターの id}.png に書く。切り出しは本番と同じ順 (アプリの iOS が Vision の前景のマスクを作り、
// functions/src/generation/pipeline.ts が downscalePhoto → applyMask する) で、マスクはアプリの iOS と同じ Vision の API
// (scripts/subject-mask.swift) で作る。そのため macOS (14 以降) で実行する。
// 出典とライセンスは assets/samples/art/LICENSES.md に書く。写真を変えたらそちらも直す。
// 同じ写真からは同じ画像を書き直す (Commons の縮小版の画素と Vision の版が変わらない限り)。
//
// 使い方: npm run build && node scripts/build-sample-art.mjs
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

import sharp from "sharp";

import cutout from "../lib/generation/cutout.js";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const artDirectory = path.join(root, "..", "assets", "samples", "art");

/**
 * 見本のモンスターの id と、元の写真 (Commons のファイル名) と、切り出しの前に写真を切り詰める範囲 (写真の幅・高さに対する割合)。
 * 切り詰めるのは、被写体以外の物 (ペン・クリップ)・机への映り込みと影・商標 (キーボードのロゴ)・撮影機材の透かしを写真から外すため。
 * ユーザーが撮る時に被写体だけを枠に収めるのと同じ扱い。
 */
const SAMPLE_PHOTOS = [
  {
    monsterId: "sample-mugmon",
    commonsFile: "Bucharest mug (Unsplash).jpg",
    crop: { left: 0.15, top: 0.35, width: 0.45, height: 0.48 },
  },
  {
    monsterId: "sample-petbottler",
    commonsFile: "Bottle of Water.jpg",
    crop: { left: 0.33, top: 0.08, width: 0.35, height: 0.8 },
  },
  {
    monsterId: "sample-keybon",
    commonsFile: "Black Computer keyboard.jpg",
    crop: { left: 0, top: 0.4, width: 0.655, height: 0.42 },
  },
  {
    monsterId: "sample-ringora",
    commonsFile: "Red delicious Apple.jpg",
    crop: { left: 0.1, top: 0.3, width: 0.8, height: 0.6 },
  },
  {
    monsterId: "sample-noton",
    commonsFile: "Leather notebook (Unsplash).jpg",
    crop: { left: 0.615, top: 0.17, width: 0.315, height: 0.51 },
  },
  { monsterId: "sample-slippan", commonsFile: "Slippers MET 69.108.371a-b CP4.jpg" },
];

/** Commons から取る縮小版の幅 (px)。切り出しは長辺 1024px に縮めてから行う (cutout.ts の CUTOUT_PHOTO_LONG_SIDE_MAXIMUM) ため、切り詰めた後もそれを下回りにくい幅にした。 */
const COMMONS_THUMBNAIL_WIDTH = 2048;

/** Commons の API が求める User-Agent ( https://foundation.wikimedia.org/wiki/Policy:Wikimedia_Foundation_User-Agent_Policy )。 */
const USER_AGENT = "snapmon-build-sample-art/1.0 (https://github.com/bannzai/snapmon)";

/** Commons の [commonsFile] の、幅 COMMONS_THUMBNAIL_WIDTH の縮小版を読む。 */
async function fetchCommonsPhoto(commonsFile) {
  const response = await fetch(
    `https://commons.wikimedia.org/w/api.php?${new URLSearchParams({
      action: "query",
      format: "json",
      titles: `File:${commonsFile}`,
      prop: "imageinfo",
      iiprop: "url",
      iiurlwidth: String(COMMONS_THUMBNAIL_WIDTH),
    })}`,
    { headers: { "User-Agent": USER_AGENT } },
  );
  if (!response.ok) {
    throw new Error(`${commonsFile} の情報を取得できませんでした: HTTP ${response.status}`);
  }
  const [page] = Object.values((await response.json()).query.pages);
  const photoResponse = await fetch(page.imageinfo[0].thumburl, { headers: { "User-Agent": USER_AGENT } });
  if (!photoResponse.ok) {
    throw new Error(`${commonsFile} を取得できませんでした: HTTP ${photoResponse.status}`);
  }
  return Buffer.from(await photoResponse.arrayBuffer());
}

/** [photo] を [crop] (割合) の範囲に切り詰めた JPEG を返す。[crop] が無ければ [photo] をそのまま返す。 */
async function cropPhoto({ photo, crop }) {
  if (!crop) {
    return photo;
  }
  // metadata() の幅・高さは EXIF の向きを直す前の値のため、向きを直した画像の大きさから範囲を決める
  // raw で受け渡すのは、途中で JPEG に符号化し直して画質を落とさないため
  const { data, info } = await sharp(photo).rotate().raw().toBuffer({ resolveWithObject: true });
  return sharp(data, { raw: { width: info.width, height: info.height, channels: info.channels } })
    .extract({
      left: Math.round(info.width * crop.left),
      top: Math.round(info.height * crop.top),
      width: Math.round(info.width * crop.width),
      height: Math.round(info.height * crop.height),
    })
    .jpeg({ quality: 95 })
    .toBuffer();
}

/** 作業用の写真とマスクを置く一時ディレクトリ。 */
const workDirectory = mkdtempSync(path.join(tmpdir(), "snapmon-sample-art-"));

/** [photo] の前景の被写体のマスクの PNG を、scripts/subject-mask.swift (アプリの iOS と同じ Vision の API) で作る。前景が無ければ throw する。 */
function createSubjectMask({ monsterId, photo }) {
  const photoPath = path.join(workDirectory, `${monsterId}.jpg`);
  const maskPath = path.join(workDirectory, `${monsterId}-mask.png`);
  writeFileSync(photoPath, photo);
  execFileSync("swift", [path.join(root, "scripts", "subject-mask.swift"), photoPath, maskPath], { stdio: "inherit" });
  return readFileSync(maskPath);
}

mkdirSync(artDirectory, { recursive: true });
for (const { monsterId, commonsFile, crop } of SAMPLE_PHOTOS) {
  const photo = await cutout.downscalePhoto(await cropPhoto({ photo: await fetchCommonsPhoto(commonsFile), crop }));
  // 被写体の画素が無いマスクは applyMask が写真全体を返すため、見本の絵として使わずに止める
  const { cutoutPng, coverage } = await cutout.applyMask({ photo, mask: createSubjectMask({ monsterId, photo }) });
  if (coverage === 1) {
    console.error(`${monsterId}: 被写体を切り出せませんでした (マスクが写真全体)`);
    process.exit(1);
  }
  writeFileSync(path.join(artDirectory, `${monsterId}.png`), cutoutPng);
  console.log(`${monsterId}: 被写体の割合 ${(coverage * 100).toFixed(1)}%`);
}
