import { describe, expect, it } from "vitest";

import { findMismatch, formatResultTable, listProbePhotos, readExpectations } from "../../scripts/probe-generation-paths.mjs";

// scripts/probe-generation-paths.mjs の、generate を呼ばない部分 (写真の並べ方・期待との突き合わせ・表)。
// generate まで通す確認は test/emulator/probe_generation_paths.test.ts。

describe("findMismatch", () => {
  const sameSubjectExpectation = { path: "same_subject", expected: { status: "duplicate" } };

  it("duplicate でも、相手が期待した写真のモンスターでなければ合わない", () => {
    expect(
      findMismatch({
        pathExpectation: sameSubjectExpectation,
        photoExpectation: { duplicateOf: "ordinary/mug.jpg" },
        outcome: { status: "duplicate", monsterId: "scissors-monster" },
        photoNamesByMonsterId: new Map([
          ["mug-monster", "ordinary/mug.jpg"],
          ["scissors-monster", "ordinary/scissors.jpg"],
        ]),
      }),
    ).toBe("同じ被写体と判定した相手が ordinary/mug.jpg ではなく ordinary/scissors.jpg");
  });

  it("rejected の理由が候補のどれかなら合う", () => {
    const personExpectation = { path: "person", expected: { status: "rejected", rejectionReasons: ["face_detected", "person_detected"] } };
    expect(findMismatch({ pathExpectation: personExpectation, photoExpectation: {}, outcome: { status: "rejected", rejectionReason: "person_detected" }, photoNamesByMonsterId: new Map() })).toBeUndefined();
    expect(findMismatch({ pathExpectation: personExpectation, photoExpectation: {}, outcome: { status: "rejected", rejectionReason: "no_subject" }, photoNamesByMonsterId: new Map() })).toBe(
      "rejectionReason が face_detected / person_detected のどれでもなく no_subject",
    );
  });

  it("status が違えば合わない (判定待ちのまま止まった生成を含む)", () => {
    expect(findMismatch({ pathExpectation: { path: "ordinary", expected: { status: "saved" } }, photoExpectation: {}, outcome: { status: "pending_judge" }, photoNamesByMonsterId: new Map() })).toBe(
      "status が saved ではなく pending_judge",
    );
  });
});

describe("listProbePhotos", () => {
  it("expectations.json のすべての経路に写真があり、paths の順に並ぶ", () => {
    const expectations = readExpectations();
    const pathNames = listProbePhotos({ expectations }).map((photo: { photoName: string }) => photo.photoName.split("/")[0]);
    expect([...new Set(pathNames)]).toEqual(expectations.paths.map((pathExpectation: { path: string }) => pathExpectation.path));
  });

  it("duplicateOf が指す写真がある", () => {
    const expectations = readExpectations();
    const photoNames = listProbePhotos({ expectations }).map((photo: { photoName: string }) => photo.photoName);
    const duplicateOfPhotoNames = expectations.paths.flatMap((pathExpectation: { photos?: Record<string, { duplicateOf: string }> }) =>
      Object.values(pathExpectation.photos ?? {}).map((photoExpectation) => photoExpectation.duplicateOf),
    );
    expect(duplicateOfPhotoNames.length).toBeGreaterThan(0);
    expect(duplicateOfPhotoNames.filter((photoName: string) => !photoNames.includes(photoName))).toEqual([]);
  });

  it("same_subject に絞っても、比べる元の ordinary を先に流す", () => {
    const photoNames = listProbePhotos({ expectations: readExpectations(), pathNames: ["same_subject"] }).map((photo: { photoName: string }) => photo.photoName);
    expect(photoNames.slice(0, 5).every((photoName: string) => photoName.startsWith("ordinary/"))).toBe(true);
    expect(photoNames.slice(5)).toEqual(["same_subject/mug_another_shot.jpg", "same_subject/scissors_another_shot.jpg"]);
  });

  it("same_kind に絞っても、比べる元の ordinary を先に流す", () => {
    const photoNames = listProbePhotos({ expectations: readExpectations(), pathNames: ["same_kind"] }).map((photo: { photoName: string }) => photo.photoName);
    expect(photoNames.slice(0, 5).every((photoName: string) => photoName.startsWith("ordinary/"))).toBe(true);
    expect(photoNames.slice(5)).toEqual(["same_kind/another_mug.jpg", "same_kind/another_rubber_duck.jpg"]);
  });

  it("expectations.json に無い経路はエラーにする", () => {
    expect(() => listProbePhotos({ expectations: readExpectations(), pathNames: ["unknown"] })).toThrow("expectations.json に無い経路です: unknown");
  });
});

describe("formatResultTable", () => {
  it("Claude と Jev の使用量から費用を足し、PASS / FAIL の数を書く", () => {
    const table = formatResultTable([
      { photoName: "ordinary/mug.jpg", expected: "saved", status: "saved", verdict: "PASS", claudeUsages: [{ inputTokens: 1_000_000, outputTokens: 100_000 }], jevInputTokens: 1_000_000 },
      { photoName: "person/portrait.jpg", expected: "rejected", status: "saved", verdict: "FAIL", mismatch: "status が rejected ではなく saved" },
    ]);
    // Claude 4 + 2 ドル、Jev 0.042 ドル
    expect(table).toContain("| ordinary/mug.jpg | saved | saved | PASS |  |  |  | 1000000 / 100000 | 1000000 | 6.0420 |");
    expect(table).toContain("| FAIL: status が rejected ではなく saved |");
    expect(table).toContain("PASS 1 / FAIL 1。Claude 入力 1000000 / 出力 100000 トークン、Jev 入力 1000000 トークン、費用 6.0420 ドル");
  });
});
