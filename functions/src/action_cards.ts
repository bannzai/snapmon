// Action Card の技の控え・選び直し・覚えさせる・忘れさせる callable と、技に割り振る商品の定期計算。購入を技に結び付けるのは
// RevenueCat の webhook (generation_tickets.ts)。構造と書き込みの主体は .claude/rules/firestore.md、規則は action_card_rules.ts と
// documents/game-rules.md「Action Card」。

import { randomUUID } from "node:crypto";

import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, type Firestore, Timestamp, type Transaction } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { authUserExists } from "./account";
import {
  MOVE_USAGE_WINDOW_DAYS,
  computeActionCardProductIDByMoveID,
  fallbackActionCardProductID,
  isActionCardProductID,
  previousDayKeys,
} from "./action_card_rules";
import { ENFORCE_APP_CHECK } from "./app_check";
import { requireSignedInUid } from "./battle";
import { fetchLatestMaster, learnableMoves } from "./generation/master";
import type { ActionCardPurchaseDocument } from "./generation_tickets";
import { requireActiveAccount } from "./pvp";
import { isDocumentID } from "./pvp_rules";

/**
 * 技ごとの Action Card の商品の表 (`actionCardProducts/current`)。updateActionCardProducts が毎日書き、購入の画面と
 * reserveActionCardMove・assignActionCardMove・webhook が読む。
 */
export interface ActionCardProductsDocument {
  /** 商品を割り振った master の版。 */
  version: number;
  /** 技の ID ごとの、その技を買える商品の ID。買える技 (最新の版の master の技のうち、置き換えられた技を除いたもの) だけを持つ。 */
  productIDByMoveID: Record<string, string>;
  /** 割り振った時刻。 */
  computedAt: Timestamp;
  /** 使用回数を集計した日数。 */
  usageWindowDays: number;
}

/**
 * 買う前に控えた技 (`users/{uid}.actionCardMoveReservation`)。reserveActionCardMove が書き (新しい控えで上書きする)、
 * RevenueCat の webhook が同じ商品の Action Card の購入を受けた時にこの技を購入に結び付けて消す (generation_tickets.ts)。
 * 端末が購入の後に技を伝える形にしないのは、購入の後にアプリが落ちると払ったのに技が手に入らないまま残るため (#290)。
 */
export interface ActionCardMoveReservation {
  /** 控えの ID。webhook が購入の記録に写し、端末はこの ID の購入が届くのを待つ (別の端末の購入と取り違えないため)。 */
  actionCardMoveReservationID: string;
  /** 控えた技の ID。 */
  moveID: string;
  /** 控えた時に技を買えた商品の ID。webhook はこの商品の購入だけをこの技に結び付ける。 */
  productID: string;
  /** 控えた時刻。 */
  reservedAt: Timestamp;
}

/**
 * 最新の版の master の買える技 [moveID] を今買える商品の ID ([transaction] で `actionCardProducts/current` を読む)。表に無い
 * (表が無い・表を作った後に master に足された) 技は段階で決める予備の商品 (action_card_rules.ts の fallbackActionCardProductID)。
 * 置き換えられた技・master に無い技は undefined。
 */
export async function currentActionCardProductID({
  firestore,
  transaction,
  moveID,
}: {
  firestore: Firestore;
  transaction: Transaction;
  moveID: string;
}): Promise<string | undefined> {
  // 投入済みの版は書き換えないため、トランザクションの外の読み取りでよい
  const move = learnableMoves((await fetchLatestMaster(firestore)).moves).find((candidate) => candidate.id === moveID);
  if (move === undefined) {
    return undefined;
  }
  const productIDByMoveID = ((await transaction.get(firestore.doc("actionCardProducts/current"))).get("productIDByMoveID") ?? {}) as Record<string, string>;
  return Object.hasOwn(productIDByMoveID, moveID) ? productIDByMoveID[moveID] : fallbackActionCardProductID(move);
}

/**
 * [uid] が技 [moveID] を買い切っているか (`users/{uid}/actionCardPurchases` に `moveID` がこの技の購入があるか)。[transaction] の中で読む。
 * Firestore のトランザクションは serializable のため ("Cloud Firestore guarantees serializable isolation of transactions."
 * https://firebase.google.com/docs/firestore/transaction-data-contention 、2026-11-10 に確認)、同じ技を 2 つの購入に結び付けない。
 */
