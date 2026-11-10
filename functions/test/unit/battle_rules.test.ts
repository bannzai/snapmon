import { describe, expect, it } from "vitest";

import { MAXIMUM_LEVEL, battleDayKey, isMonsterIDList, isSubsetOfParty, levelAfterBattle } from "../../src/battle_rules";

describe("battleDayKey", () => {
  it("日本時間の 0 時で日付が変わる", () => {
    expect(battleDayKey({ now: new Date(Date.UTC(2026, 9, 21, 14, 59)) })).toBe("2026-10-21");
    expect(battleDayKey({ now: new Date(Date.UTC(2026, 9, 21, 15, 0)) })).toBe("2026-10-22");
  });
});

describe("isMonsterIDList", () => {
  it("重複の無い 1〜3 件の ID を通す", () => {
    expect(isMonsterIDList(["a"])).toBe(true);
    expect(isMonsterIDList(["a", "b", "c"])).toBe(true);
  });

  it("空・4 件以上・重複・文字列以外・パスの区切りを含む ID は通さない", () => {
    expect(isMonsterIDList([])).toBe(false);
    expect(isMonsterIDList(["a", "b", "c", "d"])).toBe(false);
    expect(isMonsterIDList(["a", "a"])).toBe(false);
    expect(isMonsterIDList([1])).toBe(false);
    expect(isMonsterIDList([""])).toBe(false);
    expect(isMonsterIDList(["a/b"])).toBe(false);
    expect(isMonsterIDList("a")).toBe(false);
  });
});

describe("isSubsetOfParty", () => {
  it("開始時の手持ちに無いモンスターがあれば通さない", () => {
    expect(isSubsetOfParty({ participantMonsterIDs: ["a", "b"], partyMonsterIDs: ["a", "b", "c"] })).toBe(true);
    expect(isSubsetOfParty({ participantMonsterIDs: ["a", "x"], partyMonsterIDs: ["a", "b", "c"] })).toBe(false);
  });
});

describe("levelAfterBattle", () => {
  it("1 上がり、上限で止まる", () => {
    expect(levelAfterBattle({ level: 1 })).toBe(2);
    expect(levelAfterBattle({ level: MAXIMUM_LEVEL })).toBe(MAXIMUM_LEVEL);
  });
});
