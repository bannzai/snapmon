// 生成チケット (1 日の無料の回数を使い切った後に生成できる消耗型の商品) と Action Card (技を 1 つ選んで買い切る消耗型の商品) の購入を、
// RevenueCat の webhook で受ける。
// 生成チケットの残高は `users/{uid}.generationTickets` に置き、生成の予約 (generation/pipeline.ts の startGeneration) が 1 枚ずつ減らす。
// Action Card は購入 1 件を `users/{uid}/actionCardPurchases/{eventID}` に置き、買う前に控えた技 (action_cards.ts の reserveActionCardMove) を
// その購入に結び付ける。枚数の残高は持たない (#290)。
// 受け取る形は https://www.revenuecat.com/docs/integrations/webhooks/event-types-and-fields (2026-11-07 に確認): 本文は
// `{ api_version, event }` で、消耗型を含む自動更新しない購入は `event.type` が `NON_RENEWING_PURCHASE`、返金と取り消しは `CANCELLATION`。

import { timingSafeEqual } from "node:crypto";

import { type Auth, getAuth } from "firebase-admin/auth";
import { FieldValue, type Firestore, getFirestore, Timestamp, type Transaction } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/v2/https";

import { authUserExists } from "./account";
import { isActionCardProductID } from "./action_card_rules";
import { type ActionCardMoveReservation, currentActionCardProductID, ownsActionCardMove } from "./action_cards";
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

/** [productID] が生成チケットの商品なら 1 回の購入で足す枚数、それ以外は undefined。継承したキー (`constructor` 等) を商品として扱わない。 */
function generationTicketCount(productID: string | null): number | undefined {
  return productID !== null && Object.hasOwn(GENERATION_TICKET_COUNT_BY_PRODUCT_ID, productID) ? GENERATION_TICKET_COUNT_BY_PRODUCT_ID[productID] : undefined;
}

/** 消耗型の商品の種類。生成チケットは足す枚数を持つ。Action Card は商品の ID そのものが技を結び付ける条件で、別の値を持たない。 */
type ConsumableProduct = { kind: "generationTicket"; ticketCount: number } | { kind: "actionCard" };

/** [productID] がこのアプリの消耗型の商品ならその種類、それ以外は undefined。 */
function consumableProductOf(productID: string | null): ConsumableProduct | undefined {
  const ticketCount = generationTicketCount(productID);
  if (ticketCount !== undefined) {
    return { kind: "generationTicket", ticketCount };
  }
  return isActionCardProductID(productID) ? { kind: "actionCard" } : undefined;
}

