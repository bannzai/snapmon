import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import {
  CHEAP_ACTION_CARD_PRODUCT_ID,
  EXPENSIVE_ACTION_CARD_PRODUCT_ID,
  MODERATE_ACTION_CARD_PRODUCT_ID,
  computeActionCardProductIDByMoveID,
  equippedMoveIDs,
  fallbackActionCardProductID,
  isActionCardProductID,
  previousDayKeys,
} from "../../src/action_card_rules";
import type { MasterMove } from "../../src/generation/master";
import type { LearnsetEntry } from "../../src/generation/monster_stats";

/** 端末の技の枠 (test/domain/battle/battle_engine_test.dart) と共通のテストケース。 */
const equippedMoveCases = (
  JSON.parse(readFileSync(resolve(__dirname, "../../../test/fixtures/equipped_move_cases.json"), "utf8")) as {
    cases: { name: string; learnset: LearnsetEntry[]; level: number; actionCardMoveIDs: string[]; expectedMoveIDs: string[] }[];
  }
).cases;

/** テスト用の技。指定しない値は段階 1 の技 (威力 40) にする。 */
function move(overrides: Partial<MasterMove> & { id: string }): MasterMove {
  return {
    displayName: overrides.id,
    elementTypeID: "fire",
    power: 40,
    powerPoints: 30,
    category: "attack",
    effectID: "fire_particle",
    learnableLevelMinimum: 1,
    learnableLevelMaximum: 30,
    ...overrides,
  };
}

describe("isActionCardProductID", () => {
  it.each([CHEAP_ACTION_CARD_PRODUCT_ID, MODERATE_ACTION_CARD_PRODUCT_ID, EXPENSIVE_ACTION_CARD_PRODUCT_ID])("%s は Action Card の商品", (productID) => {
    expect(isActionCardProductID(productID)).toBe(true);
  });

  it.each([
    // 価格の部分だけが違う商品は、ストアに無い商品のため受け付けない (Google Play で 100 円を設定できたため 150 円の商品は作っていない。DIRECTION.md の #272 の行)
    "snapmon_actioncardrank1_150yen",
    "snapmon_actioncardrank4_100yen",
    "snapmon_actioncardrank1",
    "xsnapmon_actioncardrank1_100yen",
    "snapmon_actioncardrank1_100yenx",
    "snapmon_generationticket10_200yen",
  ])("%s は Action Card の商品ではない", (productID) => {
    expect(isActionCardProductID(productID)).toBe(false);
  });

  it("商品の識別子が無ければ Action Card の商品ではない", () => {
    expect(isActionCardProductID(null)).toBe(false);
  });
});

describe("equippedMoveIDs", () => {
  it.each(equippedMoveCases)("$name", ({ learnset, level, actionCardMoveIDs, expectedMoveIDs }) => {
    expect(equippedMoveIDs({ learnset, level, actionCardMoveIDs })).toEqual(expectedMoveIDs);
  });
});

describe("fallbackActionCardProductID", () => {
  it.each([
    ["段階 3 (威力 110)", move({ id: "m", power: 110 }), EXPENSIVE_ACTION_CARD_PRODUCT_ID],
    ["自爆 (威力 200)", move({ id: "m", power: 200 }), EXPENSIVE_ACTION_CARD_PRODUCT_ID],
    ["一撃必殺", move({ id: "m", power: 1, specialEffect: { oneHitKnockout: true, summary: "", rule: "" } }), EXPENSIVE_ACTION_CARD_PRODUCT_ID],
    ["威力 109", move({ id: "m", power: 109 }), MODERATE_ACTION_CARD_PRODUCT_ID],
    ["段階 2 (威力 70)", move({ id: "m", power: 70 }), MODERATE_ACTION_CARD_PRODUCT_ID],
    ["先制", move({ id: "m", power: 40, priority: 1 }), MODERATE_ACTION_CARD_PRODUCT_ID],
    ["必中 (威力 60)", move({ id: "m", power: 60, specialEffect: { sureHit: true, summary: "", rule: "" } }), MODERATE_ACTION_CARD_PRODUCT_ID],
    ["威力 69", move({ id: "m", power: 69 }), CHEAP_ACTION_CARD_PRODUCT_ID],
    ["先制の度合い 0", move({ id: "m", power: 40, priority: 0 }), CHEAP_ACTION_CARD_PRODUCT_ID],
    ["補助技 (威力 0)", move({ id: "m", power: 0, category: "support" }), CHEAP_ACTION_CARD_PRODUCT_ID],
  ])("%s は %s", (_, target, productID) => {
    expect(fallbackActionCardProductID(target)).toBe(productID);
  });
});

