import { deleteApp as deleteAdminApp, getApps, initializeApp as initializeAdminApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously, signOut, type User } from "firebase/auth";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

import { updateMoveRanksWith } from "../../src/action_cards";
import type { MasterMove } from "../../src/generation/master";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// Action Card の callable (redeemActionCard・teachActionCardMove・forgetActionCardMove) を Auth・Firestore・Functions の Emulator で、
// ランクの計算 (updateMoveRanks の本体 updateMoveRanksWith) を Firestore の Emulator で確かめる。

const projectId = "demo-snapmon";
const functionsBaseUrl = `http://127.0.0.1:5001/${projectId}/asia-northeast1`;

// Functions の Emulator は App Check のトークンを検証せずに中身だけを読む (battle.test.ts と同じ署名の無い JWT)。
const fakeAppCheckToken = [
  Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ sub: "1:000000000000:web:emulator", aud: [`projects/${projectId}`] })).toString("base64url"),
  "",
].join(".");

const app = initializeApp({ projectId, apiKey: "demo-api-key" }, "action-cards-test");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
const adminApp = getApps().find((existing) => existing.name === "action-cards-admin-test") ?? initializeAdminApp({ projectId }, "action-cards-admin-test");
const firestore = getFirestore(adminApp);

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

/**
 * テスト用の master。weak は予備のランク 1、middle は 2、strong は 3。replaced は replacer に置き換えられた技 (買えない)。
 */
const master = {
  version: 1,
  moves: [
    move({ id: "weak" }),
    move({ id: "middle", power: 70 }),
    move({ id: "strong", power: 110 }),
    move({ id: "replaced" }),
    move({ id: "replacer", replacesMoveId: "replaced" }),
  ],
};

afterAll(async () => {
  await deleteApp(app);
  await deleteAdminApp(adminApp);
});

beforeEach(async () => {
  await signOut(auth);
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
  await firestore.doc(`master/${master.version}`).set(master);
});

/** 匿名ログインしたユーザーと、`users/{uid}` (Action Card の残高 [credits]) と図鑑のモンスター m1 を置く。 */
async function signInUser({ credits = {} }: { credits?: Record<string, number> } = {}): Promise<User> {
  const user = (await signInAnonymously(auth)).user;
  await firestore.doc(`users/${user.uid}`).set({ actionCardCredits: credits });
  await firestore.doc(`users/${user.uid}/monsters/m1`).set({ name: "m1", level: 1, experience: 0 });
  return user;
}

/** Functions の callable [name] を [user] で呼び、HTTP の状態コードと本文を返す。 */
async function callFunction({ name, user, data }: { name: string; user: User; data: unknown }): Promise<{ status: number; body: any }> {
  const response = await fetch(`${functionsBaseUrl}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${await user.getIdToken()}`,
      "X-Firebase-AppCheck": fakeAppCheckToken,
    },
    body: JSON.stringify({ data }),
  });
  return { status: response.status, body: await response.json() };
}

/** [uid] の Action Card の残高。 */
async function creditsOf(uid: string): Promise<unknown> {
  return (await firestore.doc(`users/${uid}`).get()).get("actionCardCredits");
}

