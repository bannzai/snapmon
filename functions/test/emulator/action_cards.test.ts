import { deleteApp as deleteAdminApp, getApps, initializeApp as initializeAdminApp } from "firebase-admin/app";
import type { Auth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously, signOut, type User } from "firebase/auth";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

import { CHEAP_ACTION_CARD_PRODUCT_ID, EXPENSIVE_ACTION_CARD_PRODUCT_ID, MODERATE_ACTION_CARD_PRODUCT_ID } from "../../src/action_card_rules";
import { updateActionCardProductsWith } from "../../src/action_cards";
import { handleRevenueCatWebhook } from "../../src/generation_tickets";
import type { MasterMove } from "../../src/generation/master";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// Action Card の callable (reserveActionCardMove・assignActionCardMove・teachActionCardMove・forgetActionCardMove) を Auth・Firestore・Functions の
// Emulator で、購入の webhook (handleRevenueCatWebhook) が控えた技を購入に結び付けるのを Firestore の Emulator で、技に割り振る商品の計算 (updateActionCardProducts の本体 updateActionCardProductsWith) を Firestore の Emulator で確かめる。

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
 * テスト用の master。予備の商品は weak が [CHEAP_ACTION_CARD_PRODUCT_ID]、middle が [MODERATE_ACTION_CARD_PRODUCT_ID]、strong が [EXPENSIVE_ACTION_CARD_PRODUCT_ID]。replaced は replacer に置き換えられた技 (買えない)。
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

