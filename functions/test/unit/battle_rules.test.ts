import { describe, expect, it } from "vitest";

import { MAXIMUM_LEVEL, battleDayKey, isMonsterIdList, isSubsetOfParty, levelAfterBattle } from "../../src/battle_rules";

describe("battleDayKey", () => {
  it("日本時間の 0 時で日付が変わる", () => {
    expect(battleDayKey({ now: new Date(Date.UTC(2026, 9, 21, 14, 59)) })).toBe("2026-10-21");
    expect(battleDayKey({ now: new Date(Date.UTC(2026, 9, 21, 15, 0)) })).toBe("2026-10-22");
  });
});

describe("isMonsterIdList", () => {
  it("重複の無い 1〜3 件の ID を通す", () => {
    expect(isMonsterIdList(["a"])).toBe(true);
    expect(isMonsterIdList(["a", "b", "c"])).toBe(true);
  });

  it("空・4 件以上・重複・文字列以外・パスの区切りを含む ID は通さない", () => {
    expect(isMonsterIdList([])).toBe(false);
    expect(isMonsterIdList(["a", "b", "c", "d"])).toBe(false);
    expect(isMonsterIdList(["a", "a"])).toBe(false);
    expect(isMonsterIdList([1])).toBe(false);
    expect(isMonsterIdList([""])).toBe(false);
    expect(isMonsterIdList(["a/b"])).toBe(false);
    expect(isMonsterIdList("a")).toBe(false);
  });
});

describe("isSubsetOfParty", () => {
  it("開始時の手持ちに無いモンスターがあれば通さない", () => {
    expect(isSubsetOfParty({ participantMonsterIds: ["a", "b"], partyMonsterIds: ["a", "b", "c"] })).toBe(true);
    expect(isSubsetOfParty({ participantMonsterIds: ["a", "x"], partyMonsterIds: ["a", "b", "c"] })).toBe(false);
  });
});

describe("levelAfterBattle", () => {
  it("1 上がり、上限で止まる", () => {
    expect(levelAfterBattle({ level: 1 })).toBe(2);
    expect(levelAfterBattle({ level: MAXIMUM_LEVEL })).toBe(MAXIMUM_LEVEL);
  });
});
