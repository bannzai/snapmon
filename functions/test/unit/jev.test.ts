import { readFileSync } from "node:fs";
import path from "node:path";

import { describe, expect, it } from "vitest";

import {
  buildDedupeRequests,
  buildJudgeRequest,
  createAskJev,
  DEDUPE_CHUNK_SIZE,
  DEDUPE_THRESHOLDS,
  type JevResponse,
  JevUnavailableError,
  readJudgeResponse,
  sameSubjectCandidateIds,
} from "../../src/generation/jev";
import type { Master } from "../../src/generation/master";
import type { SubjectDescription } from "../../src/generation/prompts/describe_subject";

const master = JSON.parse(readFileSync(path.join(__dirname, "..", "..", "..", "assets", "master", "master.json"), "utf8")) as Master;
const description: SubjectDescription = {
  what: "白いマグカップ",
  colors: ["白"],
  materials: ["陶器"],
  size: "small",
  hardness: "hard",
  temperature: "warm",
  uses: ["飲み物を入れる"],
  impression: ["すっきり"],
  distinctiveMarks: [],
};

describe("buildDedupeRequests", () => {
  it("候補 20 件ごとに 1 リクエストにし、候補ごとに肯定・否定の対を問う", () => {
    const candidates = Array.from({ length: DEDUPE_CHUNK_SIZE + 1 }, (_, index) => ({ candidateId: `monster${index}`, description }));
    const requests = buildDedupeRequests({ description, candidates });
    expect(requests).toHaveLength(2);
    expect(Object.keys(requests[0].questions)).toHaveLength(DEDUPE_CHUNK_SIZE * 2);
    expect(Object.keys(requests[1].questions)).toEqual([`same__${DEDUPE_CHUNK_SIZE}`, `different__${DEDUPE_CHUNK_SIZE}`]);
  });
});

describe("sameSubjectCandidateIds", () => {
  const candidates = ["a", "b", "c", "d"].map((candidateId) => ({ candidateId, description }));
  const response = (answers: [number, number][]): JevResponse => ({
    model: "jev-1.13.0",
    usage: { input_tokens: 0, output_tokens: 0 },
    answers: Object.fromEntries(answers.flatMap(([same, different], index) => [[`same__${index}`, { type: "noul", noul: same }], [`different__${index}`, { type: "noul", noul: different }]])),
  });

  it("肯定が高く否定が低い候補だけを同じ個体とし、揺れ (両方高い・両方低い) は別の物として扱う", () => {
    expect(
      sameSubjectCandidateIds({
        responses: [response([[0.9, 0.05], [0.8, 0.8], [0.2, 0.1], [0.66, 0.34]])],
        candidates,
        thresholds: DEDUPE_THRESHOLDS,
      }),
    ).toEqual(["a", "d"]);
  });

  it("較正 (2026-10-28) の同じ物の境目 (本番で撮り直したマグカップ) は同じ個体とし、同じ種類の別の物の境目は別の物とする", () => {
    expect(
      sameSubjectCandidateIds({
        responses: [response([[0.66, 0.35], [0.71, 0.37], [0.49, 0.54], [0.4, 0.52]])],
        candidates,
        thresholds: DEDUPE_THRESHOLDS,
      }),
    ).toEqual(["b", "a"]);
  });
});

describe("buildJudgeRequest / readJudgeResponse", () => {
  it("属性ごとの Noul とステータスの Score を 1 リクエストに入れ、同じ帯に技が 2 つ以上ある属性に Choice を付ける", () => {
    const request = buildJudgeRequest({ description, elementTypes: master.elementTypes, moves: master.moves, statGrades: master.statGrades });
    expect(Object.keys(request.questions).filter((name) => name.startsWith("element__"))).toHaveLength(master.elementTypes.length);
    expect(Object.keys(request.questions).filter((name) => name.startsWith("stat__"))).toHaveLength(4);
    // master は全属性が Lv.1 の帯に技を 4 つ持つ
    expect(Object.keys(request.questions).filter((name) => name.startsWith("move__"))).toHaveLength(master.elementTypes.length);
  });

  it("技が 1 帯 1 件の属性には Choice を付けない", () => {
    const oneMovePerBand = master.moves.filter((move) => /_\d$/.test(move.id));
    const request = buildJudgeRequest({ description, elementTypes: master.elementTypes, moves: oneMovePerBand, statGrades: master.statGrades });
    expect(Object.keys(request.questions).filter((name) => name.startsWith("move__"))).toHaveLength(0);
  });

  it("Score は確率が最も高い段階を採る", () => {
    const score = (best: string) => ({
      type: "score" as const,
      score: 2,
      confidence: 0.5,
      probabilities: Object.fromEntries(master.statGrades.map((grade) => [grade.displayName, grade.displayName === best ? 0.6 : 0.1])),
    });
    const judged = readJudgeResponse({
      statGrades: master.statGrades,
      response: {
        model: "jev-1.13.0",
        usage: { input_tokens: 0, output_tokens: 0 },
        answers: {
          element__metal: { type: "noul", noul: 0.8 },
          stat__hitPoints: score("とても低い"),
          stat__attack: score("とても高い"),
          stat__defense: score("ふつう"),
          stat__speed: score("高い"),
        },
      },
    });
    expect(judged.elementProbabilities).toEqual({ metal: 0.8 });
    // 属性の答えが 1 つも無い応答は判定待ちに回す
    expect(() =>
      readJudgeResponse({ statGrades: master.statGrades, response: { model: "jev-1.13.0", usage: { input_tokens: 0, output_tokens: 0 }, answers: {} } }),
    ).toThrow(JevUnavailableError);
    expect(judged.statGradeIds).toEqual({ hitPoints: "veryLow", attack: "veryHigh", defense: "medium", speed: "high" });
  });
});

describe("createAskJev", () => {
  const request = buildJudgeRequest({ description, elementTypes: master.elementTypes, moves: master.moves, statGrades: master.statGrades });

  it("HTTP エラー・通信エラーは JevUnavailableError にする", async () => {
    const failing = createAskJev({ apiKey: "test", fetchFunction: async () => new Response("payment required", { status: 402 }) });
    await expect(failing(request)).rejects.toBeInstanceOf(JevUnavailableError);
    const offline = createAskJev({
      apiKey: "test",
      fetchFunction: async () => {
        throw new TypeError("fetch failed");
      },
    });
    await expect(offline(request)).rejects.toBeInstanceOf(JevUnavailableError);
  });

  it("422 (リクエストの形の誤り) は再試行しても直らないため JevUnavailableError にしない", async () => {
    const invalid = createAskJev({ apiKey: "test", fetchFunction: async () => new Response("{}", { status: 422 }) });
    await expect(invalid(request)).rejects.not.toBeInstanceOf(JevUnavailableError);
  });
});