/** 匿名ログインしたユーザーと、`users/{uid}` と図鑑のモンスター m1 を置く。[withUserDocument] が false なら `users/{uid}` を置かない (生成する前のユーザー)。 */
async function signInUser({ withUserDocument = true }: { withUserDocument?: boolean } = {}): Promise<User> {
  const user = (await signInAnonymously(auth)).user;
  if (withUserDocument) {
    await firestore.doc(`users/${user.uid}`).set({ displayName: "tester" });
    await firestore.doc(`users/${user.uid}/monsters/m1`).set({ name: "m1", level: 1, experience: 0 });
  }
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

/** テストで RevenueCat に設定したことにする `Authorization` の値。 */
const WEBHOOK_AUTHORIZATION = "Bearer test-webhook-authorization";

/** どの uid も残っているユーザーとして返す Auth のモック (Auth の Emulator の匿名ユーザーで webhook を受けるため)。 */
const webhookAuth = { getUser: async (uid: string) => ({ uid }) } as unknown as Auth;

/**
 * [uid] が商品 [productID] の Action Card を購入した webhook (イベント [eventID]) を、端末を介さずに Functions の本体に渡す
 * (購入の後に端末が何も呼ばなくても技が手に入ることを確かめるため)。
 */
async function receivePurchase({ uid, productID, eventID = "event-1" }: { uid: string; productID: string; eventID?: string }): Promise<void> {
  const { status } = await handleRevenueCatWebhook(
    { firestore, auth: webhookAuth, sendMessage: async () => {}, expectedAuthorization: WEBHOOK_AUTHORIZATION, now: () => new Date() },
    {
      authorization: WEBHOOK_AUTHORIZATION,
      body: {
        api_version: "1.0",
        event: { id: eventID, type: "NON_RENEWING_PURCHASE", app_user_id: uid, product_id: productID, environment: "SANDBOX" },
      },
    },
  );
  expect(status).toBe(200);
}

/** [uid] の購入 [eventID] の記録。 */
async function purchaseOf({ uid, eventID = "event-1" }: { uid: string; eventID?: string }): Promise<Record<string, unknown> | undefined> {
  return (await firestore.doc(`users/${uid}/actionCardPurchases/${eventID}`).get()).data();
}

/** [uid] の `users/{uid}.actionCardMoveReservation`。 */
async function reservationOf(uid: string): Promise<unknown> {
  return (await firestore.doc(`users/${uid}`).get()).get("actionCardMoveReservation");
}

describe("技を選んで買う (reserveActionCardMove と webhook)", () => {
  it("控えた技を、購入の webhook だけで買い切った技にし、控えを消す", async () => {
    const user = await signInUser();
    await firestore.doc("actionCardProducts/current").set({ version: 1, productIDByMoveID: { weak: MODERATE_ACTION_CARD_PRODUCT_ID }, usageWindowDays: 7 });

    const { status, body } = await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "weak", productID: MODERATE_ACTION_CARD_PRODUCT_ID } });
    expect(status).toBe(200);
    expect(body.result).toMatchObject({ moveID: "weak", productID: MODERATE_ACTION_CARD_PRODUCT_ID });
    expect(await reservationOf(user.uid)).toMatchObject({ actionCardMoveReservationID: body.result.actionCardMoveReservationID, moveID: "weak", productID: MODERATE_ACTION_CARD_PRODUCT_ID });

    await receivePurchase({ uid: user.uid, productID: MODERATE_ACTION_CARD_PRODUCT_ID });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({
      productId: MODERATE_ACTION_CARD_PRODUCT_ID,
      moveID: "weak",
      actionCardMoveReservationID: body.result.actionCardMoveReservationID,
    });
    expect(await reservationOf(user.uid)).toBeUndefined();
    expect((await firestore.doc(`users/${user.uid}`).get()).get("actionCardCredits")).toBeUndefined();
    expect((await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } })).body.result).toEqual({
      actionCardMoveIds: ["weak"],
    });
  });

  it("控えてから購入が届くまでの間に技が高い商品に変わったら、技に結び付けずに購入を残す", async () => {
    const user = await signInUser();
    await firestore.doc("actionCardProducts/current").set({ version: 1, productIDByMoveID: { weak: CHEAP_ACTION_CARD_PRODUCT_ID }, usageWindowDays: 7 });
    const { body } = await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "weak", productID: CHEAP_ACTION_CARD_PRODUCT_ID } });
    await firestore.doc("actionCardProducts/current").set({ version: 1, productIDByMoveID: { weak: MODERATE_ACTION_CARD_PRODUCT_ID }, usageWindowDays: 7 });

    await receivePurchase({ uid: user.uid, productID: CHEAP_ACTION_CARD_PRODUCT_ID });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({
      productId: CHEAP_ACTION_CARD_PRODUCT_ID,
      moveID: null,
      actionCardMoveReservationID: body.result.actionCardMoveReservationID,
    });
    expect(await reservationOf(user.uid)).toBeUndefined();
    expect((await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } })).status).toBe(400);
  });

  it("控えてから購入が届くまでの間に技が安い商品に変わっても、技に結び付けずに購入を残す (買った商品と同じ商品の技だけを渡す)", async () => {
    const user = await signInUser();
    await firestore.doc("actionCardProducts/current").set({ version: 1, productIDByMoveID: { weak: EXPENSIVE_ACTION_CARD_PRODUCT_ID }, usageWindowDays: 7 });
    await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "weak", productID: EXPENSIVE_ACTION_CARD_PRODUCT_ID } });
    await firestore.doc("actionCardProducts/current").set({ version: 1, productIDByMoveID: { weak: CHEAP_ACTION_CARD_PRODUCT_ID }, usageWindowDays: 7 });
    await receivePurchase({ uid: user.uid, productID: EXPENSIVE_ACTION_CARD_PRODUCT_ID });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ productId: EXPENSIVE_ACTION_CARD_PRODUCT_ID, moveID: null });
  });

  it("控えてから購入が届くまでの間に同じ技を買い切っていたら、技に結び付けずに購入を残す (同じ技を 2 回持たない)", async () => {
    const user = await signInUser();
    await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "weak", productID: CHEAP_ACTION_CARD_PRODUCT_ID } });
    // 別の端末で同じ技を先に受け取った
    await firestore.doc(`users/${user.uid}/actionCardPurchases/event-0`).set({ productId: CHEAP_ACTION_CARD_PRODUCT_ID, moveID: "weak", createdAt: new Date() });

    await receivePurchase({ uid: user.uid, productID: CHEAP_ACTION_CARD_PRODUCT_ID });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ productId: CHEAP_ACTION_CARD_PRODUCT_ID, moveID: null });
    expect((await firestore.collection(`users/${user.uid}/actionCardPurchases`).where("moveID", "==", "weak").get()).size).toBe(1);
  });

  it("控えの商品と違う商品の購入は、控えを使わずに残して技に結び付けない", async () => {
    const user = await signInUser();
    const { body } = await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "middle", productID: MODERATE_ACTION_CARD_PRODUCT_ID } });
    await receivePurchase({ uid: user.uid, productID: CHEAP_ACTION_CARD_PRODUCT_ID });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ productId: CHEAP_ACTION_CARD_PRODUCT_ID, moveID: null, actionCardMoveReservationID: null });
    expect(await reservationOf(user.uid)).toMatchObject({ actionCardMoveReservationID: body.result.actionCardMoveReservationID });
  });

  it("商品の ID を持たない #293 より前の形の控えは使わず、購入を技に結び付けずに残す (利用者は購入から技を選び直せる)", async () => {
    const user = await signInUser();
    await firestore
      .doc(`users/${user.uid}`)
      .set({ actionCardMoveReservation: { actionCardMoveReservationID: "old-reservation", moveID: "weak", rank: 1, reservedAt: new Date() } }, { merge: true });
    await receivePurchase({ uid: user.uid, productID: CHEAP_ACTION_CARD_PRODUCT_ID });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ productId: CHEAP_ACTION_CARD_PRODUCT_ID, moveID: null, actionCardMoveReservationID: null });
    expect((await callFunction({ name: "assignActionCardMove", user, data: { actionCardPurchaseID: "event-1", moveID: "weak" } })).status).toBe(200);
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ moveID: "weak" });
  });

  it("控えが無い購入は技に結び付けずに残す", async () => {
    const user = await signInUser();
    await receivePurchase({ uid: user.uid, productID: EXPENSIVE_ACTION_CARD_PRODUCT_ID });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ productId: EXPENSIVE_ACTION_CARD_PRODUCT_ID, moveID: null, actionCardMoveReservationID: null });
  });

  it("新しい控えは前の控えを上書きする", async () => {
    const user = await signInUser();
    await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "weak", productID: CHEAP_ACTION_CARD_PRODUCT_ID } });
    await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "replacer", productID: CHEAP_ACTION_CARD_PRODUCT_ID } });
    await receivePurchase({ uid: user.uid, productID: CHEAP_ACTION_CARD_PRODUCT_ID });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ moveID: "replacer" });
  });

  it("端末が値段を出した商品と技の今の商品が違えば控えずに failed-precondition で、今の商品を返す", async () => {
    const user = await signInUser();
    await firestore.doc("actionCardProducts/current").set({ version: 1, productIDByMoveID: { weak: MODERATE_ACTION_CARD_PRODUCT_ID }, usageWindowDays: 7 });
    const { status, body } = await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "weak", productID: CHEAP_ACTION_CARD_PRODUCT_ID } });
    expect(status).toBe(400);
    expect(body.error).toMatchObject({ status: "FAILED_PRECONDITION", details: { productID: MODERATE_ACTION_CARD_PRODUCT_ID } });
    expect(await reservationOf(user.uid)).toBeUndefined();
  });

  it("商品の表に無い技は段階で決める予備の商品にする", async () => {
    const user = await signInUser();
    await firestore.doc("actionCardProducts/current").set({ version: 1, productIDByMoveID: { weak: CHEAP_ACTION_CARD_PRODUCT_ID }, usageWindowDays: 7 });
    expect((await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "strong", productID: EXPENSIVE_ACTION_CARD_PRODUCT_ID } })).body.result).toMatchObject({ productID: EXPENSIVE_ACTION_CARD_PRODUCT_ID });
  });

  it("既に買い切った技は already-exists で控えない", async () => {
    const user = await signInUser();
    await firestore.doc(`users/${user.uid}/actionCardPurchases/event-0`).set({ productId: CHEAP_ACTION_CARD_PRODUCT_ID, moveID: "weak", createdAt: new Date() });
    expect((await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "weak", productID: CHEAP_ACTION_CARD_PRODUCT_ID } })).status).toBe(409);
    expect(await reservationOf(user.uid)).toBeUndefined();
  });

  it.each(["replaced", "unknown"])("置き換えられた技・master に無い技 (%s) は not-found", async (moveID) => {
    const user = await signInUser();
    expect((await callFunction({ name: "reserveActionCardMove", user, data: { moveID, productID: CHEAP_ACTION_CARD_PRODUCT_ID } })).status).toBe(404);
  });

  it.each([
    { moveID: "weak" },
    { productID: CHEAP_ACTION_CARD_PRODUCT_ID },
    // 価格の部分だけが違う商品・ストアに無い商品は受け付けない
    { moveID: "weak", productID: "snapmon_actioncardrank1_150yen" },
    { moveID: "weak", productID: "snapmon_generationticket10_200yen" },
    { moveID: "weak", productID: 1 },
  ])("形が違う data (%o) は invalid-argument", async (data) => {
    const user = await signInUser();
    expect((await callFunction({ name: "reserveActionCardMove", user, data })).body.error.status).toBe("INVALID_ARGUMENT");
  });

  it("生成する前の (users/{uid} の無い) ユーザーも控えて買える", async () => {
    const user = await signInUser({ withUserDocument: false });
    expect((await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "weak", productID: CHEAP_ACTION_CARD_PRODUCT_ID } })).status).toBe(200);
    await receivePurchase({ uid: user.uid, productID: CHEAP_ACTION_CARD_PRODUCT_ID });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ moveID: "weak" });
  });

  it("アカウントの削除が始まったユーザーは断る", async () => {
    const user = await signInUser();
    await firestore.doc(`users/${user.uid}`).update({ accountDeletionStartedAt: new Date() });
    expect((await callFunction({ name: "reserveActionCardMove", user, data: { moveID: "weak", productID: CHEAP_ACTION_CARD_PRODUCT_ID } })).status).toBe(400);
    expect(await reservationOf(user.uid)).toBeUndefined();
  });
});

