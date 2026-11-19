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

describe("RevenueCat の webhook の Web の購入 (store が RC_BILLING で、商品の ID の末尾が _web)", () => {
  it("生成チケットの Web の商品の購入で残高に 10 枚足し、アプリの商品の ID と Web のストアで記録して Slack に知らせる", async () => {
    const { dependencies, slackTexts } = createDependencies();
    expect(
      (await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ store: "RC_BILLING", product_id: "snapmon_generationticket10_200yen_web" }) })).body,
    ).toBe("added");
    expect(await generationTickets("alice")).toBe(10);
    expect((await firestore.doc("users/alice/ticketPurchases/event-1").get()).data()).toMatchObject({
      productID: "snapmon_generationticket10_200yen",
      ticketCount: 10,
      transactionID: "transaction-1",
      environment: "PRODUCTION",
      store: "RC_BILLING",
    });
    // 通知には届いた商品の ID をそのまま出す (Web の購入だと読めるように)
    expect(slackTexts).toEqual([expect.stringContaining("商品 snapmon_generationticket10_200yen_web・")]);
  });

  it("30 枚の Web の商品は 30 枚足し、アプリで買った残高に加える", async () => {
    const { dependencies } = createDependencies();
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() });
    await handleRevenueCatWebhook(dependencies, {
      authorization: AUTHORIZATION,
      body: webhookBody({ id: "event-2", store: "RC_BILLING", product_id: "snapmon_generationticket30_500yen_web" }),
    });
    expect(await generationTickets("alice")).toBe(40);
  });

  it("Web の購入の同じイベントの ID を 2 回受けても 1 回しか足さない", async () => {
    const { dependencies, slackTexts } = createDependencies();
    const body = webhookBody({ store: "RC_BILLING", product_id: "snapmon_generationticket10_200yen_web" });
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body });
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body })).body).toBe("duplicate");
    expect(await generationTickets("alice")).toBe(10);
    expect((await firestore.collection("users/alice/ticketPurchases").get()).size).toBe(1);
    expect(slackTexts).toHaveLength(1);
  });

  it.each(["snapmon_actioncardrank1_100yen", "snapmon_actioncardrank2_300yen", "snapmon_actioncardrank3_500yen"])(
    "Action Card の Web の商品 %s_web の購入を、アプリの商品の ID と Web のストアで記録し、Slack に知らせる",
    async (productID) => {
      const { dependencies, slackTexts } = createDependencies();
      expect(
        (await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ store: "RC_BILLING", product_id: `${productID}_web` }) })).body,
      ).toBe("added");
      expect((await firestore.doc("users/alice/actionCardPurchases/event-1").get()).data()).toMatchObject({
        productID,
        moveID: null,
        actionCardMoveReservationID: null,
        moveAssignedAt: null,
        transactionID: "transaction-1",
        environment: "PRODUCTION",
        store: "RC_BILLING",
      });
      expect((await firestore.doc("users/alice/ticketPurchases/event-1").get()).exists).toBe(false);
      expect(await generationTickets("alice")).toBeUndefined();
      expect(slackTexts).toHaveLength(1);
    },
  );

  it("Action Card の Web の購入の同じイベントの ID を 2 回受けても購入を 1 件しか記録しない", async () => {
    const { dependencies, slackTexts } = createDependencies();
    const body = webhookBody({ store: "RC_BILLING", product_id: "snapmon_actioncardrank1_100yen_web" });
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body });
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body })).body).toBe("duplicate");
    expect((await firestore.collection("users/alice/actionCardPurchases").get()).size).toBe(1);
    expect(slackTexts).toHaveLength(1);
  });

  it("Web の商品をアプリと同じ ID で作った時 (末尾に _web が無い) も、store が RC_BILLING の購入を足す", async () => {
    const { dependencies } = createDependencies();
    await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ store: "RC_BILLING" }) });
    expect(await generationTickets("alice")).toBe(10);
    expect((await firestore.doc("users/alice/ticketPurchases/event-1").get()).data()).toMatchObject({ productID: "snapmon_generationticket10_200yen", store: "RC_BILLING" });
  });

  it.each([
    { label: "生成チケット", productID: "snapmon_generationticket10_200yen" },
    { label: "Action Card", productID: "snapmon_actioncardrank2_300yen" },
  ])("$label の Web の購入の返金・取り消しは、アプリの購入と同じく残高と購入を変えずに同じ文で Slack に知らせる", async ({ label, productID }) => {
    await firestore.doc("users/alice").set({ generationTickets: 10 });
    await firestore.doc("users/alice/actionCardPurchases/event-0").set({ productID: "snapmon_actioncardrank2_300yen", moveID: "fire_1c" });
    const { dependencies, slackTexts } = createDependencies();
    const appResponse = await handleRevenueCatWebhook(dependencies, {
      authorization: AUTHORIZATION,
      body: webhookBody({ type: "CANCELLATION", id: "event-3", product_id: productID }),
    });
    const webResponse = await handleRevenueCatWebhook(dependencies, {
      authorization: AUTHORIZATION,
      body: webhookBody({ type: "CANCELLATION", id: "event-4", store: "RC_BILLING", product_id: `${productID}_web` }),
    });
    expect(webResponse).toEqual(appResponse);
    expect(webResponse).toEqual({ status: 200, body: "ignored" });
    expect(await generationTickets("alice")).toBe(10);
    expect((await firestore.doc("users/alice/actionCardPurchases/event-0").get()).data()).toEqual({ productID: "snapmon_actioncardrank2_300yen", moveID: "fire_1c" });
    expect((await firestore.collection("users/alice/ticketPurchases").get()).size).toBe(0);
    expect((await firestore.collection("users/alice/actionCardPurchases").get()).size).toBe(1);
    // 通知の文は、届いた商品の ID とイベントの ID のほかはアプリの購入と同じ
    expect(slackTexts).toEqual([
      `${label}の返金・取り消しを受けました。残高は減らしていません (イベント event-3・ユーザー alice・商品 ${productID}・環境 PRODUCTION)`,
      `${label}の返金・取り消しを受けました。残高は減らしていません (イベント event-4・ユーザー alice・商品 ${productID}_web・環境 PRODUCTION)`,
    ]);
  });

  it.each([
    // 末尾の _web を外した ID がアプリの商品でないもの
    "snapmon_generationticket100_1500yen_web",
    // _web を 2 つ外さない
    "snapmon_generationticket10_200yen_web_web",
    // _web で終わらない (似ているが別の末尾)
    "snapmon_generationticket10_200yen_website",
    "snapmon_generationticket10_200yenweb",
    "snapmon_generationticket10_200yen_WEB",
    "snapmon_generationticket10_200yen_web_",
    "snapmon_actioncardrank1_100yen_web2",
    // 末尾だけ
    "_web",
  ])("アプリの商品に当たらない Web の商品の ID %s は知らない商品として足さずに Slack に知らせる", async (productID) => {
    const { dependencies, slackTexts } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ store: "RC_BILLING", product_id: productID }) })).body).toBe(
      "unknown product",
    );
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
    expect(slackTexts).toHaveLength(1);
  });

  it("アプリの商品に当たらない Web の商品の返金・取り消しは、アプリの知らない商品と同じく Slack に知らせない", async () => {
    const { dependencies, slackTexts } = createDependencies();
    await handleRevenueCatWebhook(dependencies, {
      authorization: AUTHORIZATION,
      body: webhookBody({ type: "CANCELLATION", store: "RC_BILLING", product_id: "snapmon_generationticket100_1500yen_web" }),
    });
    expect(slackTexts).toHaveLength(0);
  });
});

