// App Store のスクリーンショットに出すモンスターの絵を、本番の生成と同じ切り出し (lib/generation/cutout.js) で作る。
// 写真は test/fixtures/calibration/photos/ の CC0 / Public domain の写真 (出典は同ディレクトリの LICENSES.md)。
// 書き出した PNG は store_screenshots/fixtures/cutouts/ に置き、スクリーンショットの生成 (make screenshots) が読む。
// 同じ写真とモデルからは同じ PNG ができるため、何度実行しても結果は変わらない。
//
// 使い方: npm ci && npm run build && npm run fetch-model && node scripts/cutout-store-screenshot-photos.mjs
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import cutout from "../lib/generation/cutout.js";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const photoDirectory = path.join(root, "test", "fixtures", "calibration", "photos");
const outputDirectory = path.join(root, "..", "store_screenshots", "fixtures", "cutouts");

/** 書き出す PNG の名前と、元の写真のファイル名。名前は store_screenshots/ のモンスターの絵のパスと揃える。 */
const PHOTOS = {
  mug: "01.jpg",
  scissors: "15.jpg",
  cactus: "04.jpg",
  rubber_duck: "08.jpg",
  kettle: "11.jpg",
  candle: "18.jpg",
};

const segmentSubject = cutout.createSegmentSubject({ modelPath: cutout.SEGMENTATION_MODEL_PATH });
mkdirSync(outputDirectory, { recursive: true });
for (const [name, fileName] of Object.entries(PHOTOS)) {
  const photo = await cutout.downscalePhoto(readFileSync(path.join(photoDirectory, fileName)));
  const { cutoutPng, coverage } = await cutout.applyMask({ photo, mask: await segmentSubject(photo) });
  if (cutoutPng === undefined) {
    console.error(`${fileName} から被写体を切り出せませんでした (被写体の割合 ${coverage})`);
    process.exit(1);
  }
  writeFileSync(path.join(outputDirectory, `${name}.png`), cutoutPng);
  console.log(`${name}.png (${fileName}、被写体の割合 ${coverage.toFixed(3)})`);
}