describe("技に結び付いていない購入で技を選び直す (assignActionCardMove)", () => {
  /** [user] に技に結び付いていない商品 [productID] の購入 event-1 を置く。[withoutMoveIDField] は #290 より前の、moveID のフィールドが無い購入。 */
  async function seedUnassignedPurchase({ user, productID, withoutMoveIDField = false }: { user: User; productID: string; withoutMoveIDField?: boolean }): Promise<void> {
    await firestore
      .doc(`users/${user.uid}/actionCardPurchases/event-1`)
      .set(
        withoutMoveIDField
          ? { productId: productID, createdAt: new Date() }
          : { productId: productID, moveID: null, actionCardMoveReservationID: null, moveAssignedAt: null, createdAt: new Date() },
      );
  }

  it("買った商品と同じ商品の技を結び付け、覚えさせられるようにする", async () => {
    const user = await signInUser();
    await seedUnassignedPurchase({ user, productID: CHEAP_ACTION_CARD_PRODUCT_ID });
    const { status, body } = await callFunction({ name: "assignActionCardMove", user, data: { actionCardPurchaseID: "event-1", moveID: "weak" } });
    expect(status).toBe(200);
    expect(body.result).toEqual({ actionCardPurchaseID: "event-1", moveID: "weak" });
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ productId: CHEAP_ACTION_CARD_PRODUCT_ID, moveID: "weak" });
    expect((await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } })).status).toBe(200);
  });

  it("moveID のフィールドが無い (#290 より前の) 購入も、技に結び付いていない購入として選び直せる", async () => {
    const user = await signInUser();
    await seedUnassignedPurchase({ user, productID: CHEAP_ACTION_CARD_PRODUCT_ID, withoutMoveIDField: true });
    expect((await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } })).status).toBe(400);
    expect((await callFunction({ name: "assignActionCardMove", user, data: { actionCardPurchaseID: "event-1", moveID: "weak" } })).status).toBe(200);
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ moveID: "weak" });
  });

  it.each([
    ["高い", "strong"],
    ["安い", "weak"],
  ])("買った商品より%s商品の技 (%s) は failed-precondition で、購入を変えない", async (_, moveID) => {
    const user = await signInUser();
    await seedUnassignedPurchase({ user, productID: MODERATE_ACTION_CARD_PRODUCT_ID });
    const { status, body } = await callFunction({ name: "assignActionCardMove", user, data: { actionCardPurchaseID: "event-1", moveID } });
    expect(status).toBe(400);
    expect(body.error.status).toBe("FAILED_PRECONDITION");
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ moveID: null });
  });

  it("既に買い切った技は already-exists で、購入は技に結び付いていないまま残る", async () => {
    const user = await signInUser();
    await firestore.doc(`users/${user.uid}/actionCardPurchases/event-0`).set({ productId: CHEAP_ACTION_CARD_PRODUCT_ID, moveID: "weak", createdAt: new Date() });
    await seedUnassignedPurchase({ user, productID: CHEAP_ACTION_CARD_PRODUCT_ID });
    expect((await callFunction({ name: "assignActionCardMove", user, data: { actionCardPurchaseID: "event-1", moveID: "weak" } })).status).toBe(409);
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ moveID: null });
  });

  it("技を受け取り済みの購入は failed-precondition で、技を変えない", async () => {
    const user = await signInUser();
    await firestore.doc(`users/${user.uid}/actionCardPurchases/event-1`).set({ productId: EXPENSIVE_ACTION_CARD_PRODUCT_ID, moveID: "weak", createdAt: new Date() });
    expect((await callFunction({ name: "assignActionCardMove", user, data: { actionCardPurchaseID: "event-1", moveID: "strong" } })).status).toBe(400);
    expect(await purchaseOf({ uid: user.uid })).toMatchObject({ moveID: "weak" });
  });

  it("無い購入・他人の購入は not-found", async () => {
    const user = await signInUser();
    await firestore.doc("users/bob/actionCardPurchases/event-bob").set({ productId: EXPENSIVE_ACTION_CARD_PRODUCT_ID, moveID: null, createdAt: new Date() });
    expect((await callFunction({ name: "assignActionCardMove", user, data: { actionCardPurchaseID: "event-bob", moveID: "weak" } })).status).toBe(404);
    expect((await firestore.doc("users/bob/actionCardPurchases/event-bob").get()).get("moveID")).toBeNull();
  });

  it.each(["replaced", "unknown"])("置き換えられた技・master に無い技 (%s) は not-found", async (moveID) => {
    const user = await signInUser();
    await seedUnassignedPurchase({ user, productID: EXPENSIVE_ACTION_CARD_PRODUCT_ID });
    expect((await callFunction({ name: "assignActionCardMove", user, data: { actionCardPurchaseID: "event-1", moveID } })).status).toBe(404);
  });

  it("actionCardPurchaseID か moveID が無ければ invalid-argument", async () => {
    const user = await signInUser();
    expect((await callFunction({ name: "assignActionCardMove", user, data: { moveID: "weak" } })).status).toBe(400);
    expect((await callFunction({ name: "assignActionCardMove", user, data: { actionCardPurchaseID: "event-1" } })).status).toBe(400);
  });
});