describe("computeActionCardProductIDByMoveID", () => {
  /** 威力 40 (予備の商品が 100 円) の技 [count] 件。ID は m00, m01, ... */
  const plainMoves = (count: number) => Array.from({ length: count }, (_, index) => move({ id: `m${String(index).padStart(2, "0")}` }));

  it("10 件がすべて使われていれば使用回数の順に 2 件・3 件・5 件に分ける", () => {
    const moves = plainMoves(10);
    const usageCountByMoveID = Object.fromEntries(moves.map((target, index) => [target.id, 100 - index]));
    expect(computeActionCardProductIDByMoveID({ moves, usageCountByMoveID })).toEqual({
      m00: EXPENSIVE_ACTION_CARD_PRODUCT_ID,
      m01: EXPENSIVE_ACTION_CARD_PRODUCT_ID,
      m02: MODERATE_ACTION_CARD_PRODUCT_ID,
      m03: MODERATE_ACTION_CARD_PRODUCT_ID,
      m04: MODERATE_ACTION_CARD_PRODUCT_ID,
      m05: CHEAP_ACTION_CARD_PRODUCT_ID,
      m06: CHEAP_ACTION_CARD_PRODUCT_ID,
      m07: CHEAP_ACTION_CARD_PRODUCT_ID,
      m08: CHEAP_ACTION_CARD_PRODUCT_ID,
      m09: CHEAP_ACTION_CARD_PRODUCT_ID,
    });
  });

  it("割合の母数は使われていない技を含めた買える技の数で、境界の位置は切り捨て", () => {
    // 10 件のうち使われたのは 3 件。上位 2 件 (10 件の 20%) が500 円、3 件目が 5 件目 (50%) までの300 円
    const moves = plainMoves(10);
    expect(computeActionCardProductIDByMoveID({ moves, usageCountByMoveID: { m00: 9, m01: 8, m02: 7 } })).toMatchObject({ m00: EXPENSIVE_ACTION_CARD_PRODUCT_ID, m01: EXPENSIVE_ACTION_CARD_PRODUCT_ID, m02: MODERATE_ACTION_CARD_PRODUCT_ID });
  });

  it("使われた技でも並びが 50% より後なら100 円", () => {
    // 4 件のうち 2 件 (50%) までが300 円 以上で、500 円 は 4 件の 20% の切り捨てで 0 件
    const moves = plainMoves(4);
    expect(computeActionCardProductIDByMoveID({ moves, usageCountByMoveID: { m00: 4, m01: 3, m02: 2, m03: 1 } })).toEqual({ m00: MODERATE_ACTION_CARD_PRODUCT_ID, m01: MODERATE_ACTION_CARD_PRODUCT_ID, m02: CHEAP_ACTION_CARD_PRODUCT_ID, m03: CHEAP_ACTION_CARD_PRODUCT_ID });
  });

  it("使われていない技は並びの位置に関係なく段階で決める", () => {
    // 5 件のうち使われたのは m00 だけ。並びで上位 20% に入る位置が無くても、使用 0 の strong は500 円、weak は100 円
    const moves = [...plainMoves(1), move({ id: "strong", power: 110 }), move({ id: "middle", power: 70 }), move({ id: "weak1" }), move({ id: "weak2" })];
    expect(computeActionCardProductIDByMoveID({ moves, usageCountByMoveID: { m00: 9 } })).toEqual({ m00: EXPENSIVE_ACTION_CARD_PRODUCT_ID, strong: EXPENSIVE_ACTION_CARD_PRODUCT_ID, middle: MODERATE_ACTION_CARD_PRODUCT_ID, weak1: CHEAP_ACTION_CARD_PRODUCT_ID, weak2: CHEAP_ACTION_CARD_PRODUCT_ID });
  });

  it("どの技も使われていなければすべて段階で決める", () => {
    const moves = [move({ id: "weak" }), move({ id: "strong", power: 110 }), move({ id: "middle", power: 70 })];
    expect(computeActionCardProductIDByMoveID({ moves, usageCountByMoveID: {} })).toEqual({ weak: CHEAP_ACTION_CARD_PRODUCT_ID, strong: EXPENSIVE_ACTION_CARD_PRODUCT_ID, middle: MODERATE_ACTION_CARD_PRODUCT_ID });
  });

  it("使用回数が同じ技は境界をまたいでも技の ID の順に並べる", () => {
    const moves = plainMoves(5).reverse();
    // m00 と m01 が同じ回数で、500 円 の 1 件 (5 件の 20%) の境界をまたぐ
    expect(computeActionCardProductIDByMoveID({ moves, usageCountByMoveID: { m00: 7, m01: 7, m02: 3, m03: 2, m04: 1 } })).toMatchObject({ m00: EXPENSIVE_ACTION_CARD_PRODUCT_ID, m01: MODERATE_ACTION_CARD_PRODUCT_ID });
  });

  it("使われた強い技でも使用の順の商品にし、段階の商品を使わない", () => {
    const moves = [...plainMoves(4), move({ id: "strong", power: 110 })];
    expect(computeActionCardProductIDByMoveID({ moves, usageCountByMoveID: { m00: 50, m01: 40, m02: 30, m03: 20, strong: 1 } })).toMatchObject({ m00: EXPENSIVE_ACTION_CARD_PRODUCT_ID, strong: CHEAP_ACTION_CARD_PRODUCT_ID });
  });

  it("買える技に無い ID の使用回数は表に入れない", () => {
    expect(computeActionCardProductIDByMoveID({ moves: plainMoves(1), usageCountByMoveID: { replaced: 99, constructor: 5 } })).toEqual({ m00: CHEAP_ACTION_CARD_PRODUCT_ID });
  });
});

describe("previousDayKeys", () => {
  it("日本時間の前日から遡った日付を返し、当日を含めない", () => {
    // 2026-11-09 04:00 (日本時間)
    expect(previousDayKeys({ now: new Date("2026-11-08T19:00:00Z"), days: 3 })).toEqual(["2026-11-08", "2026-11-07", "2026-11-06"]);
  });
});