export async function ownsActionCardMove({
  firestore,
  transaction,
  uid,
  moveID,
}: {
  firestore: Firestore;
  transaction: Transaction;
  uid: string;
  moveID: string;
}): Promise<boolean> {
  return !(await transaction.get(firestore.collection(`users/${uid}/actionCardPurchases`).where("moveID", "==", moveID).limit(1))).empty;
}

/**
 * 直近 [MOVE_USAGE_WINDOW_DAYS] 日の `moveUsageDailyCounts` を合計し、最新の版の master の買える技に割り振った商品を
 * `actionCardProducts/current` に書く (updateActionCardProducts の本体。テストは Firestore と時刻を渡して直接呼ぶ)。
 * 同じ入力からは同じ表を書く (冪等)。返す値は書いた表。
 */
export async function updateActionCardProductsWith({ firestore, now }: { firestore: Firestore; now: Date }): Promise<ActionCardProductsDocument> {
  const [master, usageSnapshots] = await Promise.all([
    fetchLatestMaster(firestore),
    firestore.getAll(...previousDayKeys({ now, days: MOVE_USAGE_WINDOW_DAYS }).map((dayKey) => firestore.doc(`moveUsageDailyCounts/${dayKey}`))),
  ]);
  const usageCountByMoveID: Record<string, number> = {};
  for (const snapshot of usageSnapshots) {
    for (const [moveID, count] of Object.entries((snapshot.get("counts") ?? {}) as Record<string, unknown>)) {
      if (typeof count === "number") {
        usageCountByMoveID[moveID] = (usageCountByMoveID[moveID] ?? 0) + count;
      }
    }
  }
  const actionCardProducts: ActionCardProductsDocument = {
    version: master.version,
    productIDByMoveID: computeActionCardProductIDByMoveID({ moves: learnableMoves(master.moves), usageCountByMoveID }),
    computedAt: Timestamp.fromDate(now),
    usageWindowDays: MOVE_USAGE_WINDOW_DAYS,
  };
  await firestore.doc("actionCardProducts/current").set(actionCardProducts);
  return actionCardProducts;
}

/**
 * 技に割り振る商品を毎日 1 回決め直す (日本時間の 4 時。利用者の少ない時間で、日本時間で区切った前日までの集計が出そろった後にするため)。
 */
export const updateActionCardProducts = onSchedule({ schedule: "0 4 * * *", timeZone: "Asia/Tokyo" }, async () => {
  await updateActionCardProductsWith({ firestore: getFirestore(), now: new Date() });
});

/**
 * Action Card を買う前に、買う技を控える callable。端末は控えた商品をストアで購入し、webhook が購入をこの技に結び付ける。
 *
 * 受け取る data: `{ moveID: string, productID: string }` (最新の版の master の買える技の ID と、端末が値段を出した商品の ID)。
 * 返す値: `{ actionCardMoveReservationID, moveID, productID }`。
 * 技を今買える商品が `productID` と違えば (値段を出している間に技の商品が変わった) 控えずに failed-precondition で断り、`details` に今の商品
 * `productID` を返す (出した値段と違う商品を買わせないため)。既に買い切った技は already-exists、置き換えられた技・master に無い技は not-found、
 * 形が違えば (Action Card の商品の ID でないものを含む) invalid-argument。
 * 控えは 1 件だけで、呼ぶたびに新しい ID で上書きする (前の控えで買わなかった技を、後の購入に結び付けないため)。
 * 生成する前の (`users/{uid}` の無い) ユーザーも、webhook と同じく Auth のユーザーで見分けて受け付ける (生成の前にも買えるようにするため)。
 */