describe("teachActionCardMove・forgetActionCardMove", () => {
  /** [user] に技 [moveId] を買い切った購入を置く。 */
  async function seedActionCard({ user, moveId }: { user: User; moveId: string }): Promise<void> {
    await firestore.doc(`users/${user.uid}/actionCardPurchases/event-${moveId}`).set({ productId: CHEAP_ACTION_CARD_PRODUCT_ID, moveID: moveId, createdAt: new Date() });
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
    expect((await firestore.doc(`users/${user.uid}/actionCardPurchases/event-weak`).get()).get("moveID")).toBe("weak");
    await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1", moveId: "weak" } });
    expect(await actionCardMoveIdsOf({ uid: user.uid, monsterId: "m1" })).toEqual(["strong", "weak"]);
  });

  it("monsterId か moveId が無ければ invalid-argument", async () => {
    const user = await signInUser();
    expect((await callFunction({ name: "teachActionCardMove", user, data: { monsterId: "m1" } })).status).toBe(400);
    expect((await callFunction({ name: "forgetActionCardMove", user, data: { moveId: "weak" } })).status).toBe(400);
  });
});

describe("updateActionCardProductsWith", () => {
  // 2026-11-09 04:00 (日本時間)
  const now = new Date("2026-11-08T19:00:00Z");

  it("前日から 7 日分の使用回数を合計して、買える技に商品を割り振って書く", async () => {
    // 当日 (11-09) と 8 日前 (11-01) の分は数えない
    await firestore.doc("moveUsageDailyCounts/2026-11-09").set({ counts: { strong: 1000 } });
    await firestore.doc("moveUsageDailyCounts/2026-11-01").set({ counts: { strong: 1000 } });
    await firestore.doc("moveUsageDailyCounts/2026-11-08").set({ counts: { weak: 3, middle: 1, replaced: 50 } });
    await firestore.doc("moveUsageDailyCounts/2026-11-02").set({ counts: { middle: 1 } });

    const written = await updateActionCardProductsWith({ firestore, now });
    const stored = (await firestore.doc("actionCardProducts/current").get()).data();
    expect(stored).toMatchObject({ version: 1, usageWindowDays: 7 });
    expect(stored?.computedAt.toDate()).toEqual(now);
    // 買える技は 4 件 (replaced は置き換えられたため表に入れない)。500 円は 4 件の 20% の切り捨てで 0 件、300 円は 50% の 2 件目まで。
    // 使用の順は weak (3)・middle (2) で、使われていない strong と replacer は段階で決める
    expect(stored?.productIDByMoveID).toEqual({ weak: MODERATE_ACTION_CARD_PRODUCT_ID, middle: MODERATE_ACTION_CARD_PRODUCT_ID, strong: EXPENSIVE_ACTION_CARD_PRODUCT_ID, replacer: CHEAP_ACTION_CARD_PRODUCT_ID });
    expect(written.productIDByMoveID).toEqual(stored?.productIDByMoveID);
  });

  it("集計が無ければすべて段階で決め、同じ入力で 2 回動かしても同じ表を書く", async () => {
    await updateActionCardProductsWith({ firestore, now });
    await updateActionCardProductsWith({ firestore, now });
    expect((await firestore.doc("actionCardProducts/current").get()).get("productIDByMoveID")).toEqual({ weak: CHEAP_ACTION_CARD_PRODUCT_ID, middle: MODERATE_ACTION_CARD_PRODUCT_ID, strong: EXPENSIVE_ACTION_CARD_PRODUCT_ID, replacer: CHEAP_ACTION_CARD_PRODUCT_ID });
  });

  it("最新の版の master の技に商品を割り振る", async () => {
    await firestore.doc("master/2").set({ version: 2, moves: [move({ id: "weak" }), move({ id: "newcomer", power: 120 })] });
    expect((await updateActionCardProductsWith({ firestore, now })).version).toBe(2);
    expect((await firestore.doc("actionCardProducts/current").get()).get("productIDByMoveID")).toEqual({ weak: CHEAP_ACTION_CARD_PRODUCT_ID, newcomer: EXPENSIVE_ACTION_CARD_PRODUCT_ID });
  });
});
