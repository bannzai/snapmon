// Action Card の技の控え・選び直し・覚えさせる・忘れさせる callable と、技のランクの定期計算。購入を技に結び付けるのは
// RevenueCat の webhook (generation_tickets.ts)。構造と書き込みの主体は .claude/rules/firestore.md、規則は action_card_rules.ts と
// documents/game-rules.md「Action Card」。

import { randomUUID } from "node:crypto";

import { getAuth } from "firebase-admin/auth";
import { FieldValue, getFirestore, type Firestore, Timestamp, type Transaction } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { authUserExists } from "./account";
import { MOVE_RANKS, MOVE_USAGE_WINDOW_DAYS, type MoveRank, canAssignMoveToActionCard, computeMoveRanks, fallbackMoveRank, previousDayKeys } from "./action_card_rules";
import { ENFORCE_APP_CHECK } from "./app_check";
import { requireSignedInUid } from "./battle";
import { fetchLatestMaster, learnableMoves } from "./generation/master";
import type { ActionCardPurchaseDocument } from "./generation_tickets";
import { requireActiveAccount } from "./pvp";
import { isDocumentId } from "./pvp_rules";

/** 技のランクの表 (`moveRanks/current`)。updateMoveRanks が毎日書き、購入の画面と reserveActionCardMove・assignActionCardMove・webhook が読む。 */
export interface MoveRanksDocument {
  /** ランクを決めた master の版。 */
  version: number;
  /** 技の ID ごとのランク。買える技 (最新の版の master の技のうち、置き換えられた技を除いたもの) だけを持つ。 */
  rankByMoveId: Record<string, MoveRank>;
  /** 決めた時刻。 */
  computedAt: Timestamp;
  /** 使用回数を集計した日数。 */
  usageWindowDays: number;
}

/**
 * 買う前に控えた技 (`users/{uid}.actionCardMoveReservation`)。reserveActionCardMove が書き (新しい控えで上書きする)、
 * RevenueCat の webhook が同じランクの Action Card の購入を受けた時にこの技を購入に結び付けて消す (generation_tickets.ts)。
 * 端末が購入の後に技を伝える形にしないのは、購入の後にアプリが落ちると払ったのに技が手に入らないまま残るため (#290)。
 */
export interface ActionCardMoveReservation {
  /** 控えの ID。webhook が購入の記録に写し、端末はこの ID の購入が届くのを待つ (別の端末の購入と取り違えないため)。 */
  actionCardMoveReservationID: string;
  /** 控えた技の ID。 */
  moveID: string;
  /** 控えた時の技のランク。webhook はこのランクの商品の購入だけをこの技に結び付ける。 */
  rank: MoveRank;
  /** 控えた時刻。 */
  reservedAt: Timestamp;
}

/**
 * 最新の版の master の買える技 [moveID] の今のランク ([transaction] で `moveRanks/current` を読む)。表に無い
 * (表が無い・表を作った後に master に足された) 技は段階で決める予備のランク (action_card_rules.ts の fallbackMoveRank)。
 * 置き換えられた技・master に無い技は undefined。
 */
