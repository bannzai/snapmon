import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

import sharp from "sharp";
import { describe, expect, it } from "vitest";

import { applyMask, createSegmentSubject, downscalePhoto, MINIMUM_SUBJECT_COVERAGE, SEGMENTATION_MODEL_PATH } from "../../src/generation/cutout";

/** 単色の写真 (被写体の無い写真の見本)。 */
function uniformPhoto(): Promise<Buffer> {
  return sharp({ create: { width: 320, height: 240, channels: 3, background: { r: 200, g: 180, b: 150 } } }).jpeg().toBuffer();
}

/** 中央に四角い被写体があるマスク。 */
function centeredSquareMask({ width, height }: { width: number; height: number }): Promise<Buffer> {
  return sharp({ create: { width, height, channels: 3, background: "#000000" } })
    .composite([{ input: { create: { width: width / 2, height: height / 2, channels: 3, background: "#ffffff" } }, left: width / 4, top: height / 4 }])
    .png()
    .toBuffer();
}

describe("downscalePhoto", () => {
  it("長辺を 1024px に縮め、小さい写真は拡大しない", async () => {
    const large = await sharp({ create: { width: 4000, height: 3000, channels: 3, background: "#808080" } }).jpeg().toBuffer();
    expect(await sharp(await downscalePhoto(large)).metadata()).toMatchObject({ width: 1024, height: 768 });
    expect(await sharp(await downscalePhoto(await uniformPhoto())).metadata()).toMatchObject({ width: 320, height: 240 });
  });
});

describe("applyMask", () => {
  it("マスクの範囲を透明な背景で切り出し、被写体の外接矩形に切り詰める", async () => {
    const result = await applyMask({ photo: await uniformPhoto(), mask: await centeredSquareMask({ width: 320, height: 240 }) });
    expect(result.coverage).toBeCloseTo(0.25, 2);
    const metadata = await sharp(result.cutoutPng!).metadata();
    expect(metadata.hasAlpha).toBe(true);
    expect(metadata.width).toBeLessThan(320);
  });

  it("被写体でない画素は RGB も 0 にし、背景の色を残さない", async () => {
    const result = await applyMask({ photo: await uniformPhoto(), mask: await centeredSquareMask({ width: 320, height: 240 }) });
    const { data, info } = await sharp(result.cutoutPng!).raw().toBuffer({ resolveWithObject: true });
    for (let index = 0; index < info.width * info.height; index++) {
      if (data[index * 4 + 3] === 0) {
        expect([data[index * 4], data[index * 4 + 1], data[index * 4 + 2]]).toEqual([0, 0, 0]);
      }
    }
  });

  it("写真と大きさの違うマスク (端末の表示の大きさで手で決めた範囲) も写真に合わせて適用する", async () => {
    const result = await applyMask({ photo: await uniformPhoto(), mask: await centeredSquareMask({ width: 160, height: 120 }) });
    expect(result.coverage).toBeCloseTo(0.25, 2);
  });

  it("被写体が無いマスクは切り出さない", async () => {
    const emptyMask = await sharp({ create: { width: 320, height: 240, channels: 3, background: "#000000" } }).png().toBuffer();
    const result = await applyMask({ photo: await uniformPhoto(), mask: emptyMask });
    expect(result.cutoutPng).toBeUndefined();
    expect(result.coverage).toBeLessThan(MINIMUM_SUBJECT_COVERAGE);
  });
});

// 実際のモデル (178 MB) で確かめる。CI は firebase-ci.yml で `npm run fetch-model` してから実行し、手元でモデルが無い時だけ飛ばす。
describe.skipIf(!existsSync(SEGMENTATION_MODEL_PATH) && !process.env.CI)("createSegmentSubject (isnet-general-use)", () => {
  const segmentSubject = createSegmentSubject({ modelPath: SEGMENTATION_MODEL_PATH });

  it("単色の写真からは被写体を切り出せない", async () => {
    const photo = await uniformPhoto();
    const result = await applyMask({ photo, mask: await segmentSubject(photo) });
    expect(result.cutoutPng).toBeUndefined();
  }, 60_000);

  it("物の写真からは被写体を切り出せる", async () => {
    const photo = readFileSync(path.join(__dirname, "..", "fixtures", "calibration", "photos", "08.jpg"));
    const result = await applyMask({ photo, mask: await segmentSubject(photo) });
    expect(result.cutoutPng).toBeDefined();
    expect(result.coverage).toBeGreaterThan(0.1);
  }, 60_000);
});
