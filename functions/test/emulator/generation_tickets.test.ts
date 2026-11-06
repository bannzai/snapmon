import { deleteApp, getApps, initializeApp } from "firebase-admin/app";
import type { Auth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

import { handleGenerationTicketWebhook, type GenerationTicketWebhookDependencies } from "../../src/generation_tickets";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。

const projectId = "demo-snapmon";
const app = getApps().find((existing) => existing.name === "generation-tickets-test") ?? initializeApp({ projectId }, "generation-tickets-test");
const firestore = getFirestore(app);

/** テストで RevenueCat に設定したことにする `Authorization` の値。 */
const AUTHORIZATION = "Bearer test-webhook-authorization";

afterAll(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
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
function createDependencies(): { dependencies: GenerationTicketWebhookDependencies; slackTexts: string[] } {
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
    const response = await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() });
    expect(response.status).toBe(200);
    expect(await generationTickets("alice")).toBe(10);
    expect((await firestore.doc("users/alice/ticketPurchases/event-1").get()).data()).toMatchObject({
      productId: "snapmon_generationticket10_200yen",
      ticketCount: 10,
      transactionId: "transaction-1",
      environment: "PRODUCTION",
      store: "APP_STORE",
    });
    expect(slackTexts).toHaveLength(1);
  });

  it("30 枚の商品は 30 枚足し、既にある残高に加える", async () => {
    await firestore.doc("users/alice").set({ generationTickets: 3 });
    const { dependencies } = createDependencies();
    await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ product_id: "snapmon_generationticket30_500yen" }) });
    expect(await generationTickets("alice")).toBe(33);
  });

  it("同じイベントの ID を 2 回受けても 1 回しか足さない", async () => {
    const { dependencies, slackTexts } = createDependencies();
    await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() });
    const second = await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() });
    expect(second.status).toBe(200);
    expect(await generationTickets("alice")).toBe(10);
    expect(slackTexts).toHaveLength(1);
  });

  it("別のイベントの ID なら同じ商品でも足す", async () => {
    const { dependencies } = createDependencies();
    await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() });
    await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: "event-2" }) });
    expect(await generationTickets("alice")).toBe(20);
  });

  it("Authorization が違う・無い時は 401 で何も書かない", async () => {
    const { dependencies } = createDependencies();
    expect((await handleGenerationTicketWebhook(dependencies, { authorization: "Bearer wrong-webhook-authorization", body: webhookBody() })).status).toBe(401);
    expect((await handleGenerationTicketWebhook(dependencies, { authorization: `${AUTHORIZATION} `, body: webhookBody() })).status).toBe(401);
    expect((await handleGenerationTicketWebhook(dependencies, { authorization: undefined, body: webhookBody() })).status).toBe(401);
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
  });

  it("Secret が空の時は、空の Authorization でも通さない", async () => {
    const { dependencies } = createDependencies();
    expect((await handleGenerationTicketWebhook({ ...dependencies, expectedAuthorization: "" }, { authorization: "", body: webhookBody() })).status).toBe(401);
  });

  it("消耗型の購入以外のイベント (サブスクリプションの購入) は足さない", async () => {
    const { dependencies } = createDependencies();
    const response = await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ type: "INITIAL_PURCHASE" }) });
    expect(response.status).toBe(200);
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
  });

  it("返金・取り消しは残高を減らさず Slack に知らせる", async () => {
    await firestore.doc("users/alice").set({ generationTickets: 10 });
    const { dependencies, slackTexts } = createDependencies();
    const response = await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ type: "CANCELLATION", id: "event-3" }) });
    expect(response.status).toBe(200);
    expect(await generationTickets("alice")).toBe(10);
    expect(slackTexts).toHaveLength(1);
  });

  it("知らない商品の消耗型の購入は足さずに Slack に知らせる", async () => {
    const { dependencies, slackTexts } = createDependencies();
    const response = await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ product_id: "snapmon_generationticket100_1500yen" }) });
    expect(response.status).toBe(200);
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
    expect(slackTexts).toHaveLength(1);
  });

  it("logIn していない購入 (RevenueCat の匿名の ID) と / を含む ID は足さない", async () => {
    const { dependencies, slackTexts } = createDependencies();
    await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ app_user_id: "$RCAnonymousID:abc123" }) });
    await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: "event-2", app_user_id: "alice/ticketPurchases" }) });
    expect((await firestore.doc("users/alice").get()).exists).toBe(false);
    expect(slackTexts).toHaveLength(2);
  });

  it("生成する前に買った (users/{uid} の無い) ユーザーにも足す", async () => {
    const { dependencies } = createDependencies();
    await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ app_user_id: "bob" }) });
    expect(await generationTickets("bob")).toBe(10);
  });

  it("アカウントの削除が始まったユーザーと消し終えたユーザーには足さず、users/{uid} を作り直さない", async () => {
    await firestore.doc("users/alice").set({ accountDeletionStartedAt: new Date() });
    const { dependencies } = createDependencies();
    await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody() });
    await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: "event-2", app_user_id: "deleted" }) });
    expect(await generationTickets("alice")).toBeUndefined();
    expect((await firestore.doc("users/alice/ticketPurchases/event-1").get()).exists).toBe(false);
    expect((await firestore.doc("users/deleted").get()).exists).toBe(false);
  });

  it("event.id の無い本文は 400 を返す", async () => {
    const { dependencies } = createDependencies();
    expect((await handleGenerationTicketWebhook(dependencies, { authorization: AUTHORIZATION, body: webhookBody({ id: undefined }) })).status).toBe(400);
  });
});
