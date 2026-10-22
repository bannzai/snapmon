// Jev の閾値を、ラベル付きの見本 (test/fixtures/calibration/) で実測する。
// 本番と同じ問いの組み立て (lib/generation/jev.js) と同じモデルで、同じ入力を 2 回送り、問いごとの真のセルの最小値と偽のセルの最大値を出す
// (~/.claude/skills/jev/references/jev-question-design.md「閾値は問いごとにラベル付きサンプルの実測で決め」)。
// 結果は documents/game-rules.md「Jev の閾値」に写す。問いの文言・説明の prompt・モデルを変えたら測り直す。
//
// 使い方: npm run build && TYPESAFE_API_KEY=... node scripts/calibrate-jev.mjs
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import jev from "../lib/generation/jev.js";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
const fixtures = path.join(root, "test", "fixtures", "calibration");
const descriptions = JSON.parse(readFileSync(path.join(fixtures, "descriptions.json"), "utf8"));
const labels = JSON.parse(readFileSync(path.join(fixtures, "labels.json"), "utf8"));
const master = JSON.parse(readFileSync(path.join(root, "..", "assets", "master", "master.json"), "utf8"));

// JEV_API_KEY: jev skill の jev-ask.sh と同じく、TYPESAFE_API_KEY が無い時のフォールバックとして読む
const apiKey = process.env.TYPESAFE_API_KEY || process.env.JEV_API_KEY;
if (!apiKey) {
  console.error("TYPESAFE_API_KEY (か JEV_API_KEY) が無いため測れません");
  process.exit(2);
}
const askJev = jev.createAskJev({ apiKey, fetchFunction: fetch });
/** 同じ入力を送る回数 (揺れを測るため 2 回)。 */
const REPEAT_COUNT = 2;
let inputTokens = 0;

async function ask(request) {
  const response = await askJev(request);
  inputTokens += response.usage.input_tokens;
  return response;
}

// 属性: 見本ごとに判定の問いを送り、当てはまるべき属性 (真) と当てはまるべきでない属性 (偽) の確率を集める
const elementTrue = [];
const elementFalse = [];
const statGrades = {};
for (const [sampleId, label] of Object.entries(labels.elements)) {
  for (let round = 0; round < REPEAT_COUNT; round++) {
    const response = await ask(
      jev.buildJudgeRequest({ description: descriptions[sampleId].description, elementTypes: master.elementTypes, moves: master.moves, statGrades: master.statGrades }),
    );
    const judged = jev.readJudgeResponse({ response, statGrades: master.statGrades });
    for (const [elementTypeId, probability] of Object.entries(judged.elementProbabilities)) {
      if (label.expected.includes(elementTypeId)) {
        elementTrue.push({ sampleId, round, elementTypeId, probability });
      } else if (!label.acceptable.includes(elementTypeId)) {
        elementFalse.push({ sampleId, round, elementTypeId, probability });
      }
    }
    statGrades[sampleId] = [...(statGrades[sampleId] ?? []), judged.statGradeIds];
  }
}

// 同じ被写体: 対ごとに肯定・否定の問いを送る
const dedupeRows = [];
for (const [kind, pairs] of [["same", labels.dedupe.same], ["differentSameKind", labels.dedupe.differentSameKind], ["differentKind", labels.dedupe.differentKind]]) {
  for (const [leftId, rightId] of pairs) {
    for (let round = 0; round < REPEAT_COUNT; round++) {
      const [response] = await Promise.all(
        jev.buildDedupeRequests({ description: descriptions[leftId].description, candidates: [{ candidateId: rightId, description: descriptions[rightId].description }] }).map(ask),
      );
      dedupeRows.push({ kind, leftId, rightId, round, same: response.answers.same__0.noul, different: response.answers.different__0.noul });
    }
  }
}

// 分類: 上位 3 件を目視用に出す (閾値は持たない)
const categories = {};
for (const sampleId of Object.keys(descriptions)) {
  const response = await ask(jev.buildClassifyRequest({ description: descriptions[sampleId].description, visionLabels: [], subjectCategories: master.subjectCategories }));
  categories[sampleId] = jev.topCategoryIds({ response, count: 3 });
}

const minimum = (rows, key) => rows.reduce((best, row) => (row[key] < best[key] ? row : best));
const maximum = (rows, key) => rows.reduce((best, row) => (row[key] > best[key] ? row : best));
const sameRows = dedupeRows.filter((row) => row.kind === "same");
const differentRows = dedupeRows.filter((row) => row.kind !== "same");
console.log(
  JSON.stringify(
    {
      model: jev.JEV_MODEL,
      measuredAt: new Date().toISOString(),
      repeatCount: REPEAT_COUNT,
      element: {
        trueCount: elementTrue.length,
        falseCount: elementFalse.length,
        trueMinimum: minimum(elementTrue, "probability"),
        falseMaximum: maximum(elementFalse, "probability"),
        trueBelowHalf: elementTrue.filter((row) => row.probability < 0.5),
        falseAtLeastHalf: elementFalse.filter((row) => row.probability >= 0.5),
      },
      dedupe: {
        sameMinimumOfSame: minimum(sameRows, "same"),
        sameMaximumOfDifferent: maximum(sameRows, "different"),
        differentMaximumOfSame: maximum(differentRows, "same"),
        differentMinimumOfDifferent: minimum(differentRows, "different"),
        rows: dedupeRows,
      },
      statGrades,
      categories,
      inputTokens,
    },
    null,
    2,
  ),
);
