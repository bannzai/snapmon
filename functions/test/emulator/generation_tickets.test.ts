import { deleteApp, getApps, initializeApp } from "firebase-admin/app";
import type { Auth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

import { handleRevenueCatWebhook, type RevenueCatWebhookDependencies } from "../../src/generation_tickets";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。

const projectID = "demo-snapmon";
const app = getApps().find((existing) => existing.name === "generation-tickets-test") ?? initializeApp({ projectId: projectID }, "generation-tickets-test");
const firestore = getFirestore(app);

/** テストで RevenueCat に設定したことにする `Authorization` の値。 */
const AUTHORIZATION = "Bearer test-webhook-authorization";

afterAll(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${projectID}/databases/(default)/documents`, { method: "DELETE" });
});

/** Auth のユーザーが残っている uid。 */
const authUserUids = new Set(["alice", "bob"]);

/** [authUserUids] の uid だけを残っているユーザーとして返す Auth のモック。 */
const auth = {
  getUser: async (uid: string) => {
    if (!authUserUids.has(uid)) {
      throw Object.assign(new Error("ユーザーが見つかりません"), { code: "auth/user-not-found" });
    }
    return { uid };
  },
} as unknown as Auth;

/** 本番の依存をモックに替えたものと、Slack に送った文。 */
function createDependencies(): { dependencies: RevenueCatWebhookDependencies; slackTexts: string[] } {
  const slackTexts: string[] = [];
  return {
    slackTexts,
    dependencies: {
      firestore,
      auth,
      sendMessage: async ({ text }) => {
        slackTexts.push(text);
      },
      expectedAuthorization: AUTHORIZATION,
      now: () => new Date("2026-11-07T00:00:00Z"),
    },
  };
}

/** RevenueCat の webhook の本文。既定は alice の 10 枚の消耗型の購入。 */
function webhookBody(event: Record<string, unknown> = {}) {
  return {
    api_version: "1.0",
    event: {
      id: "event-1",
      type: "NON_RENEWING_PURCHASE",
      app_user_id: "alice",
      product_id: "snapmon_generationticket10_200yen",
      environment: "PRODUCTION",
      transaction_id: "transaction-1",
      store: "APP_STORE",
      ...event,
    },
  };
}

/** [uid] の生成チケットの残高 (`users/{uid}.generationTickets`)。文書かフィールドが無ければ undefined。 */
async function generationTickets(uid: string): Promise<unknown> {
  return (await firestore.doc(`users/${uid}`).get()).get("generationTickets");
}

describe("RevenueCat の webhook", () => {
  it("消耗型の購入で残高に 10 枚足し、購入の記録を残して Slack に知らせる", async () => {
    const { dependencies, slackTexts } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() })).status).toBe(200);
    expect(await generationTickets("alice")).toBe(10);
    expect((await firestore.doc("users/alice/ticketPurchases/event-1").get()).data()).toMatchObject({
      productID: "snapmon_generationticket10_200yen",
      ticketCount: 10,
      transactionID: "transaction-1",
      environment: "PRODUCTION",
      store: "APP_STORE",
    });
    expect(slackTexts).toHaveLength(1);
  });

  it("30 枚の商品は 30 枚足し、既にある残高に加える", async () => {
    await firestore.doc("users/alice").set({ generationTickets: 3 });
    const { dependencies } = createDependencies();
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ product_id: "snapmon_generationticket30_500yen" }) });
    expect(await generationTickets("alice")).toBe(33);
  });

  it("同じイベントの ID を 2 回受けても 1 回しか足さない", async () => {
    const { dependencies, slackTexts } = createDependencies();
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() });
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() })).status).toBe(200);
    expect(await generationTickets("alice")).toBe(10);
    expect(slackTexts).toHaveLength(1);
  });

  it("別のイベントの ID なら同じ商品でも足す", async () => {
    const { dependencies } = createDependencies();
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() });
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: "event-2" }) });
    expect(await generationTickets("alice")).toBe(20);
  });

  it("Authorization が違う・無い時は 401 で何も書かない", async () => {
    const { dependencies } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: "Bearer wrong-webhook-authorization", body: webhookBody() })).status).toBe(401);
    expect((await handleRevenueCatWebhook(dependencies, { authorization: `${AUTHORIZATION} `, body: webhookBody() })).status).toBe(401);
    expect((await handleRevenueCatWebhook(dependencies, { authorization: undefined, body: webhookBody() })).status).toBe(401);
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
  });

  it("Secret が空の時は、空の Authorization でも通さない", async () => {
    const { dependencies } = createDependencies();
    expect((await handleRevenueCatWebhook({ ...dependencies, expectedAuthorization: "" }, { authorization: "", body: webhookBody() })).status).toBe(401);
  });

  it("消耗型の購入以外のイベント (サブスクリプションの購入) は足さない", async () => {
    const { dependencies } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ type: "INITIAL_PURCHASE" }) })).status).toBe(200);
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
  });

  it("返金・取り消しは残高を減らさず Slack に知らせる", async () => {
    await firestore.doc("users/alice").set({ generationTickets: 10 });
    const { dependencies, slackTexts } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ type: "CANCELLATION", id: "event-3" }) })).status).toBe(200);
    expect(await generationTickets("alice")).toBe(10);
    expect(slackTexts).toHaveLength(1);
  });

  it("知らない商品の消耗型の購入は足さずに Slack に知らせる", async () => {
    const { dependencies, slackTexts } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ product_id: "snapmon_generationticket100_1500yen" }) })).status).toBe(200);
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
    expect(slackTexts).toHaveLength(1);
  });

  it("logIn していない購入 (RevenueCat の匿名の ID) と / を含む ID は足さない", async () => {
    const { dependencies, slackTexts } = createDependencies();
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ app_user_id: "$RCAnonymousID:abc123" }) });
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: "event-2", app_user_id: "alice/ticketPurchases" }) });
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
    expect(slackTexts).toHaveLength(2);
  });

  it("生成する前に買った (users/{uid} の無い) ユーザーにも足す", async () => {
    const { dependencies } = createDependencies();
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ app_user_id: "bob" }) });
    expect(await generationTickets("bob")).toBe(10);
  });

  it("アカウントの削除が始まったユーザーと消し終えたユーザーには足さず、users/{uid} を作り直さない", async () => {
    await firestore.doc("users/alice").set({ accountDeletionStartedAt: new Date() });
    const { dependencies } = createDependencies();
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() });
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: "event-2", app_user_id: "deleted" }) });
    expect(await generationTickets("alice")).toBeUndefined();
    expect((await firestore.doc("users/alice/ticketPurchases/event-1").get()).exists).toBe(false);
    expect((await firestore.doc("users/deleted").get()).exists).toBe(false);
  });

  it("event.id の無い本文は 400 を返す", async () => {
    const { dependencies } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: undefined }) })).status).toBe(400);
  });

  it("文書 ID に使えない event.id (/ を含む・..) は 400 を返して何も書かない", async () => {
    const { dependencies } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: "event/1" }) })).status).toBe(400);
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: ".." }) })).status).toBe(400);
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
  });

  it("UUID の形の event.id は受け付ける", async () => {
    const { dependencies } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: "CDD0A5C7-26F5-4D57-A4B2-1F2E5B0A9C11" }) })).status).toBe(200);
    expect(await generationTickets("alice")).toBe(10);
  });

  it("継承したキーの商品 (constructor) は知らない商品として足さずに Slack に知らせる", async () => {
    const { dependencies, slackTexts } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ product_id: "constructor" }) })).status).toBe(200);
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
    expect(slackTexts).toHaveLength(1);
  });
});

describe("RevenueCat の webhook の Action Card (技の控えが無い購入)", () => {
  // 控えた技を結び付ける購入は action_cards.test.ts で確かめる
  it.each(["snapmon_actioncardrank1_100yen", "snapmon_actioncardrank2_300yen", "snapmon_actioncardrank3_500yen"])(
    "%s の購入は技に結び付けずに届いた商品の ID のまま記録し、Slack に知らせる",
    async (productID) => {
      const { dependencies, slackTexts } = createDependencies();
      expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ product_id: productID }) })).status).toBe(200);
      const purchase = (await firestore.doc("users/alice/actionCardPurchases/event-1").get()).data();
      // 商品の ID のほかに、値段の段を表す値を持たない (#293)
      expect(purchase).not.toHaveProperty("rank");
      expect(purchase).toMatchObject({
        productID,
        moveID: null,
        actionCardMoveReservationID: null,
        moveAssignedAt: null,
        transactionID: "transaction-1",
        environment: "PRODUCTION",
        store: "APP_STORE",
      });
      // 選び直しの callable (assignActionCardMove) は users/{uid} を求めるため、生成する前のユーザーにも作る
      expect((await firestore.doc("users/alice").get()).exists).toBe(true);
      expect((await firestore.doc("users/alice").get()).get("actionCardCredits")).toBeUndefined();
      expect((await firestore.doc("users/alice/ticketPurchases/event-1").get()).exists).toBe(false);
      expect(await generationTickets("alice")).toBeUndefined();
      expect(slackTexts).toHaveLength(1);
    },
  );

  it("同じイベントの ID を 2 回受けても購入を 1 件しか記録せず、他のフィールドを保つ", async () => {
    await firestore.doc("users/alice").set({ generationTickets: 5 });
    const { dependencies, slackTexts } = createDependencies();
    const body = webhookBody({ product_id: "snapmon_actioncardrank1_100yen" });
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body });
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body })).body).toBe("duplicate");
    expect((await firestore.collection("users/alice/actionCardPurchases").get()).size).toBe(1);
    expect(await generationTickets("alice")).toBe(5);
    expect(slackTexts).toHaveLength(1);
  });

  it.each([
    // 価格の部分だけが違う商品はストアに無い (Google Play で 100 円を設定できたため 150 円の商品は作っていない。DIRECTION.md の #272 の行)
    "snapmon_actioncardrank1_150yen",
    "snapmon_actioncardrank4_100yen",
    "snapmon_actioncardrank1",
    "snapmon_actioncardrank10_100yen",
    "snapmon_actioncardrank0_100yen",
  ])(
    "Action Card の 3 つの商品のどれでもない %s は知らない商品として記録せずに Slack に知らせる",
    async (productID) => {
      const { dependencies, slackTexts } = createDependencies();
      expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ product_id: productID }) })).body).toBe("unknown product");
      expect((await firestore.doc("users/alice").get()).exists).toBe(false);
      expect(slackTexts).toHaveLength(1);
    },
  );

  it("返金・取り消しは購入と買い切った技を変えず Slack に知らせる", async () => {
    await firestore.doc("users/alice/actionCardPurchases/event-0").set({ productID: "snapmon_actioncardrank2_300yen", moveID: "fire_1c" });
    const { dependencies, slackTexts } = createDependencies();
    await handleRevenueCatWebhook(dependencies, {
      authorization: AUTHORIZATION,
      body: webhookBody({ type: "CANCELLATION", product_id: "snapmon_actioncardrank2_300yen" }),
    });
    expect((await firestore.doc("users/alice/actionCardPurchases/event-0").get()).data()).toEqual({ productID: "snapmon_actioncardrank2_300yen", moveID: "fire_1c" });
    expect((await firestore.doc("users/alice/actionCardPurchases/event-1").get()).exists).toBe(false);
    expect(slackTexts).toHaveLength(1);
  });

  it("アカウントの削除が始まったユーザーには記録しない", async () => {
    await firestore.doc("users/alice").set({ accountDeletionStartedAt: new Date() });
    const { dependencies } = createDependencies();
    expect(
      (await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ product_id: "snapmon_actioncardrank3_500yen" }) })).body,
    ).toBe("account missing");
    expect((await firestore.doc("users/alice/actionCardPurchases/event-1").get()).exists).toBe(false);
  });
});
