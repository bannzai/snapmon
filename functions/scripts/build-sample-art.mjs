// 見本のモンスター (assets/samples/sample_monsters.json) の切り出した絵を、Wikimedia Commons の CC0 / Public domain の写真から作り、
// assets/samples/art/{見本のモンスターの id}.png に書く。切り出しは本番の generate と同じ順 (functions/src/generation/pipeline.ts の
// downscalePhoto → 自動のマスク → applyMask) で、同じモデル (lib/generation/cutout.js) を使う。
// 出典とライセンスは assets/samples/art/LICENSES.md に書く。写真を変えたらそちらも直す。
// 同じ写真からは同じ画像を書き直す (Commons の縮小版の画素が変わらない限り)。
//
// 使い方: npm run build && npm run fetch-model && node scripts/build-sample-art.mjs
import { mkdirSync, writeFileSync } from "node:fs";
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
  const query = new URLSearchParams({
    action: "query",
    format: "json",
    titles: `File:${commonsFile}`,
    prop: "imageinfo",
    iiprop: "url",
    iiurlwidth: String(COMMONS_THUMBNAIL_WIDTH),
  });
  const response = await fetch(`https://commons.wikimedia.org/w/api.php?${query}`, { headers: { "User-Agent": USER_AGENT } });
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

const segmentSubject = cutout.createSegmentSubject({ modelPath: cutout.SEGMENTATION_MODEL_PATH });
mkdirSync(artDirectory, { recursive: true });
for (const { monsterId, commonsFile, crop } of SAMPLE_PHOTOS) {
  const photo = await cutout.downscalePhoto(await cropPhoto({ photo: await fetchCommonsPhoto(commonsFile), crop }));
  const { cutoutPng, coverage } = await cutout.applyMask({ photo, mask: await segmentSubject(photo) });
  if (!cutoutPng) {
    console.error(`${monsterId}: 被写体を切り出せませんでした (被写体の割合 ${coverage})`);
    process.exit(1);
  }
  writeFileSync(path.join(artDirectory, `${monsterId}.png`), cutoutPng);
  console.log(`${monsterId}: 被写体の割合 ${(coverage * 100).toFixed(1)}%`);
}