export const reserveActionCardMove = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { moveID, productID } = (request.data ?? {}) as { moveID?: unknown; productID?: unknown };
  if (!isDocumentID(moveID) || typeof productID !== "string" || !isActionCardProductID(productID)) {
    throw new HttpsError("invalid-argument", "moveID と productID (Action Card の商品の ID) を渡してください");
  }
  const firestore = getFirestore();
  const userDocument = firestore.doc(`users/${uid}`);
  return firestore.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userDocument);
    if (userSnapshot.get("accountDeletionStartedAt") !== undefined || (!userSnapshot.exists && !(await authUserExists({ auth: getAuth(), uid })))) {
      throw new HttpsError("failed-precondition", "アカウントの削除が進んでいるか、アカウントが見つかりません");
    }
    const moveProductID = await currentActionCardProductID({ firestore, transaction, moveID });
    if (moveProductID === undefined) {
      throw new HttpsError("not-found", `買える技に ${moveID} はありません`);
    }
    if (await ownsActionCardMove({ firestore, transaction, uid, moveID })) {
      throw new HttpsError("already-exists", `${moveID} は買い切り済みです`);
    }
    if (moveProductID !== productID) {
      throw new HttpsError("failed-precondition", `${moveID} を買える商品が ${productID} から ${moveProductID} に変わりました`, {
        productID: moveProductID,
      });
    }
    const actionCardMoveReservation: ActionCardMoveReservation = {
      actionCardMoveReservationID: randomUUID(),
      moveID,
      productID: moveProductID,
      reservedAt: Timestamp.now(),
    };
    transaction.set(userDocument, { actionCardMoveReservation }, { merge: true });
    return { actionCardMoveReservationID: actionCardMoveReservation.actionCardMoveReservationID, moveID, productID: moveProductID };
  });
});

/**
 * 技に結び付いていない Action Card の購入 (`moveID` が null か無いもの) に、利用者が選び直した技を結び付ける callable。
 * 控えた技を購入に結び付けられなかった時 (技を選んでから購入が届くまでの間に技の商品が変わった・既に同じ技を買い切っていた・控えが無かった) だけ使う。
 *
 * 受け取る data: `{ actionCardPurchaseID: string, moveID: string }`。返す値: `{ actionCardPurchaseID, moveID }`。
 * 技を今買える商品が購入した商品と違えば failed-precondition (払った値段と違う値段の技を渡さないため。#293)、既に買い切った技は already-exists、
 * 購入が無ければ not-found、既に技に結び付いた購入は failed-precondition、置き換えられた技・master に無い技は not-found。断った時は購入を変えない。
 */
export const assignActionCardMove = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { actionCardPurchaseID, moveID } = (request.data ?? {}) as { actionCardPurchaseID?: unknown; moveID?: unknown };
  if (!isDocumentID(actionCardPurchaseID) || !isDocumentID(moveID)) {
    throw new HttpsError("invalid-argument", "actionCardPurchaseID と moveID を渡してください");
  }
  const firestore = getFirestore();
  const purchaseDocument = firestore.doc(`users/${uid}/actionCardPurchases/${actionCardPurchaseID}`);
  return firestore.runTransaction(async (transaction) => {
    const [userSnapshot, purchaseSnapshot] = await transaction.getAll(firestore.doc(`users/${uid}`), purchaseDocument);
    requireActiveAccount({ userSnapshot });
    if (!purchaseSnapshot.exists) {
      throw new HttpsError("not-found", `Action Card の購入 ${actionCardPurchaseID} はありません`);
    }
    // この変更 (#290) より前の購入は moveID を持たないため、無い時も技に結び付いていない購入として扱う
    if (typeof purchaseSnapshot.get("moveID") === "string") {
      throw new HttpsError("failed-precondition", `Action Card の購入 ${actionCardPurchaseID} は技を受け取り済みです`);
    }
    const moveProductID = await currentActionCardProductID({ firestore, transaction, moveID });
    if (moveProductID === undefined) {
      throw new HttpsError("not-found", `買える技に ${moveID} はありません`);
    }
    if (await ownsActionCardMove({ firestore, transaction, uid, moveID })) {
      throw new HttpsError("already-exists", `${moveID} は買い切り済みです`);
    }
    const purchasedProductID = purchaseSnapshot.get("productID") as string;
    if (moveProductID !== purchasedProductID) {
      throw new HttpsError("failed-precondition", `${purchasedProductID} の Action Card では ${moveProductID} で買う技 ${moveID} を受け取れません`);
    }
    transaction.update(purchaseDocument, { moveID, moveAssignedAt: Timestamp.now() } satisfies Partial<ActionCardPurchaseDocument>);
    return { actionCardPurchaseID, moveID };
  });
});