/** [product] の商品の、Slack の通知に書く名前。商品の ID は通知の summary に別に出す。 */
function productLabel(product: ConsumableProduct): string {
  return product.kind === "generationTicket" ? "生成チケット" : "Action Card";
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

/** 生成チケットの購入の記録 (`users/{uid}/ticketPurchases/{eventID}`)。同じイベントを 2 回足さない判定と購入の履歴に使う。 */
export interface TicketPurchaseDocument {
  /** 商品の識別子。 */
  productID: string;
  /** 足した枚数。 */
  ticketCount: number;
  /** ストアの取引の ID (RevenueCat が送らなかった時は null)。 */
  transactionID: string | null;
  /** `SANDBOX` か `PRODUCTION` (RevenueCat が送らなかった時は null)。 */
  environment: string | null;
  /** 購入したストア (RevenueCat が送らなかった時は null)。 */
  store: string | null;
  /** 記録した時刻。 */
  createdAt: Timestamp;
}

/**
 * Action Card の購入 1 件 (`users/{uid}/actionCardPurchases/{eventID}`)。同じイベントを 2 回記録しない判定に使い、買い切った技はこの記録の
 * `moveID` から出す (技ごとのドキュメントと残高の枚数を別に持たない。#290)。形は [TicketPurchaseDocument] の枚数の代わりに技を持つ。
 * 買った商品は `productID` (webhook が届いた商品の ID をそのまま書く) で、この購入で受け取れる技は、受け取る時にその商品で買える技 (#293)。
 */
export interface ActionCardPurchaseDocument extends Omit<TicketPurchaseDocument, "ticketCount"> {
  /**
   * この購入で買い切った技の ID。技に結び付いていない購入 (利用者が技を選び直して受け取る) は null。
   * この変更 (#290) より前の購入はこのフィールドを持たず、無い時も null と同じに扱う。
   */
  moveID: string | null;
  /** 購入に結び付けた控えの ID (action_cards.ts の ActionCardMoveReservation)。控えの商品が購入と違い控えを使わなかった時は null。 */
  actionCardMoveReservationID: string | null;
  /** `moveID` を結び付けた時刻。技に結び付いていない間は null。 */
  moveAssignedAt: Timestamp | null;
}

/** webhook の処理に使う外部の資源。本番は onRequest が、テストはモックを渡す。 */
export interface RevenueCatWebhookDependencies {
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
export interface RevenueCatWebhookResponse {
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
    logger.error("購入の通知を Slack に送れませんでした", { error, text });
  }
}

/**
 * 技 [reservation] (購入と同じ商品の控え) を今受け取れるか。技が今も買え、今の技の商品が控えの商品 (= 買った商品) と同じで、まだ買い切っていない時だけ true
 * (控えてから購入が届くまでの間に技の商品が変わった時は、払った値段と違う値段の技を渡さないため。#293)。
 * [transaction] の中で読む (同じ技を 2 つの購入に結び付けないため。action_cards.ts の ownsActionCardMove)。
 */
async function canReceiveReservedMove({
  firestore,
  transaction,
  uid,
  reservation,
}: {
  firestore: Firestore;
  transaction: Transaction;
  uid: string;
  reservation: ActionCardMoveReservation;
}): Promise<boolean> {
  return (
    (await currentActionCardProductID({ firestore, transaction, moveID: reservation.moveID })) === reservation.productID &&
    !(await ownsActionCardMove({ firestore, transaction, uid, moveID: reservation.moveID }))
  );
}

/**
 * RevenueCat の webhook を受け、消耗型の商品の購入を記録する (onRequest の本体)。生成チケットは `users/{uid}.generationTickets` に枚数を足す。
 * Action Card は購入の記録に、`users/{uid}.actionCardMoveReservation` の同じ商品の控えの技を結び付け (受け取れない時は技に結び付けずに残し、
 * 利用者が assignActionCardMove で選び直す)、使った控えを消す。端末が購入の後に何も呼ばなくても技が手に入る。
 *
 * - `Authorization` が RevenueCat に設定した値と一致しない時は 401 で、何も書かない
 * - `NON_RENEWING_PURCHASE` で、商品が生成チケットか Action Card で、`app_user_id` が uid の形で、アカウントが残っている時だけ記録する。同じイベントの ID の
 *   2 回目は記録しない (購入の記録 `users/{uid}/ticketPurchases/{eventID}`・`users/{uid}/actionCardPurchases/{eventID}` を足す時と同じトランザクションで作る)
 * - 返金・取り消し (`CANCELLATION`) は残高・買い切った技を減らさず Slack に知らせる (残高が負になる扱いを作らないため。DIRECTION.md「決めたこと」2026-11-07 の行と
 *   2026-11-09 の #271 の行)
 * - 足せない購入 (知らない商品・uid の形でない・アカウントが無い) は Slack に知らせて 200 を返す (再送しても足せないため)
 * - それ以外のイベントは何もせず 200 を返す
 *
 * Firestore の書き込みが失敗した時は投げる (onRequest が 500 を返し、RevenueCat が再送する)。
 */
export async function handleRevenueCatWebhook(
  dependencies: RevenueCatWebhookDependencies,
  { authorization, body }: { authorization: string | undefined; body: unknown },
): Promise<RevenueCatWebhookResponse> {
  if (!isAuthorized({ authorization, expectedAuthorization: dependencies.expectedAuthorization })) {
    return { status: 401, body: "unauthorized" };
  }
  const event = ((body ?? {}) as { event?: RevenueCatWebhookEvent }).event;
  if (!event || typeof event.id !== "string" || !REVENUECAT_EVENT_ID_PATTERN.test(event.id) || typeof event.type !== "string") {
    return { status: 400, body: "event.id と event.type がないか、event.id の形が違います" };
  }
  const appUserID = event.app_user_id;
  const productID = optionalString(event.product_id);
  const environment = optionalString(event.environment);
  const summary = `イベント ${event.id}・ユーザー ${String(appUserID)}・商品 ${productID ?? "(なし)"}・環境 ${environment ?? "(なし)"}`;
  const product = consumableProductOf(productID);

  if (event.type === "CANCELLATION") {
    if (product !== undefined) {
      await notify(dependencies.sendMessage, `${productLabel(product)}の返金・取り消しを受けました。残高は減らしていません (${summary})`);
    }
    return { status: 200, body: "ignored" };
  }
  if (event.type !== "NON_RENEWING_PURCHASE") {
    return { status: 200, body: "ignored" };
  }
  if (product === undefined) {
    // 生成チケットと Action Card 以外の消耗型の商品は無いため、届いたら設定の誤りとして知らせる
    await notify(dependencies.sendMessage, `知らない商品の購入を受けました。残高に足していません (${summary})`);
    return { status: 200, body: "unknown product" };
  }
  if (typeof appUserID !== "string" || !FIREBASE_UID_PATTERN.test(appUserID)) {
    await notify(dependencies.sendMessage, `uid ではないユーザーの${productLabel(product)}の購入を受けました。残高に足していません (${summary})`);
    return { status: 200, body: "unknown user" };
  }

  const { firestore } = dependencies;
  const userDocument = firestore.doc(`users/${appUserID}`);
  const purchaseRecord = {
    productID: productID!,
    transactionID: optionalString(event.transaction_id),
    environment,
    store: optionalString(event.store),
    createdAt: Timestamp.fromDate(dependencies.now()),
  };
  const purchaseDocument =
    product.kind === "generationTicket"
      ? firestore.doc(`users/${appUserID}/ticketPurchases/${event.id}`)
      : firestore.doc(`users/${appUserID}/actionCardPurchases/${event.id}`);
  const outcome = await firestore.runTransaction(async (transaction): Promise<"added" | "duplicate" | "account_missing"> => {
    const [userSnapshot, purchaseSnapshot] = await Promise.all([transaction.get(userDocument), transaction.get(purchaseDocument)]);
    if (purchaseSnapshot.exists) {
      return "duplicate";
    }
    // アカウントの削除 (account.ts) が始まった後と消し終えた後は書かない。書くと、消し終えた後に users/{uid} が残るため。
    // 生成する前に買ったユーザーには users/{uid} が無いため、Auth のユーザーで見分ける (pipeline.ts の予約と同じ)
    if (userSnapshot.get("accountDeletionStartedAt") !== undefined || (!userSnapshot.exists && !(await authUserExists({ auth: dependencies.auth, uid: appUserID })))) {
      return "account_missing";
    }
    if (product.kind === "generationTicket") {
      transaction.create(purchaseDocument, { ...purchaseRecord, ticketCount: product.ticketCount } satisfies TicketPurchaseDocument);
      transaction.set(userDocument, { generationTickets: FieldValue.increment(product.ticketCount) }, { merge: true });
      return "added";
    }
    const reservation = userSnapshot.get("actionCardMoveReservation") as ActionCardMoveReservation | undefined;
    // 控えの商品が届いた商品と違う時は、別の購入のための控えのため使わずに残す (このアプリは控えてから買うため、通常は起きない)
    const matchedReservation = reservation?.productID === productID ? reservation : undefined;
    const moveID =
      matchedReservation !== undefined && (await canReceiveReservedMove({ firestore, transaction, uid: appUserID, reservation: matchedReservation }))
        ? matchedReservation.moveID
        : null;
    transaction.create(purchaseDocument, {
      ...purchaseRecord,
      moveID,
      actionCardMoveReservationID: matchedReservation?.actionCardMoveReservationID ?? null,
      moveAssignedAt: moveID === null ? null : purchaseRecord.createdAt,
    } satisfies ActionCardPurchaseDocument);
    if (matchedReservation !== undefined) {
      transaction.update(userDocument, { actionCardMoveReservation: FieldValue.delete() });
    } else if (!userSnapshot.exists) {
      // 生成も控えもしていないユーザーには users/{uid} が無いが、購入は users/{uid} の配下に置くため作る (生成チケットの購入と同じ)
      transaction.set(userDocument, {}, { merge: true });
    }
    return "added";
  });
  if (outcome === "account_missing") {
    await notify(dependencies.sendMessage, `アカウントが無いか削除中のユーザーの${productLabel(product)}の購入を受けました。残高に足していません (${summary})`);
    return { status: 200, body: "account missing" };
  }
  if (outcome === "added") {
    await notify(
      dependencies.sendMessage,
      product.kind === "generationTicket" ? `生成チケットが ${product.ticketCount} 枚売れました (${summary})` : `${productLabel(product)}が売れました (${summary})`,
    );
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
  try {
    const result = await handleRevenueCatWebhook(
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
  } catch (error) {
    // 失敗したトランザクションは何も書かないため、500 で RevenueCat に再送させても二重に足さない
    logger.error("RevenueCat の webhook の処理に失敗しました", { error });
    response.status(500).send("internal error");
  }
});
