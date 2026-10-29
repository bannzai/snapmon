import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it, vi } from "vitest";

import type { MonsterDocument } from "../../src/generation/records";
import { handleReportCreated } from "../../src/pvp";
import {
  DISPLAY_NAME_MAX_LENGTH,
  type ReportDocument,
  defaultDisplayName,
  displayNameOf,
  publicMonster,
  reportNotificationText,
  selectOpponents,
  validateDisplayName,
} from "../../src/pvp_rules";
import { postSlackMessage } from "../../src/slack";

/** 図鑑のモンスターのドキュメント。他人に返してはいけない値は見分けられる文字列にする。 */
function monsterDocument(): MonsterDocument {
  return {
    definition: {
      id: "monster-1",
      sourcePhotoReference: "users/owner-1/photos/secret-photo-request",
      name: "マグモン",
      encyclopediaText: "まいにち あたたかい のみものを はこぶ",
      elementTypeIds: ["heat"],
      learnset: [{ moveId: "warm-touch", unlockLevel: 1 }],
      baseStats: { hitPoints: 50, attack: 50, defense: 50, speed: 50 },
      individualValues: { hitPoints: 1, attack: 2, defense: 3, speed: 4 },
      statCalculationVersion: 1,
      masterVersion: 1,
    },
    level: 7,
    experience: 6,
    artPath: "monsters/monster-1/art.png",
    decoration: { eyes: "round", mouth: "smile", limbs: "stubby", aura: "soft", outlineColor: "#000000" } as never,
    decorationVersion: 1,
    subjectDescription: { what: "secret-subject-description" } as never,
    categoryIds: ["secret-category"],
    definitionIds: ["definition-1"],
    generationRequestId: "secret-generation-request",
    createdAt: Timestamp.fromMillis(0),
  };
}

describe("selectOpponents", () => {
  it("手持ちの平均レベルが近い順に 3 人を選び、空の手持ちは選ばない", () => {
    expect(
      selectOpponents({
        candidates: [
          { uid: "far", partyLevels: [40] },
          { uid: "empty", partyLevels: [] },
          { uid: "near", partyLevels: [9, 11] },
          { uid: "middle", partyLevels: [15] },
          { uid: "exact", partyLevels: [10] },
        ],
        playerAverageLevel: 10,
      }),
    ).toEqual(["near", "exact", "middle"]);
  });

  it("差が同じ時は渡した順 (手持ちを変えた新しい順) を保つ", () => {
    expect(
      selectOpponents({
        candidates: [
          { uid: "newer-above", partyLevels: [12] },
          { uid: "older-below", partyLevels: [8] },
        ],
        playerAverageLevel: 10,
      }),
    ).toEqual(["newer-above", "older-below"]);
  });
});

describe("表示名", () => {
  it("既定の名前は uid から決まり、同じ uid なら同じ名前になる", () => {
    expect(defaultDisplayName("uid-1")).toMatch(/^トレーナー \d{4}$/);
    expect(defaultDisplayName("uid-1")).toBe(defaultDisplayName("uid-1"));
    expect(displayNameOf({ uid: "uid-1", storedDisplayName: undefined })).toBe(defaultDisplayName("uid-1"));
    expect(displayNameOf({ uid: "uid-1", storedDisplayName: "ばんざい" })).toBe("ばんざい");
  });

  it("前後の空白を除いて受け付ける", () => {
    expect(validateDisplayName("  ばんざい ")).toEqual({ displayName: "ばんざい" });
  });

  it("空・長すぎる・制御文字・禁止語は受け付けない", () => {
    for (const input of [undefined, 1, "", "   ", "あ".repeat(DISPLAY_NAME_MAX_LENGTH + 1), "ばん\nざい", "ばん​ざい", "ピカチュウ", "殺す人"]) {
      expect(validateDisplayName(input), String(input)).toHaveProperty("error");
    }
    expect(validateDisplayName("あ".repeat(DISPLAY_NAME_MAX_LENGTH))).toHaveProperty("displayName");
  });
});