export async function currentMoveRank({
  firestore,
  transaction,
  moveID,
}: {
  firestore: Firestore;
  transaction: Transaction;
  moveID: string;
}): Promise<MoveRank | undefined> {
  // 投入済みの版は書き換えないため、トランザクションの外の読み取りでよい
  const move = learnableMoves((await fetchLatestMaster(firestore)).moves).find((candidate) => candidate.id === moveID);
  if (move === undefined) {
    return undefined;
  }
  const rankByMoveId = ((await transaction.get(firestore.doc("moveRanks/current"))).get("rankByMoveId") ?? {}) as Record<string, MoveRank>;
  return Object.hasOwn(rankByMoveId, moveID) ? rankByMoveId[moveID] : fallbackMoveRank(move);
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
 * 直近 [MOVE_USAGE_WINDOW_DAYS] 日の `moveUsageDailyCounts` を合計し、最新の版の master の買える技のランクを `moveRanks/current` に書く
 * (updateMoveRanks の本体。テストは Firestore と時刻を渡して直接呼ぶ)。同じ入力からは同じ表を書く (冪等)。返す値は書いた表。
 */
export async function updateMoveRanksWith({ firestore, now }: { firestore: Firestore; now: Date }): Promise<MoveRanksDocument> {
  const [master, usageSnapshots] = await Promise.all([
    fetchLatestMaster(firestore),
    firestore.getAll(...previousDayKeys({ now, days: MOVE_USAGE_WINDOW_DAYS }).map((dayKey) => firestore.doc(`moveUsageDailyCounts/${dayKey}`))),
  ]);
  const usageCountByMoveId: Record<string, number> = {};
  for (const snapshot of usageSnapshots) {
    for (const [moveId, count] of Object.entries((snapshot.get("counts") ?? {}) as Record<string, unknown>)) {
      if (typeof count === "number") {
        usageCountByMoveId[moveId] = (usageCountByMoveId[moveId] ?? 0) + count;
      }
    }
  }
  const moveRanks: MoveRanksDocument = {
    version: master.version,
    rankByMoveId: computeMoveRanks({ moves: learnableMoves(master.moves), usageCountByMoveId }),
    computedAt: Timestamp.fromDate(now),
    usageWindowDays: MOVE_USAGE_WINDOW_DAYS,
  };
  await firestore.doc("moveRanks/current").set(moveRanks);
  return moveRanks;
}

/**
 * 技のランクを毎日 1 回決め直す (日本時間の 4 時。利用者の少ない時間で、日本時間で区切った前日までの集計が出そろった後にするため)。
 */
export const updateMoveRanks = onSchedule({ schedule: "0 4 * * *", timeZone: "Asia/Tokyo" }, async () => {
  await updateMoveRanksWith({ firestore: getFirestore(), now: new Date() });
});

/**
 * Action Card を買う前に、買う技を控える callable。端末は返った控えのランクの商品をストアで購入し、webhook が購入をこの技に結び付ける。
 *
 * 受け取る data: `{ moveID: string, rank: 1 | 2 | 3 }` (最新の版の master の買える技の ID と、端末が値段を出した技のランク)。
 * 返す値: `{ actionCardMoveReservationID, moveID, rank }`。
 * 技の今のランクが `rank` と違えば (値段を出している間にランクが変わった) 控えずに failed-precondition で断り、`details` に今のランク `rank` を返す
 * (出した値段と違う商品を買わせないため)。既に買い切った技は already-exists、置き換えられた技・master に無い技は not-found、形が違えば invalid-argument。
 * 控えは 1 件だけで、呼ぶたびに新しい ID で上書きする (前の控えで買わなかった技を、後の購入に結び付けないため)。
 * 生成する前の (`users/{uid}` の無い) ユーザーも、webhook と同じく Auth のユーザーで見分けて受け付ける (生成の前にも買えるようにするため)。
 */
export const reserveActionCardMove = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { moveID, rank } = (request.data ?? {}) as { moveID?: unknown; rank?: unknown };
  if (!isDocumentId(moveID) || !MOVE_RANKS.includes(rank as MoveRank)) {
    throw new HttpsError("invalid-argument", "moveID と rank (1・2・3 のどれか) を渡してください");
  }
  const firestore = getFirestore();
  const userDocument = firestore.doc(`users/${uid}`);
  return firestore.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userDocument);
    if (userSnapshot.get("accountDeletionStartedAt") !== undefined || (!userSnapshot.exists && !(await authUserExists({ auth: getAuth(), uid })))) {
      throw new HttpsError("failed-precondition", "アカウントの削除が進んでいるか、アカウントが見つかりません");
    }
    const moveRank = await currentMoveRank({ firestore, transaction, moveID });
    if (moveRank === undefined) {
      throw new HttpsError("not-found", `買える技に ${moveID} はありません`);
    }
    if (await ownsActionCardMove({ firestore, transaction, uid, moveID })) {
      throw new HttpsError("already-exists", `${moveID} は買い切り済みです`);
    }
    if (moveRank !== rank) {
      throw new HttpsError("failed-precondition", `${moveID} のランクが ${String(rank)} から ${moveRank} に変わりました`, { rank: moveRank });
    }
    const actionCardMoveReservation: ActionCardMoveReservation = {
      actionCardMoveReservationID: randomUUID(),
      moveID,
      rank: moveRank,
      reservedAt: Timestamp.now(),
    };
    transaction.set(userDocument, { actionCardMoveReservation }, { merge: true });
    return { actionCardMoveReservationID: actionCardMoveReservation.actionCardMoveReservationID, moveID, rank: moveRank };
  });
});

/**
 * 技に結び付いていない Action Card の購入 (`moveID` が null か無いもの) に、利用者が選び直した技を結び付ける callable。
 * 控えた技を購入に結び付けられなかった時 (技を選んでから購入が届くまでの間にランクが上がった・既に同じ技を買い切っていた・控えが無かった) だけ使う。
 *
 * 受け取る data: `{ actionCardPurchaseID: string, moveID: string }`。返す値: `{ actionCardPurchaseID, moveID }`。
 * 技の今のランクが購入のランクより高ければ failed-precondition (action_card_rules.ts の canAssignMoveToActionCard)、既に買い切った技は already-exists、
 * 購入が無ければ not-found、既に技に結び付いた購入は failed-precondition、置き換えられた技・master に無い技は not-found。断った時は購入を変えない。
 */
