// 生成チケット (1 日の無料の回数を使い切った後に生成できる消耗型の商品) の購入を、RevenueCat の webhook で残高に足す。
// 残高は `users/{uid}.generationTickets` に置き、生成の予約 (generation/pipeline.ts の startGeneration) が 1 枚ずつ減らす。
// 受け取る形は https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields (2026-11-07 に確認): 本文は
// `{ api_version, event }` で、消耗型を含む自動更新しない購入は `event.type` が `NON_RENEWING_PURCHASE`、返金と取り消しは `CANCELLATION`。

import { timingSafeEqual } from "node:crypto";

import { type Auth, getAuth } from "firebase-admin/auth";
import { FieldValue, type Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/v2/https";

import { authUserExists } from "./account";
import { revenueCatWebhookAuthorization, slackBotToken } from "./secrets";
import { PRODUCTION_NOTIFICATION_CHANNEL, postSlackMessage, type SendSlackMessage } from "./slack";

/**
 * 商品の識別子と、1 回の購入で足すチケットの枚数。識別子は App Store・Google Play・RevenueCat で同じ
 * (~/.claude/documents/rules/iap-product-identifier-naming.md)。価格はストアが正で、ここには持たない (issue #182 の制約)。
 */
export const GENERATION_TICKET_COUNT_BY_PRODUCT_ID: Readonly<Record<string, number>> = {
  snapmon_generationticket10_200yen: 10,
  snapmon_generationticket30_500yen: 30,
};

/**
 * RevenueCat の `app_user_id` のうち、Firebase の uid として受け付ける形。アプリは `Purchases.logIn(uid)` で uid を渡す。
 * `logIn` していない購入の匿名の ID (`$RCAnonymousID:...`) と、Firestore のパスを壊す文字 (`/`) を含む値はこの形に合わない。
 * 長さの上限 128 は Firebase Authentication の uid の上限 (Admin SDK の `createUser` は 128 文字を超える uid を拒否する)。
 * 文字種は、このアプリが使う匿名ログインと Firebase が自動で振る uid (英数字) が収まる範囲にした。
 */
const FIREBASE_UID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/**
 * RevenueCat のイベントの ID のうち、`ticketPurchases` の文書 ID としてそのまま使う形。RevenueCat の ID は UUID (英数字と `-`) で、
 * Firestore の文書 ID を壊す値 (`/` を含む・`.`・`..`・1,500 バイトを超える) はこの形に合わない。上限の 128 は UUID (36 文字) に余裕を持たせた値。
 */
const REVENUECAT_EVENT_ID_PATTERN = /^[A-Za-z0-9_-]{1,128}$/;

/** [productId] が生成チケットの商品なら 1 回の購入で足す枚数、それ以外は undefined。継承したキー (`constructor` 等) を商品として扱わない。 */
function generationTicketCount(productId: string | null): number | undefined {
  return productId !== null && Object.hasOwn(GENERATION_TICKET_COUNT_BY_PRODUCT_ID, productId) ? GENERATION_TICKET_COUNT_BY_PRODUCT_ID[productId] : undefined;
}

/** RevenueCat の webhook の本文の `event` のうち、このファイルが読むフィールド。 */
export interface RevenueCatWebhookEvent {
  /** イベントの一意な ID。同じイベントの再送で同じ値が届く。 */
  id?: unknown;
  /** イベントの種類 (`NON_RENEWING_PURCHASE`・`CANCELLATION` 等)。 */
  type?: unknown;
  /** 購入したユーザーの ID (アプリが logIn した Firebase の uid)。 */
  app_user_id?: unknown;
  /** 商品の識別子。 */
  product_id?: unknown;
  /** `SANDBOX` か `PRODUCTION`。 */
  environment?: unknown;
  /** ストアの取引の ID。 */
  transaction_id?: unknown;
  /** 購入したストア (`APP_STORE`・`PLAY_STORE` 等)。 */
  store?: unknown;
}

/** 生成チケットの購入の記録 (`users/{uid}/ticketPurchases/{eventId}`)。同じイベントを 2 回足さない判定と購入の履歴に使う。 */
export interface TicketPurchaseDocument {
  /** 商品の識別子。 */
  productId: string;
  /** 足した枚数。 */
  ticketCount: number;
  /** ストアの取引の ID (RevenueCat が送らなかった時は null)。 */
  transactionId: string | null;
  /** `SANDBOX` か `PRODUCTION` (RevenueCat が送らなかった時は null)。 */
  environment: string | null;
  /** 購入したストア (RevenueCat が送らなかった時は null)。 */
  store: string | null;
  /** 記録した時刻。 */
  createdAt: Timestamp;
}

/** webhook の処理に使う外部の資源。本番は onRequest が、テストはモックを渡す。 */
export interface GenerationTicketWebhookDependencies {
  /** Firestore。 */
  firestore: Firestore;
  /** Firebase Authentication (アカウントを消し終えた uid の見分けに使う)。 */
  auth: Auth;
  /** Slack に知らせる。 */
  sendMessage: SendSlackMessage;
  /** RevenueCat に設定した `Authorization` ヘッダーの値。 */
  expectedAuthorization: string;
  /** 現在時刻。 */
  now: () => Date;
}

/** webhook の応答。`status` は HTTP の状態コード。 */
export interface GenerationTicketWebhookResponse {
  /** HTTP の状態コード。 */
  status: number;
  /** 応答の本文 (RevenueCat のダッシュボードの配信の記録に出る)。 */
  body: string;
}

/** [authorization] が [expectedAuthorization] と一致するか。比べる時間で値を推測させないよう、長さが同じ時は timingSafeEqual で比べる。 */
function isAuthorized({ authorization, expectedAuthorization }: { authorization: string | undefined; expectedAuthorization: string }): boolean {
  if (authorization === undefined || expectedAuthorization === "") {
    return false;
  }
  const actual = Buffer.from(authorization);
  const expected = Buffer.from(expectedAuthorization);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

/** [value] が空でない文字列ならそのまま、それ以外は null。 */
function optionalString(value: unknown): string | null {
  return typeof value === "string" && value !== "" ? value : null;
}

/** Slack に送る。失敗はログに残して投げない (残高は Firestore に書き終えており、RevenueCat に再送させないため)。 */
async function notify(sendMessage: SendSlackMessage, text: string): Promise<void> {
  try {
    await sendMessage({ channel: PRODUCTION_NOTIFICATION_CHANNEL, text });
  } catch (error) {
    logger.error("生成チケットの通知を Slack に送れませんでした", { error, text });
  }
}

/**
 * RevenueCat の webhook を受け、生成チケットの購入なら `users/{uid}.generationTickets` に足す (onRequest の本体)。
 *
 * - `Authorization` が RevenueCat に設定した値と一致しない時は 401 で、何も書かない
 * - `NON_RENEWING_PURCHASE` で、商品が生成チケットで、`app_user_id` が uid の形で、アカウントが残っている時だけ足す。同じイベントの ID の
 *   2 回目は足さない (`users/{uid}/ticketPurchases/{eventId}` を足す時と同じトランザクションで作る)
 * - 返金・取り消し (`CANCELLATION`) は残高を減らさず Slack に知らせる (残高が負になる扱いを作らないため。DIRECTION.md「決めたこと」2026-11-07 の行)
 * - 足せない購入 (知らない商品・uid の形でない・アカウントが無い) は Slack に知らせて 200 を返す (再送しても足せないため)
 * - それ以外のイベントは何もせず 200 を返す
 *
 * Firestore の書き込みが失敗した時は投げる (onRequest が 500 を返し、RevenueCat が再送する)。
 */
export async function handleGenerationTicketWebhook(
  dependencies: GenerationTicketWebhookDependencies,
  { authorization, body }: { authorization: string | undefined; body: unknown },
): Promise<GenerationTicketWebhookResponse> {
  if (!isAuthorized({ authorization, expectedAuthorization: dependencies.expectedAuthorization })) {
    return { status: 401, body: "unauthorized" };
  }
  const event = ((body ?? {}) as { event?: RevenueCatWebhookEvent }).event;
  if (!event || typeof event.id !== "string" || !REVENUECAT_EVENT_ID_PATTERN.test(event.id) || typeof event.type !== "string") {
    return { status: 400, body: "event.id と event.type がないか、event.id の形が違います" };
  }
  const appUserId = event.app_user_id;
  const productId = optionalString(event.product_id);
  const environment = optionalString(event.environment);
  const summary = `イベント ${event.id}・ユーザー ${String(appUserId)}・商品 ${productId ?? "(なし)"}・環境 ${environment ?? "(なし)"}`;

  if (event.type === "CANCELLATION") {
    if (generationTicketCount(productId) !== undefined) {
      await notify(dependencies.sendMessage, `生成チケットの返金・取り消しを受けました。残高は減らしていません (${summary})`);
    }
    return { status: 200, body: "ignored" };
  }
  if (event.type !== "NON_RENEWING_PURCHASE") {
    return { status: 200, body: "ignored" };
  }
  const ticketCount = generationTicketCount(productId);
  if (ticketCount === undefined) {
    // 生成チケット以外の消耗型の商品はまだ無いため、届いたら設定の誤りとして知らせる
    await notify(dependencies.sendMessage, `生成チケットとして知らない商品の購入を受けました。残高に足していません (${summary})`);
    return { status: 200, body: "unknown product" };
  }
  if (typeof appUserId !== "string" || !FIREBASE_UID_PATTERN.test(appUserId)) {
    await notify(dependencies.sendMessage, `uid ではないユーザーの生成チケットの購入を受けました。残高に足していません (${summary})`);
    return { status: 200, body: "unknown user" };
  }

  const { firestore } = dependencies;
  const userDocument = firestore.doc(`users/${appUserId}`);
  const purchaseDocument = firestore.doc(`users/${appUserId}/ticketPurchases/${event.id}`);
  const outcome = await firestore.runTransaction(async (transaction): Promise<"added" | "duplicate" | "account_missing"> => {
    const [userSnapshot, purchaseSnapshot] = await Promise.all([transaction.get(userDocument), transaction.get(purchaseDocument)]);
    if (purchaseSnapshot.exists) {
      return "duplicate";
    }
    // アカウントの削除 (account.ts) が始まった後と消し終えた後は書かない。書くと、消し終えた後に users/{uid} が残るため。
    // 生成する前に買ったユーザーには users/{uid} が無いため、Auth のユーザーで見分ける (pipeline.ts の予約と同じ)
    if (userSnapshot.get("accountDeletionStartedAt") !== undefined || (!userSnapshot.exists && !(await authUserExists({ auth: dependencies.auth, uid: appUserId })))) {
      return "account_missing";
    }
    transaction.create(purchaseDocument, {
      productId: productId!,
      ticketCount,
      transactionId: optionalString(event.transaction_id),
      environment,
      store: optionalString(event.store),
      createdAt: Timestamp.fromDate(dependencies.now()),
    } satisfies TicketPurchaseDocument);
    transaction.set(userDocument, { generationTickets: FieldValue.increment(ticketCount) }, { merge: true });
    return "added";
  });
  if (outcome === "account_missing") {
    await notify(dependencies.sendMessage, `アカウントが無いか削除中のユーザーの生成チケットの購入を受けました。残高に足していません (${summary})`);
    return { status: 200, body: "account missing" };
  }
  if (outcome === "added") {
    await notify(dependencies.sendMessage, `生成チケットが ${ticketCount} 枚売れました (${summary})`);
  }
  return { status: 200, body: outcome };
}

/**
 * RevenueCat の webhook の受け口 (HTTP)。RevenueCat のダッシュボードで、この関数の URL と `Authorization` ヘッダーの値
 * (Secret `REVENUECAT_WEBHOOK_AUTHORIZATION` と同じ値) を設定する。App Check は RevenueCat のサーバーが付けられないため使わない。
 */
export const revenueCatWebhook = onRequest({ secrets: [revenueCatWebhookAuthorization, slackBotToken] }, async (request, response) => {
  if (request.method !== "POST") {
    response.status(405).send("method not allowed");
    return;
  }
  const result = await handleGenerationTicketWebhook(
    {
      firestore: getFirestore(),
      auth: getAuth(),
      sendMessage: ({ channel, text }) => postSlackMessage({ token: slackBotToken.value(), channel, text, fetchFunction: fetch }),
      expectedAuthorization: revenueCatWebhookAuthorization.value(),
      now: () => new Date(),
    },
    { authorization: request.get("Authorization"), body: request.body },
  );
  response.status(result.status).send(result.body);
});