describe("RevenueCat の webhook の試験の購入 (environment が SANDBOX)", () => {
  it.each([
    { label: "生成チケット", productID: "snapmon_generationticket10_200yen_web" },
    { label: "生成チケット", productID: "snapmon_generationticket10_200yen" },
    { label: "Action Card", productID: "snapmon_actioncardrank2_300yen_web" },
  ])("Web の販売 (store が RC_BILLING) の試験の購入 $productID は、残高にも購入の記録にも書かず Slack に知らせる", async ({ label, productID }) => {
    const user = { generationTickets: 5, actionCardMoveReservation: { moveID: "fire_1c", productID: "snapmon_actioncardrank2_300yen", actionCardMoveReservationID: "reservation-1" } };
    await firestore.doc("users/alice").set(user);
    const { dependencies, slackTexts } = createDependencies();
    expect(
      await handleRevenueCatWebhook(dependencies, {
        authorization: AUTHORIZATION,
        body: webhookBody({ store: "RC_BILLING", environment: "SANDBOX", product_id: productID }),
      }),
    ).toEqual({ status: 200, body: "web sandbox purchase" });
    // 残高も、買う前に控えた技も変えない
    expect((await firestore.doc("users/alice").get()).data()).toEqual(user);
    expect((await firestore.collection("users/alice/ticketPurchases").get()).size).toBe(0);
    expect((await firestore.collection("users/alice/actionCardPurchases").get()).size).toBe(0);
    expect(slackTexts).toEqual([
      `Web の販売の試験の購入 (sandbox) で${label}が買われました。残高に足していません (イベント event-1・ユーザー alice・商品 ${productID}・環境 SANDBOX)`,
    ]);
  });

  it("Web の販売の試験の購入は、まだ users/{uid} が無いユーザーの文書を作らない", async () => {
    const { dependencies } = createDependencies();
    await handleRevenueCatWebhook(dependencies, {
      authorization: AUTHORIZATION,
      body: webhookBody({ store: "RC_BILLING", environment: "SANDBOX", product_id: "snapmon_generationticket10_200yen_web" }),
    });
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
  });

  it.each([
    // アプリのストアの試験の購入 (審査とテスターの購入) は今までどおり足す
    { store: "APP_STORE", environment: "SANDBOX" },
    { store: "PLAY_STORE", environment: "SANDBOX" },
    // ストアの値が届かない試験の購入も今までどおり足す
    { store: undefined, environment: "SANDBOX" },
    // Web の販売でも、代金を払った購入は足す
    { store: "RC_BILLING", environment: "PRODUCTION" },
    // 環境の値が届かない Web の販売の購入は、試験の購入として扱わない
    { store: "RC_BILLING", environment: undefined },
  ])("store が $store・environment が $environment の購入は残高に足す", async ({ store, environment }) => {
    const { dependencies } = createDependencies();
    expect((await handleRevenueCatWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ store, environment }) })).body).toBe("added");
    expect(await generationTickets("alice")).toBe(10);
    expect((await firestore.doc("users/alice/ticketPurchases/event-1").get()).data()).toMatchObject({ store: store ?? null, environment: environment ?? null });
  });

  it("Web の販売の試験の購入の返金・取り消しは、ほかの返金・取り消しと同じく残高を変えずに Slack に知らせる", async () => {
    await firestore.doc("users/alice").set({ generationTickets: 10 });
    const { dependencies, slackTexts } = createDependencies();
    expect(
      await handleRevenueCatWebhook(dependencies, {
        authorization: AUTHORIZATION,
        body: webhookBody({ type: "CANCELLATION", store: "RC_BILLING", environment: "SANDBOX", product_id: "snapmon_generationticket10_200yen_web" }),
      }),
    ).toEqual({ status: 200, body: "ignored" });
    expect(await generationTickets("alice")).toBe(10);
    expect(slackTexts).toEqual([
      "生成チケットの返金・取り消しを受けました。残高は減らしていません (イベント event-1・ユーザー alice・商品 snapmon_generationticket10_200yen_web・環境 SANDBOX)",
    ]);
  });

  it("Web の販売の試験の購入でも、アプリの商品に当たらない商品は知らない商品として Slack に知らせる", async () => {
    const { dependencies, slackTexts } = createDependencies();
    expect(
      (
        await handleRevenueCatWebhook(dependencies, {
          authorization: AUTHORIZATION,
          body: webhookBody({ store: "RC_BILLING", environment: "SANDBOX", product_id: "snapmon_generationticket100_1500yen_web" }),
        })
      ).body,
    ).toBe("unknown product");
    expect(slackTexts).toEqual([
      "知らない商品の購入を受けました。残高に足していません (イベント event-1・ユーザー alice・商品 snapmon_generationticket100_1500yen_web・環境 SANDBOX)",
    ]);
  });
});
