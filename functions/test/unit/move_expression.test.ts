import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import { boundedProposedSpecialEffectPower, proposedSpecialEffectViolation } from "../../src/generation/prompts/propose_element";
import { MOVE_EXPRESSION_VARIABLE_NAMES, evaluateMoveExpression, moveExpressionViolation, parseMoveExpression } from "../../src/move_expression";

/** Dart の評価器のテスト (test/domain/battle/move_expression_test.dart) と共通のテストケース。 */
const fixture = JSON.parse(readFileSync(resolve(__dirname, "../../../test/fixtures/move_expression_cases.json"), "utf8")) as {
  variableNames: string[];
  variables: Record<string, number>;
  cases: { expression: string; expected: number | "error" }[];
};

/** `expression` を共通のテストケースの変数で評価した値。評価できなければ "error"。 */
function evaluateOrError(expression: string): number | "error" {
  try {
    return evaluateMoveExpression({ node: parseMoveExpression(expression), variables: fixture.variables });
  } catch {
    return "error";
  }
}

describe("evaluateMoveExpression", () => {
  it.each(fixture.cases)("$expression → $expected", ({ expression, expected }) => {
    expect(evaluateOrError(expression)).toBe(expected);
  });

  it("変数の一覧が共通のテストケースと一致する", () => {
    expect([...MOVE_EXPRESSION_VARIABLE_NAMES]).toEqual(fixture.variableNames);
    expect(Object.keys(fixture.variables)).toEqual(fixture.variableNames);
  });
});

describe("moveExpressionViolation", () => {
  it("一覧の変数だけを使う式を通し、未知の変数・文法の誤りを理由付きで返す", () => {
    expect(moveExpressionViolation("if(opponent.defense > self.attack, 150, 100)")).toBeUndefined();
    expect(moveExpressionViolation("if(opponent.armor > self.attack, 150, 100)")).toContain("opponent.armor");
    expect(moveExpressionViolation("if(1, 2)")).toContain("引数");
  });
});

describe("proposedSpecialEffectViolation", () => {
  it("見本の状況で 0〜200 に収まる式を通す", () => {
    expect(proposedSpecialEffectViolation({ specialEffect: { power: "if(opponent.defense > self.attack, 150, 100)", summary: "硬い相手に強い", rule: "条件を満たすと威力が上がる" }, powerPoints: 25 })).toBeUndefined();
    expect(
      proposedSpecialEffectViolation({
        specialEffect: { power: "100 + 100 * (move.maximumPowerPoints - move.remainingPowerPoints) / (move.maximumPowerPoints - 1)", summary: "PP が減るほど強い", rule: "条件を満たすと威力が上がる" },
        powerPoints: 25,
      }),
    ).toBeUndefined();
  });

  it("上限を超える・負になる・評価できない状況がある式と、長すぎる説明・規則を断る", () => {
    expect(proposedSpecialEffectViolation({ specialEffect: { power: "if(movesFirst, 201, 100)", summary: "先に動くと強い", rule: "条件を満たすと威力が上がる" }, powerPoints: 25 })).toContain("201");
    expect(proposedSpecialEffectViolation({ specialEffect: { power: "if(movesFirst, -1, 100)", summary: "先に動くと強い", rule: "条件を満たすと威力が上がる" }, powerPoints: 25 })).toContain("-1");
    expect(proposedSpecialEffectViolation({ specialEffect: { power: "100 / (self.hitPoints - 1)", summary: "先に動くと強い", rule: "条件を満たすと威力が上がる" }, powerPoints: 25 })).toContain("評価できない");
    expect(proposedSpecialEffectViolation({ specialEffect: { power: "hp", summary: "先に動くと強い", rule: "条件を満たすと威力が上がる" }, powerPoints: 25 })).toContain("hp");
    expect(proposedSpecialEffectViolation({ specialEffect: { power: "100", summary: "とても長い説明の文言になっています", rule: "条件を満たすと威力が上がる" }, powerPoints: 25 })).toContain("説明");
    expect(proposedSpecialEffectViolation({ specialEffect: { power: "100", summary: "先に動くと強い", rule: "あ".repeat(41) }, powerPoints: 25 })).toContain("規則");
    expect(proposedSpecialEffectViolation({ specialEffect: { power: "100", summary: "先に動くと強い", rule: "あ".repeat(40) }, powerPoints: 25 })).toBeUndefined();
  });
});

describe("boundedProposedSpecialEffectPower", () => {
  it("見本の状況の検査を通った式も、見本に無い高いレベルで 200 を超えない", () => {
    const power = "100 + 10 * self.level";
    expect(proposedSpecialEffectViolation({ specialEffect: { power, summary: "育つほど強い", rule: "レベルが高いほど威力が上がる" }, powerPoints: 25 })).toBeUndefined();
    const node = parseMoveExpression(boundedProposedSpecialEffectPower(power));
    expect(evaluateMoveExpression({ node, variables: { ...fixture.variables, "self.level": 20 } })).toBe(200);
    expect(evaluateMoveExpression({ node, variables: { ...fixture.variables, "self.level": 5 } })).toBe(150);
  });
});