describe("redeemActionCard", () => {
  it("ランクの表のランクのカードを 1 枚使って技を買い切る", async () => {
    const user = await signInUser({ credits: { rank1: 1, rank2: 1 } });
    await firestore.doc("moveRanks/current").set({ version: 1, rankByMoveId: { weak: 2 }, usageWindowDays: 7 });

    const { status, body } = await callFunction({ name: "redeemActionCard", user, data: { moveId: "weak" } });
    expect(status).toBe(200);
    expect(body.result).toEqual({ moveId: "weak", rank: 2, creditRank: 2, actionCardCredits: { rank1: 1, rank2: 0, rank3: 0 } });
    expect(await creditsOf(user.uid)).toEqual({ rank1: 1, rank2: 0 });
    expect((await firestore.doc(`users/${user.uid}/actionCards/weak`).get()).data()).toMatchObject({ moveId: "weak", rank: 2 });
  });

  it("同じランクのカードが無ければ上のランクのカードで買える", async () => {
    const user = await signInUser({ credits: { rank3: 1 } });
    const { status, body } = await callFunction({ name: "redeemActionCard", user, data: { moveId: "weak" } });
    expect(status).toBe(200);
    // ランクの表が無いため、段階で決める予備のランク 1
    expect(body.result).toMatchObject({ rank: 1, creditRank: 3 });
    expect(await creditsOf(user.uid)).toEqual({ rank3: 0 });
  });

  it("ランクの表に無い技は段階で決める予備のランクにする (strong は 3 のため、ランク 2 のカードでは買えない)", async () => {
    const user = await signInUser({ credits: { rank2: 1 } });
    await firestore.doc("moveRanks/current").set({ version: 1, rankByMoveId: { weak: 1 }, usageWindowDays: 7 });
    const { status, body } = await callFunction({ name: "redeemActionCard", user, data: { moveId: "strong" } });
    expect(status).toBe(400);
    expect(body.error).toMatchObject({ status: "FAILED_PRECONDITION", details: { actionCardCredits: { rank1: 0, rank2: 1, rank3: 0 } } });
  });

  it("使えるカードが無ければ failed-precondition で、残高を変えずに残高を返す", async () => {
    const user = await signInUser({ credits: { rank1: 2 } });
    const { status, body } = await callFunction({ name: "redeemActionCard", user, data: { moveId: "middle" } });
    expect(status).toBe(400);
    expect(body.error).toMatchObject({ status: "FAILED_PRECONDITION", details: { actionCardCredits: { rank1: 2, rank2: 0, rank3: 0 } } });
    expect(await creditsOf(user.uid)).toEqual({ rank1: 2 });
    expect((await firestore.doc(`users/${user.uid}/actionCards/middle`).get()).exists).toBe(false);
  });

  it("既に持っている技は already-exists で、2 回目はカードを減らさない", async () => {
    const user = await signInUser({ credits: { rank1: 2 } });
    expect((await callFunction({ name: "redeemActionCard", user, data: { moveId: "weak" } })).status).toBe(200);
    const { status, body } = await callFunction({ name: "redeemActionCard", user, data: { moveId: "weak" } });
    expect(status).toBe(409);
    expect(body.error).toMatchObject({ status: "ALREADY_EXISTS", details: { actionCardCredits: { rank1: 1, rank2: 0, rank3: 0 } } });
    expect(await creditsOf(user.uid)).toEqual({ rank1: 1 });
  });

  it.each(["replaced", "unknown"])("置き換えられた技・master に無い技 (%s) は not-found", async (moveId) => {
    const user = await signInUser({ credits: { rank3: 1 } });
    expect((await callFunction({ name: "redeemActionCard", user, data: { moveId } })).status).toBe(404);
    expect(await creditsOf(user.uid)).toEqual({ rank3: 1 });
  });

  it("置き換えた側の技は買える", async () => {
    const user = await signInUser({ credits: { rank1: 1 } });
    expect((await callFunction({ name: "redeemActionCard", user, data: { moveId: "replacer" } })).status).toBe(200);
  });

  it("moveId が無ければ invalid-argument", async () => {
    const user = await signInUser({ credits: { rank1: 1 } });
    expect((await callFunction({ name: "redeemActionCard", user, data: {} })).status).toBe(400);
  });

  it("アカウントの削除が始まったユーザーは断る", async () => {
    const user = await signInUser({ credits: { rank1: 1 } });
    await firestore.doc(`users/${user.uid}`).update({ accountDeletionStartedAt: new Date() });
    expect((await callFunction({ name: "redeemActionCard", user, data: { moveId: "weak" } })).status).toBe(400);
    expect((await firestore.doc(`users/${user.uid}/actionCards/weak`).get()).exists).toBe(false);
  });
});

