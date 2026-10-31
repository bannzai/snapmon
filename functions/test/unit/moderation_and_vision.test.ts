import { describe, expect, it } from "vitest";

import { findModerationViolation } from "../../src/generation/moderation";
import { DESCRIBE_SUBJECT_SYSTEM_PROMPT, parseDescribeSubjectOutput } from "../../src/generation/prompts/describe_subject";
import { proposalRangeViolation } from "../../src/generation/prompts/propose_element";
import { visionRejectionLogFields, visionRejectionReason } from "../../src/generation/vision";

describe("findModerationViolation", () => {
  it("禁止語と他社の名称を、ひらがな・カタカナ・全角半角の揺れを越えて見つける", () => {
    expect(findModerationViolation("ぴかちゅうに似ている")).toBe("ピカチュウ");
    expect(findModerationViolation("ＰＯＫＥＭＯＮ")).toBe("pokemon");
    expect(findModerationViolation("血まみれの姿")).toBe("血まみれ");
  });

  it("普通の文章は通す", () => {
    expect(findModerationViolation("マグカップン\n朝いちばんの湯気をまとって、持ち主のそばにやってくる。")).toBeUndefined();
  });

  it("普通の語の一部になる禁止語 (殺菌のイエローのスプレー、おうちにかえろう、ワインレッド、テロップ、skill) は止めない", () => {
    expect(findModerationViolation("殺菌スプレーのイエローモン。おうちにかえろうと鳴く")).toBeUndefined();
    expect(findModerationViolation("ワインレッドの体でテロップを読む。special skill")).toBeUndefined();
    expect(findModerationViolation("机のかたわらで眠る。めくらましの光を放つ郷土人形")).toBeUndefined();
    expect(findModerationViolation("kill them")).toBe("kill");
  });
});

describe("visionRejectionReason", () => {
  it("露骨な画像と顔が写る画像を拒否し、それ以外は通す", () => {
    expect(visionRejectionReason({ safeSearchAnnotation: { adult: "VERY_LIKELY" } })).toBe("explicit_content");
    expect(visionRejectionReason({ safeSearchAnnotation: { violence: "VERY_LIKELY" } })).toBe("explicit_content");
    expect(visionRejectionReason({ safeSearchAnnotation: { racy: "VERY_LIKELY" } })).toBe("explicit_content");
    expect(visionRejectionReason({ safeSearchAnnotation: { adult: "POSSIBLE" }, faceAnnotations: [{ detectionConfidence: 0.3 }] })).toBe("face_detected");
    expect(visionRejectionReason({ safeSearchAnnotation: { adult: "VERY_UNLIKELY" }, labelAnnotations: [{ description: "Mug", score: 0.9 }] })).toBeUndefined();
  });

  it("adult・violence・racy が LIKELY でも拒否しない (イラストが LIKELY になる誤検知を通すため)", () => {
    expect(visionRejectionReason({ safeSearchAnnotation: { adult: "LIKELY", violence: "LIKELY", racy: "LIKELY" } })).toBeUndefined();
  });
});

describe("visionRejectionLogFields", () => {
  it("SafeSearch の各区分の尤度と、顔の数・確信度を返す", () => {
    expect(
      visionRejectionLogFields({
        safeSearchAnnotation: { adult: "VERY_LIKELY", violence: "UNLIKELY", racy: "LIKELY", medical: "VERY_UNLIKELY", spoof: "POSSIBLE" },
        faceAnnotations: [{ detectionConfidence: 0.9 }, { detectionConfidence: 0.4 }],
        labelAnnotations: [{ description: "Mug", score: 0.9 }],
      }),
    ).toEqual({
      safeSearch: { adult: "VERY_LIKELY", violence: "UNLIKELY", racy: "LIKELY", medical: "VERY_UNLIKELY", spoof: "POSSIBLE" },
      faceCount: 2,
      faceDetectionConfidences: [0.9, 0.4],
    });
    expect(visionRejectionLogFields({})).toEqual({ safeSearch: {}, faceCount: 0, faceDetectionConfidences: [] });
  });
});

describe("DESCRIBE_SUBJECT_SYSTEM_PROMPT", () => {
  it("絵・画面の中の物・フィギュアは、媒体ではなく描かれた物として説明させる (#129)", () => {
    expect(DESCRIBE_SUBJECT_SYSTEM_PROMPT).toContain("描かれた物 (かたどられた物) そのものを被写体とします");
    expect(DESCRIBE_SUBJECT_SYSTEM_PROMPT).toContain("紙・画面・プラスチックなどの媒体ではなく、その物が実物ならどうかで what・materials・size・hardness・temperature・uses・impression を書いてください");
    expect(DESCRIBE_SUBJECT_SYSTEM_PROMPT).toContain("materials は「紙」ではなく「食べ物」");
    // 同じ物を描いた別の絵を同じ被写体にしないため、絵であることと描き方は見分ける手がかりに残させる
    expect(DESCRIBE_SUBJECT_SYSTEM_PROMPT).toContain("同じ物を描いた別の絵と見分ける手がかりとして distinctiveMarks に書いてください");
    // 手がかりに媒体の名前 (紙に描かれた) が残ると、Jev が紙の属性に寄せるため書かせない
    expect(DESCRIBE_SUBJECT_SYSTEM_PROMPT).toContain("紙・画面などの媒体の名前はここにも書かない");
    // 人の絵を人に含めない既存の指示は残す
    expect(DESCRIBE_SUBJECT_SYSTEM_PROMPT).toContain("動物・人形・ぬいぐるみ・人の絵は人に含めない");
  });
});

describe("parseDescribeSubjectOutput", () => {
  const output = {
    description: { what: "マグカップ", colors: [], materials: [], size: "small", hardness: "hard", temperature: "warm", uses: [], impression: [], distinctiveMarks: [] },
    name: "マグモン",
    encyclopediaText: "あたたかい。",
    decoration: { eyeStyle: "round", mouthStyle: "smile", limbStyle: "stubby", auraStyle: "soft", eyeCenterX: 1.4, eyeCenterY: -0.2, eyeScale: 0.5, outlineColorHex: "#112233" },
    containsPerson: false,
  };

  it("装飾の割合を範囲に収める", () => {
    expect(parseDescribeSubjectOutput(JSON.stringify(output)).decoration).toMatchObject({ eyeCenterX: 1, eyeCenterY: 0, eyeScale: 0.3 });
  });

  it("名前の長さと色の形式が範囲外なら throw する", () => {
    expect(() => parseDescribeSubjectOutput(JSON.stringify({ ...output, name: "ア" }))).toThrow();
    expect(() => parseDescribeSubjectOutput(JSON.stringify({ ...output, decoration: { ...output.decoration, outlineColorHex: "blue" } }))).toThrow();
  });
});

describe("proposalRangeViolation", () => {
  const proposal = {
    element: { displayName: "ろう", description: "ろうでできた物", colorHex: "#FFEEDD" },
    moves: [
      { displayName: "ろうアタック", power: 40, powerPoints: 30 },
      { displayName: "ろうプレス", power: 70, powerPoints: 15 },
      { displayName: "ろうバースト", power: 110, powerPoints: 5 },
    ],
  };

  it("範囲内の提案は通し、威力が範囲外なら理由を返す", () => {
    expect(proposalRangeViolation(proposal)).toBeUndefined();
    expect(proposalRangeViolation({ ...proposal, moves: [{ ...proposal.moves[0], power: 200 }, proposal.moves[1], proposal.moves[2]] })).toContain("威力");
  });
});