/** teach・forget の callable の request.data `{ monsterID, moveID }` を確かめて返す。形が違えば invalid-argument を投げる。 */
function monsterMoveArguments(requestData: unknown): { monsterID: string; moveID: string } {
  const { monsterID, moveID } = (requestData ?? {}) as { monsterID?: unknown; moveID?: unknown };
  if (!isDocumentID(monsterID) || !isDocumentID(moveID)) {
    throw new HttpsError("invalid-argument", "monsterID と moveID を渡してください");
  }
  return { monsterID, moveID };
}

/**
 * 買い切った技を本人のモンスターに覚えさせる callable。
 *
 * 受け取る data: `{ monsterID: string, moveID: string }`。返す値: `{ actionCardMoveIDs: string[] }` (覚えさせた後の一覧)。
 * `users/{uid}/monsters/{monsterID}.actionCardMoveIDs` の末尾に足す (既に入っていれば変えない。冪等)。生まれた時の learnset は書き換えない。
 * 買い切っていない技は failed-precondition、図鑑に無いモンスター (他人のモンスターを含む) は not-found。
 */
export const teachActionCardMove = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { monsterID, moveID } = monsterMoveArguments(request.data);
  const firestore = getFirestore();
  const monsterDocument = firestore.doc(`users/${uid}/monsters/${monsterID}`);
  return firestore.runTransaction(async (transaction) => {
    const [userSnapshot, monsterSnapshot] = await transaction.getAll(firestore.doc(`users/${uid}`), monsterDocument);
    requireActiveAccount({ userSnapshot });
    if (!monsterSnapshot.exists) {
      throw new HttpsError("not-found", `図鑑にモンスター ${monsterID} はいません`);
    }
    if (!(await ownsActionCardMove({ firestore, transaction, uid, moveID: moveID }))) {
      throw new HttpsError("failed-precondition", `${moveID} を買い切っていません`);
    }
    const actionCardMoveIDs = (monsterSnapshot.get("actionCardMoveIDs") ?? []) as string[];
    if (actionCardMoveIDs.includes(moveID)) {
      return { actionCardMoveIDs };
    }
    transaction.update(monsterDocument, { actionCardMoveIDs: FieldValue.arrayUnion(moveID) });
    return { actionCardMoveIDs: [...actionCardMoveIDs, moveID] };
  });
});

/**
 * 覚えさせた技を本人のモンスターから忘れさせる callable。買い切った技は残るため、何度でも覚え直せる。
 *
 * 受け取る data: `{ monsterID: string, moveID: string }`。返す値: `{ actionCardMoveIDs: string[] }` (忘れさせた後の一覧)。
 * 覚えていない技なら変えない (冪等)。図鑑に無いモンスター (他人のモンスターを含む) は not-found。
 */
export const forgetActionCardMove = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { monsterID, moveID } = monsterMoveArguments(request.data);
  const firestore = getFirestore();
  const monsterDocument = firestore.doc(`users/${uid}/monsters/${monsterID}`);
  return firestore.runTransaction(async (transaction) => {
    const [userSnapshot, monsterSnapshot] = await transaction.getAll(firestore.doc(`users/${uid}`), monsterDocument);
    requireActiveAccount({ userSnapshot });
    if (!monsterSnapshot.exists) {
      throw new HttpsError("not-found", `図鑑にモンスター ${monsterID} はいません`);
    }
    const actionCardMoveIDs = (monsterSnapshot.get("actionCardMoveIDs") ?? []) as string[];
    if (!actionCardMoveIDs.includes(moveID)) {
      return { actionCardMoveIDs };
    }
    transaction.update(monsterDocument, { actionCardMoveIDs: FieldValue.arrayRemove(moveID) });
    return { actionCardMoveIDs: actionCardMoveIDs.filter((actionCardMoveID) => actionCardMoveID !== moveID) };
  });
});