export const assignActionCardMove = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { actionCardPurchaseID, moveID } = (request.data ?? {}) as { actionCardPurchaseID?: unknown; moveID?: unknown };
  if (!isDocumentId(actionCardPurchaseID) || !isDocumentId(moveID)) {
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
    const moveRank = await currentMoveRank({ firestore, transaction, moveID });
    if (moveRank === undefined) {
      throw new HttpsError("not-found", `買える技に ${moveID} はありません`);
    }
    if (await ownsActionCardMove({ firestore, transaction, uid, moveID })) {
      throw new HttpsError("already-exists", `${moveID} は買い切り済みです`);
    }
    const actionCardRank = purchaseSnapshot.get("rank") as MoveRank;
    if (!canAssignMoveToActionCard({ moveRank, actionCardRank })) {
      throw new HttpsError("failed-precondition", `ランク ${actionCardRank} の Action Card ではランク ${moveRank} の ${moveID} を受け取れません`);
    }
    transaction.update(purchaseDocument, { moveID, moveAssignedAt: Timestamp.now() } satisfies Partial<ActionCardPurchaseDocument>);
    return { actionCardPurchaseID, moveID };
  });
});

/** teach・forget の callable の request.data `{ monsterId, moveId }` を確かめて返す。形が違えば invalid-argument を投げる。 */
function monsterMoveArguments(requestData: unknown): { monsterId: string; moveId: string } {
  const { monsterId, moveId } = (requestData ?? {}) as { monsterId?: unknown; moveId?: unknown };
  if (!isDocumentId(monsterId) || !isDocumentId(moveId)) {
    throw new HttpsError("invalid-argument", "monsterId と moveId を渡してください");
  }
  return { monsterId, moveId };
}

/**
 * 買い切った技を本人のモンスターに覚えさせる callable。
 *
 * 受け取る data: `{ monsterId: string, moveId: string }`。返す値: `{ actionCardMoveIds: string[] }` (覚えさせた後の一覧)。
 * `users/{uid}/monsters/{monsterId}.actionCardMoveIds` の末尾に足す (既に入っていれば変えない。冪等)。生まれた時の learnset は書き換えない。
 * 買い切っていない技は failed-precondition、図鑑に無いモンスター (他人のモンスターを含む) は not-found。
 */
export const teachActionCardMove = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { monsterId, moveId } = monsterMoveArguments(request.data);
  const firestore = getFirestore();
  const monsterDocument = firestore.doc(`users/${uid}/monsters/${monsterId}`);
  return firestore.runTransaction(async (transaction) => {
    const [userSnapshot, monsterSnapshot] = await transaction.getAll(firestore.doc(`users/${uid}`), monsterDocument);
    requireActiveAccount({ userSnapshot });
    if (!monsterSnapshot.exists) {
      throw new HttpsError("not-found", `図鑑にモンスター ${monsterId} はいません`);
    }
    if (!(await ownsActionCardMove({ firestore, transaction, uid, moveID: moveId }))) {
      throw new HttpsError("failed-precondition", `${moveId} を買い切っていません`);
    }
    const actionCardMoveIds = (monsterSnapshot.get("actionCardMoveIds") ?? []) as string[];
    if (actionCardMoveIds.includes(moveId)) {
      return { actionCardMoveIds };
    }
    transaction.update(monsterDocument, { actionCardMoveIds: FieldValue.arrayUnion(moveId) });
    return { actionCardMoveIds: [...actionCardMoveIds, moveId] };
  });
});

/**
 * 覚えさせた技を本人のモンスターから忘れさせる callable。買い切った技は残るため、何度でも覚え直せる。
 *
 * 受け取る data: `{ monsterId: string, moveId: string }`。返す値: `{ actionCardMoveIds: string[] }` (忘れさせた後の一覧)。
 * 覚えていない技なら変えない (冪等)。図鑑に無いモンスター (他人のモンスターを含む) は not-found。
 */
export const forgetActionCardMove = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { monsterId, moveId } = monsterMoveArguments(request.data);
  const firestore = getFirestore();
  const monsterDocument = firestore.doc(`users/${uid}/monsters/${monsterId}`);
  return firestore.runTransaction(async (transaction) => {
    const [userSnapshot, monsterSnapshot] = await transaction.getAll(firestore.doc(`users/${uid}`), monsterDocument);
    requireActiveAccount({ userSnapshot });
    if (!monsterSnapshot.exists) {
      throw new HttpsError("not-found", `図鑑にモンスター ${monsterId} はいません`);
    }
    const actionCardMoveIds = (monsterSnapshot.get("actionCardMoveIds") ?? []) as string[];
    if (!actionCardMoveIds.includes(moveId)) {
      return { actionCardMoveIds };
    }
    transaction.update(monsterDocument, { actionCardMoveIds: FieldValue.arrayRemove(moveId) });
    return { actionCardMoveIds: actionCardMoveIds.filter((actionCardMoveId) => actionCardMoveId !== moveId) };
  });
});
