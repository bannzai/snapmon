import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";

import { type PvpBattleDocument, isRulesVersion, outcomeAfterReport, parsePvpAction, timeoutOutcome } from "../../src/pvp_battle_rules";

/** host-uid と guest-uid の進行中の対戦に、[overrides] の項目を上書きしたドキュメント。 */
function battleDocument(overrides: Partial<PvpBattleDocument>): PvpBattleDocument {
  return {
    host: { uid: "host-uid", displayName: "ホスト", iconPath: null, monsters: [] },
    guest: { uid: "guest-uid", displayName: "ゲスト", iconPath: null, monsters: [] },
    participantUids: ["host-uid", "guest-uid"],
    randomSeed: 1,
    battleDate: "2026-11-19",
    turns: [],
    turnSeconds: 60,
    turnDeadline: Timestamp.fromMillis(0),
    status: "active",
    winnerUid: null,
    finishReason: null,
    reportedWinnerUids: {},
    createdAt: Timestamp.fromMillis(0),
    ...overrides,
  };
}

describe("parsePvpAction", () => {
  it("技・わるあがき・交代の形を、決めた項目だけ写して返す", () => {
    expect(parsePvpAction({ kind: "move", moveID: "warm-touch", extra: "x" })).toEqual({ kind: "move", moveID: "warm-touch" });
    expect(parsePvpAction({ kind: "struggle", moveID: "warm-touch" })).toEqual({ kind: "struggle" });
    expect(parsePvpAction({ kind: "switch", memberIndex: 2, extra: 1 })).toEqual({ kind: "switch", memberIndex: 2 });
  });

  it("交代は手持ちの 0〜2 番目だけを受け付ける", () => {
    expect(parsePvpAction({ kind: "switch", memberIndex: 0 })).toEqual({ kind: "switch", memberIndex: 0 });
    expect(parsePvpAction({ kind: "switch", memberIndex: 3 })).toBeUndefined();
    expect(parsePvpAction({ kind: "switch", memberIndex: -1 })).toBeUndefined();
    expect(parsePvpAction({ kind: "switch", memberIndex: 1.5 })).toBeUndefined();
    expect(parsePvpAction({ kind: "switch", memberIndex: "1" })).toBeUndefined();
    expect(parsePvpAction({ kind: "switch" })).toBeUndefined();
  });

  it("技は空でない 200 文字までの ID だけを受け付ける", () => {
    expect(parsePvpAction({ kind: "move", moveID: "a".repeat(200) })).toEqual({ kind: "move", moveID: "a".repeat(200) });
    expect(parsePvpAction({ kind: "move", moveID: "a".repeat(201) })).toBeUndefined();
    expect(parsePvpAction({ kind: "move", moveID: "" })).toBeUndefined();
    expect(parsePvpAction({ kind: "move", moveID: 1 })).toBeUndefined();
    expect(parsePvpAction({ kind: "move" })).toBeUndefined();
  });

  it("決めていない種類と、オブジェクトでない値は受け付けない", () => {
    expect(parsePvpAction({ kind: "forfeit" })).toBeUndefined();
    expect(parsePvpAction({})).toBeUndefined();
    expect(parsePvpAction(null)).toBeUndefined();
    expect(parsePvpAction(undefined)).toBeUndefined();
    expect(parsePvpAction("struggle")).toBeUndefined();
  });
});

describe("isRulesVersion", () => {
  it("空でない 64 文字までの文字列だけを版として受け付ける", () => {
    expect(isRulesVersion("1")).toBe(true);
    expect(isRulesVersion("a".repeat(64))).toBe(true);
    expect(isRulesVersion("a".repeat(65))).toBe(false);
    expect(isRulesVersion("")).toBe(false);
    expect(isRulesVersion(1)).toBe(false);
    expect(isRulesVersion(undefined)).toBe(false);
  });
});

describe("timeoutOutcome", () => {
  it("行動を出したのが片方だけなら、出した側の勝ちで終える", () => {
    expect(timeoutOutcome({ submittedUids: ["guest-uid"] })).toEqual({ status: "finished", winnerUid: "guest-uid", finishReason: "timeout" });
    expect(timeoutOutcome({ submittedUids: ["host-uid"] })).toEqual({ status: "finished", winnerUid: "host-uid", finishReason: "timeout" });
  });

  it("どちらも出していなければ、勝敗を付けずに終える", () => {
    expect(timeoutOutcome({ submittedUids: [] })).toEqual({ status: "void", winnerUid: null, finishReason: "timeout" });
  });
});

describe("outcomeAfterReport", () => {
  it("進行中の対戦は、最初の報告の勝者で終える", () => {
    expect(outcomeAfterReport({ battle: battleDocument({}), reportedWinnerUid: "guest-uid" })).toEqual({
      status: "finished",
      winnerUid: "guest-uid",
      finishReason: "result",
    });
  });

  it("進行中の対戦への「決着していない」は何も変えない", () => {
    expect(outcomeAfterReport({ battle: battleDocument({}), reportedWinnerUid: null })).toBeUndefined();
  });

  it("報告で終わった対戦に同じ勝者の報告が届いても変えない", () => {
    expect(
      outcomeAfterReport({
        battle: battleDocument({ status: "finished", winnerUid: "host-uid", finishReason: "result" }),
        reportedWinnerUid: "host-uid",
      }),
    ).toBeUndefined();
  });

  it("報告で終わった対戦に、別の勝者・決着していないという報告が届いたら勝敗を付けない", () => {
    const battle = battleDocument({ status: "finished", winnerUid: "host-uid", finishReason: "result" });
    expect(outcomeAfterReport({ battle, reportedWinnerUid: "guest-uid" })).toEqual({ status: "void", winnerUid: null, finishReason: "mismatch" });
    expect(outcomeAfterReport({ battle, reportedWinnerUid: null })).toEqual({ status: "void", winnerUid: null, finishReason: "mismatch" });
  });

  it("期限切れで終わった対戦は、食い違う報告で変えない", () => {
    expect(
      outcomeAfterReport({
        battle: battleDocument({ status: "finished", winnerUid: "host-uid", finishReason: "timeout" }),
        reportedWinnerUid: "guest-uid",
      }),
    ).toBeUndefined();
  });

  it("勝敗を付けずに終わった対戦は、報告で変えない", () => {
    expect(
      outcomeAfterReport({
        battle: battleDocument({ status: "void", winnerUid: null, finishReason: "blocked" }),
        reportedWinnerUid: "host-uid",
      }),
    ).toBeUndefined();
  });
});