describe("publicMonster", () => {
  it("元の写真の参照・被写体の説明・分類・生成の要求 ID を返さない", () => {
    const shown = publicMonster(monsterDocument());
    const shownText = JSON.stringify(shown);
    for (const secret of ["secret-photo-request", "photos/", "secret-subject-description", "secret-category", "secret-generation-request"]) {
      expect(shownText).not.toContain(secret);
    }
    expect(shown.definition).not.toHaveProperty("sourcePhotoReference");
    expect(shown).toMatchObject({ level: 7, artPath: "monsters/monster-1/art.png", definitionIds: ["definition-1"] });
    expect(shown.definition).toMatchObject({ id: "monster-1", name: "マグモン", elementTypeIds: ["heat"] });
  });
});

describe("通報の通知", () => {
  const report: ReportDocument = {
    reporterUid: "reporter-1",
    monsterOwnerUid: "owner-1",
    monsterId: "monster-1",
    monsterName: "マグモン",
    monsterArtPath: "monsters/monster-1/art.png",
    reason: "inappropriate_picture",
  };

  it("理由・モンスター・持ち主・通報した人を書いた文章を #snapmon-notification に送る", async () => {
    const sendMessage = vi.fn(async () => {});
    await handleReportCreated({ reportId: "reporter-1_monster-1", report, sendMessage });
    expect(sendMessage).toHaveBeenCalledWith({
      channel: "#snapmon-notification",
      text: reportNotificationText({ reportId: "reporter-1_monster-1", report }),
    });
    const text = reportNotificationText({ reportId: "reporter-1_monster-1", report });
    for (const expected of [
      "不適切な絵",
      "マグモン",
      "monster-1",
      "owner-1",
      "reporter-1",
      "reports/reporter-1_monster-1",
      "reportedMonsters/monster-1 を消す",
    ]) {
      expect(text).toContain(expected);
    }
  });

  it("本番以外のプロジェクトで動いても #snapmon-notification に送る", async () => {
    vi.stubEnv("GCLOUD_PROJECT", "demo-snapmon");
    vi.stubEnv("FIREBASE_CONFIG", JSON.stringify({ projectId: "demo-snapmon" }));
    try {
      const sendMessage = vi.fn(async () => {});
      await handleReportCreated({ reportId: "reporter-1_monster-1", report, sendMessage });
      expect(sendMessage).toHaveBeenCalledWith(expect.objectContaining({ channel: "#snapmon-notification" }));
    } finally {
      vi.unstubAllEnvs();
    }
  });
});

describe("postSlackMessage", () => {
  it("bot token で chat.postMessage にチャンネルと文章を送る", async () => {
    const fetchFunction = vi.fn(async () => new Response(JSON.stringify({ ok: true })));
    await postSlackMessage({ token: "xoxb-test", channel: "#snapmon-notification", text: "通報", fetchFunction });
    expect(fetchFunction).toHaveBeenCalledWith("https://slack.com/api/chat.postMessage", {
      method: "POST",
      headers: { "Content-Type": "application/json; charset=utf-8", Authorization: "Bearer xoxb-test" },
      body: JSON.stringify({ channel: "#snapmon-notification", text: "通報" }),
    });
  });

  it("Slack が ok: false を返したら例外を投げる", async () => {
    const fetchFunction = vi.fn(async () => new Response(JSON.stringify({ ok: false, error: "channel_not_found" })));
    await expect(postSlackMessage({ token: "xoxb-test", channel: "#x", text: "通報", fetchFunction })).rejects.toThrow(
      "channel_not_found",
    );
  });

  it("token が空なら送らずに例外を投げる", async () => {
    const fetchFunction = vi.fn(async () => new Response(JSON.stringify({ ok: true })));
    await expect(postSlackMessage({ token: "", channel: "#x", text: "通報", fetchFunction })).rejects.toThrow("SLACK_BOT_TOKEN");
    expect(fetchFunction).not.toHaveBeenCalled();
  });
});
