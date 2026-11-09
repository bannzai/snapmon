import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import {
  actionCardCreditsOf,
  actionCardRankOfProduct,
  computeMoveRanks,
  creditRankToRedeem,
  equippedMoveIds,
  fallbackMoveRank,
  previousDayKeys,
} from "../../src/action_card_rules";
import type { MasterMove } from "../../src/generation/master";
import type { LearnsetEntry } from "../../src/generation/monster_stats";

/** 端末の技の枠 (test/domain/battle/battle_engine_test.dart) と共通のテストケース。 */
const equippedMoveCases = (
  JSON.parse(readFileSync(resolve(__dirname, "../../../test/fixtures/equipped_move_cases.json"), "utf8")) as {
    cases: { name: string; learnset: LearnsetEntry[]; level: number; actionCardMoveIds: string[]; expectedMoveIds: string[] }[];
  }
).cases;

/** テスト用の技。指定しない値は段階 1 の技 (威力 40) にする。 */
function move(overrides: Partial<MasterMove> & { id: string }): MasterMove {
  return {
    displayName: overrides.id,
    elementTypeId: "fire",
    power: 40,
    powerPoints: 30,
    category: "attack",
    effectId: "fire_particle",
    learnableLevelMinimum: 1,
    learnableLevelMaximum: 30,
    ...overrides,
  };
}

describe("actionCardRankOfProduct", () => {
  it.each([
    ["snapmon_actioncardrank1_100yen", 1],
    ["snapmon_actioncardrank1_150yen", 1],
    ["snapmon_actioncardrank2_300yen", 2],
    ["snapmon_actioncardrank3_500yen", 3],
  ])("%s はランク %i", (productId, rank) => {
    expect(actionCardRankOfProduct(productId)).toBe(rank);
  });

  it.each([
    "snapmon_actioncardrank0_100yen",
    "snapmon_actioncardrank4_100yen",
    "snapmon_actioncardrank10_100yen",
    "snapmon_actioncardrank1",
    "xsnapmon_actioncardrank1_100yen",
    "snapmon_generationticket10_200yen",
  ])("%s は Action Card ではない", (productId) => {
    expect(actionCardRankOfProduct(productId)).toBeUndefined();
  });

  it("商品の識別子が無ければ Action Card ではない", () => {
    expect(actionCardRankOfProduct(null)).toBeUndefined();
  });
});

describe("equippedMoveIds", () => {
  it.each(equippedMoveCases)("$name", ({ learnset, level, actionCardMoveIds, expectedMoveIds }) => {
    expect(equippedMoveIds({ learnset, level, actionCardMoveIds })).toEqual(expectedMoveIds);
  });
});

describe("fallbackMoveRank", () => {
  it.each([
    ["段階 3 (威力 110)", move({ id: "m", power: 110 }), 3],
    ["自爆 (威力 200)", move({ id: "m", power: 200 }), 3],
    ["一撃必殺", move({ id: "m", power: 1, specialEffect: { oneHitKnockout: true, summary: "", rule: "" } }), 3],
    ["威力 109", move({ id: "m", power: 109 }), 2],
    ["段階 2 (威力 70)", move({ id: "m", power: 70 }), 2],
    ["先制", move({ id: "m", power: 40, priority: 1 }), 2],
    ["必中 (威力 60)", move({ id: "m", power: 60, specialEffect: { sureHit: true, summary: "", rule: "" } }), 2],
    ["威力 69", move({ id: "m", power: 69 }), 1],
    ["先制の度合い 0", move({ id: "m", power: 40, priority: 0 }), 1],
    ["補助技 (威力 0)", move({ id: "m", power: 0, category: "support" }), 1],
  ])("%s はランク %i", (_, target, rank) => {
    expect(fallbackMoveRank(target)).toBe(rank);
  });
});