describe("teachActionCardMove・forgetActionCardMove", () => {
  /** [user] に技 [moveId] を買い切った状態を置く。 */
  async function seedActionCard({ user, moveId }: { user: User; moveId: string }): Promise<void> {
    await firestore.doc(`users/${user.uid}/actionCards/${moveId}`).set({ moveId, rank: 1, redeemedAt: new Date() });
  }

  /** [uid] のモンスター [monsterId] の actionCardMoveIds。 */
  async function actionCardMoveIdsOf({ uid, monsterId }: { uid: string; monsterId: string }): Promise<unknown> {
    return (await firestore.doc(`users/${uid}/monsters/${monsterId}`).get()).get("actionCardMoveIds");
  }

  it("覚えさせた順で末尾に足し、同じ技を 2 回覚えさせても 1 つだけにする", async () => {
    const user = await signInUser();
    await seedActionCard({ user, moveId: "weak" });
    await seedActionCard({ user, moveId: "strong" });

    expect((await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "strong" } })).body.result).toEqual({
      actionCardMoveIds: ["strong"],
    });
    await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } });
    expect((await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "strong" } })).body.result).toEqual({
      actionCardMoveIds: ["strong", "weak"],
    });
    expect(await actionCardMoveIdsOf({ uid: user.uid, monsterId: "m1" })).toEqual(["strong", "weak"]);
  });

  it("1 つの買い切った技を何体にでも覚えさせられる", async () => {
    const user = await signInUser();
    await firestore.doc(`users/${user.uid}/monsters/m2`).set({ name: "m2", level: 1, experience: 0 });
    await seedActionCard({ user, moveId: "weak" });
    await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } });
    await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m2", moveId: "weak" } });
    expect(await actionCardMoveIdsOf({ uid: user.uid, monsterId: "m1" })).toEqual(["weak"]);
    expect(await actionCardMoveIdsOf({ uid: user.uid, monsterId: "m2" })).toEqual(["weak"]);
  });

  it("買い切っていない技は failed-precondition", async () => {
    const user = await signInUser();
    const { status, body } = await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } });
    expect(status).toBe(400);
    expect(body.error.status).toBe("FAILED_PRECONDITION");
    expect(await actionCardMoveIdsOf({ uid: user.uid, monsterId: "m1" })).toBeUndefined();
  });

  it("他人のモンスターには覚えさせられず、忘れさせられない", async () => {
    const user = await signInUser();
    await seedActionCard({ user, moveId: "weak" });
    await firestore.doc("users/bob/monsters/m-bob").set({ name: "m-bob", level: 1, experience: 0, actionCardMoveIds: ["weak"] });

    expect((await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m-bob", moveId: "weak" } })).status).toBe(404);
    expect((await callFunction({ name: "forgetActionCardMove", user, data: { monsterId: "m-bob", moveId: "weak" } })).status).toBe(404);
    expect(await actionCardMoveIdsOf({ uid: "bob", monsterId: "m-bob" })).toEqual(["weak"]);
  });

  it("忘れさせても買い切った技は残り、覚え直せる。覚えていない技を忘れさせても変えない", async () => {
    const user = await signInUser();
    await seedActionCard({ user, moveId: "weak" });
    await seedActionCard({ user, moveId: "strong" });
    await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } });
    await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "strong" } });

    expect((await callFunction({ name: "forgetActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } })).body.result).toEqual({
      actionCardMoveIds: ["strong"],
    });
    expect((await callFunction({ name: "forgetActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } })).body.result).toEqual({
      actionCardMoveIds: ["strong"],
    });
    expect((await firestore.doc(`users/${user.uid}/actionCards/weak`).get()).exists).toBe(true);
    await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } });
    expect(await actionCardMoveIdsOf({ uid: user.uid, monsterId: "m1" })).toEqual(["strong", "weak"]);
  });

  it("monsterId か moveId が無ければ invalid-argument", async () => {
    const user = await signInUser();
    expect((await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1" } })).status).toBe(400);
    expect((await callFunction({ name: "forgetActionCardMove", user, data: { moveId: "weak" } })).status).toBe(400);
  });
});

describe("updateMoveRanksWith", () => {
  // 2026-11-09 04:00 (日本時間)
  const now = new Date("2026-11-08T19:00:00Z");

  it("前日から 7 日分の使用回数を合計して、買える技のランクを書く", async () => {
    // 当日 (11-09) と 8 日前 (11-01) の分は数えない
    await firestore.doc("moveUsageDailyCounts/2026-11-09").set({ counts: { strong: 1000 } });
    await firestore.doc("moveUsageDailyCounts/2026-11-01").set({ counts: { strong: 1000 } });
    await firestore.doc("moveUsageDailyCounts/2026-11-08").set({ counts: { weak: 3, middle: 1, replaced: 50 } });
    await firestore.doc("moveUsageDailyCounts/2026-11-02").set({ counts: { middle: 1 } });

    const written = await updateMoveRanksWith({ firestore, now });
    const stored = (await firestore.doc("moveRanks/current").get()).data();
    expect(stored).toMatchObject({ version: 1, usageWindowDays: 7 });
    expect(stored?.computedAt.toDate()).toEqual(now);
    // 使われた技は weak (3) と middle (2) の 2 件で、上位 20% (0 件)・30% (0 件) の後のランク 1。
    // strong (使われていない) と replacer は段階で決める。置き換えられた replaced は表に入れない
    expect(stored?.rankByMoveId).toEqual({ weak: 1, middle: 1, strong: 3, replacer: 1 });
    expect(written.rankByMoveId).toEqual(stored?.rankByMoveId);
  });

  it("集計が無ければすべて段階で決め、同じ入力で 2 回動かしても同じ表を書く", async () => {
    await updateMoveRanksWith({ firestore, now });
    await updateMoveRanksWith({ firestore, now });
    expect((await firestore.doc("moveRanks/current").get()).get("rankByMoveId")).toEqual({ weak: 1, middle: 2, strong: 3, replacer: 1 });
  });

  it("最新の版の master の技でランクを決める", async () => {
    await firestore.doc("master/2").set({ version: 2, moves: [move({ id: "weak" }), move({ id: "newcomer", power: 120 })] });
    expect((await updateMoveRanksWith({ firestore, now })).version).toBe(2);
    expect((await firestore.doc("moveRanks/current").get()).get("rankByMoveId")).toEqual({ weak: 1, newcomer: 3 });
  });
});