describe("computeMoveRanks", () => {
  /** 威力 40 (予備のランク 1) の技 [count] 件。ID は m00, m01, ... */
  const plainMoves = (count: number) => Array.from({ length: count }, (_, index) => move({ id: `m${String(index).padStart(2, "0")}` }));

  it("10 件がすべて使われていれば使用回数の順に 2 件・3 件・5 件に分ける", () => {
    const moves = plainMoves(10);
    const usageCountByMoveId = Object.fromEntries(moves.map((target, index) => [target.id, 100 - index]));
    expect(computeMoveRanks({ moves, usageCountByMoveId })).toEqual({
      m00: 3,
      m01: 3,
      m02: 2,
      m03: 2,
      m04: 2,
      m05: 1,
      m06: 1,
      m07: 1,
      m08: 1,
      m09: 1,
    });
  });

  it("割合の母数は使われていない技を含めた買える技の数で、境界の位置は切り捨て", () => {
    // 10 件のうち使われたのは 3 件。上位 2 件 (10 件の 20%) がランク 3、3 件目が 5 件目 (50%) までのランク 2
    const moves = plainMoves(10);
    expect(computeMoveRanks({ moves, usageCountByMoveId: { m00: 9, m01: 8, m02: 7 } })).toMatchObject({ m00: 3, m01: 3, m02: 2 });
  });

  it("使われた技でも並びが 50% より後ならランク 1", () => {
    // 4 件のうち 2 件 (50%) までがランク 2 以上で、ランク 3 は 4 件の 20% の切り捨てで 0 件
    const moves = plainMoves(4);
    expect(computeMoveRanks({ moves, usageCountByMoveId: { m00: 4, m01: 3, m02: 2, m03: 1 } })).toEqual({ m00: 2, m01: 2, m02: 1, m03: 1 });
  });

  it("使われていない技は並びの位置に関係なく段階で決める", () => {
    // 5 件のうち使われたのは m00 だけ。並びで上位 20% に入る位置が無くても、使用 0 の strong はランク 3、weak はランク 1
    const moves = [...plainMoves(1), move({ id: "strong", power: 110 }), move({ id: "middle", power: 70 }), move({ id: "weak1" }), move({ id: "weak2" })];
    expect(computeMoveRanks({ moves, usageCountByMoveId: { m00: 9 } })).toEqual({ m00: 3, strong: 3, middle: 2, weak1: 1, weak2: 1 });
  });

  it("どの技も使われていなければすべて段階で決める", () => {
    const moves = [move({ id: "weak" }), move({ id: "strong", power: 110 }), move({ id: "middle", power: 70 })];
    expect(computeMoveRanks({ moves, usageCountByMoveId: {} })).toEqual({ weak: 1, strong: 3, middle: 2 });
  });

  it("使用回数が同じ技は境界をまたいでも技の ID の順に並べる", () => {
    const moves = plainMoves(5).reverse();
    // m00 と m01 が同じ回数で、ランク 3 の 1 件 (5 件の 20%) の境界をまたぐ
    expect(computeMoveRanks({ moves, usageCountByMoveId: { m00: 7, m01: 7, m02: 3, m03: 2, m04: 1 } })).toMatchObject({ m00: 3, m01: 2 });
  });

  it("使われた強い技でも使用の順のランクにし、段階のランクを使わない", () => {
    const moves = [...plainMoves(4), move({ id: "strong", power: 110 })];
    expect(computeMoveRanks({ moves, usageCountByMoveId: { m00: 50, m01: 40, m02: 30, m03: 20, strong: 1 } })).toMatchObject({ m00: 3, strong: 1 });
  });

  it("買える技に無い ID の使用回数は表に入れない", () => {
    expect(computeMoveRanks({ moves: plainMoves(1), usageCountByMoveId: { replaced: 99, constructor: 5 } })).toEqual({ m00: 1 });
  });
});

describe("creditRankToRedeem", () => {
  it("技のランクと同じランクのカードを使う", () => {
    expect(creditRankToRedeem({ moveRank: 2, actionCardCredits: { rank1: 1, rank2: 1, rank3: 1 } })).toBe(2);
  });

  it("同じランクが無ければ上の一番安いランクを使う", () => {
    expect(creditRankToRedeem({ moveRank: 1, actionCardCredits: { rank1: 0, rank2: 1, rank3: 1 } })).toBe(2);
  });

  it("下のランクのカードでは高い技を買えない", () => {
    expect(creditRankToRedeem({ moveRank: 3, actionCardCredits: { rank1: 5, rank2: 5, rank3: 0 } })).toBeUndefined();
  });
});

describe("actionCardCreditsOf", () => {
  it("無いランクと数でない値は 0 枚", () => {
    expect(actionCardCreditsOf({ rank2: 3, rank3: "1" })).toEqual({ rank1: 0, rank2: 3, rank3: 0 });
    expect(actionCardCreditsOf(undefined)).toEqual({ rank1: 0, rank2: 0, rank3: 0 });
  });
});

describe("previousDayKeys", () => {
  it("日本時間の前日から遡った日付を返し、当日を含めない", () => {
    // 2026-11-09 04:00 (日本時間)
    expect(previousDayKeys({ now: new Date("2026-11-08T19:00:00Z"), days: 3 })).toEqual(["2026-11-08", "2026-11-07", "2026-11-06"]);
  });
});
