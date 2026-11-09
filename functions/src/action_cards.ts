// Action Card の買い切り・覚えさせる・忘れさせる callable と、技のランクの定期計算。
// 構造と書き込みの主体は .claude/rules/firestore.md、規則は action_card_rules.ts と documents/game-rules.md「Action Card」。

import { FieldValue, getFirestore, type Firestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onSchedule } from "firebase-functions/v2/scheduler";

import {
  MOVE_RANKS,
  MOVE_USAGE_WINDOW_DAYS,
  type MoveRank,
  actionCardCreditsOf,
  computeMoveRanks,
  creditRankToRedeem,
  fallbackMoveRank,
  previousDayKeys,
} from "./action_card_rules";
import { ENFORCE_APP_CHECK } from "./app_check";
import { requireSignedInUid } from "./battle";
import { fetchLatestMaster, learnableMoves } from "./generation/master";
import { requireActiveAccount } from "./pvp";
import { isDocumentId } from "./pvp_rules";

/** 技のランクの表 (`moveRanks/current`)。updateMoveRanks が毎日書き、購入の画面と redeemActionCard が読む。 */
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

/** 買い切った技 (`users/{uid}/actionCards/{moveId}`)。持っている間、本人のどのモンスターにも何回でも覚えさせられる。 */
export interface ActionCardDocument {
  /** 技の識別子 (文書 ID と同じ)。 */
  moveId: string;
  /** 買った時点の技のランク。後でランクが変わってもこの値は変えない。 */
  rank: MoveRank;
  /** 買った時刻。 */
  redeemedAt: Timestamp;
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
 * Action Card のクレジットを 1 枚使って技を買い切る callable。
 *
 * 受け取る data: `{ moveId: string, creditRank?: 1 | 2 | 3 }` (最新の版の master の買える技の ID と、端末が確かめる画面で出した使うカードのランク)。
 * 返す値: `{ moveId, rank, creditRank, actionCardCredits: { rank1, rank2, rank3 } }` (技のランク、使ったカードのランク、使った後の残高)。
 * 技のランクは `moveRanks/current` から引き、表に無い (表が無い・表を作った後に master に足された) 技は段階で決める予備のランク
 * (action_card_rules.ts の fallbackMoveRank) にする。カードは技のランク以上で一番安いランクのものを使う。
 * 既に持っている技は already-exists、使えるカードが無い時は failed-precondition で、どちらも `details` に残高を返す。
 * `creditRank` を渡した時は、使うカードのランクがそれと違えば (確かめている間に技のランクか残高が変わった) カードを使わずに failed-precondition で断り、
 * `details` に残高と今使うランク `creditRank` を返す (端末が確かめ直すため。#277)。`creditRank` を渡さない呼び出しは確かめずに使う
 * (`creditRank` を足す前のアプリの呼び出しを壊さないため)。ランクでない値は invalid-argument。
 * 置き換えられた技・master に無い技は not-found。同じ技を買い直せないため、同じ呼び出しを繰り返してもクレジットは 1 回しか減らない。
 */
export const redeemActionCard = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { moveId, creditRank: confirmedCreditRank } = (request.data ?? {}) as { moveId?: unknown; creditRank?: unknown };
  if (!isDocumentId(moveId)) {
    throw new HttpsError("invalid-argument", "moveId を渡してください");
  }
  if (confirmedCreditRank !== undefined && !MOVE_RANKS.includes(confirmedCreditRank as MoveRank)) {
    throw new HttpsError("invalid-argument", "creditRank は 1・2・3 のどれかを渡してください");
  }
  const firestore = getFirestore();
  // 投入済みの版は書き換えないため、トランザクションの外で読んでよい
  const move = learnableMoves((await fetchLatestMaster(firestore)).moves).find((candidate) => candidate.id === moveId);
  if (move === undefined) {
    throw new HttpsError("not-found", `買える技に ${moveId} はありません`);
  }
  const userDocument = firestore.doc(`users/${uid}`);
  const actionCardDocument = firestore.doc(`users/${uid}/actionCards/${moveId}`);
  return firestore.runTransaction(async (transaction) => {
    const [userSnapshot, moveRanksSnapshot, actionCardSnapshot] = await transaction.getAll(userDocument, firestore.doc("moveRanks/current"), actionCardDocument);
    requireActiveAccount({ userSnapshot });
    const actionCardCredits = actionCardCreditsOf(userSnapshot.get("actionCardCredits"));
    if (actionCardSnapshot.exists) {
      throw new HttpsError("already-exists", `${moveId} は買い切り済みです`, { actionCardCredits });
    }
    const rankByMoveId = (moveRanksSnapshot.get("rankByMoveId") ?? {}) as Record<string, MoveRank>;
    const rank = Object.hasOwn(rankByMoveId, moveId) ? rankByMoveId[moveId] : fallbackMoveRank(move);
    const creditRank = creditRankToRedeem({ moveRank: rank, actionCardCredits });
    if (creditRank === undefined) {
      throw new HttpsError("failed-precondition", `ランク ${rank} 以上の Action Card がありません`, { actionCardCredits });
    }
    if (confirmedCreditRank !== undefined && confirmedCreditRank !== creditRank) {
      throw new HttpsError("failed-precondition", `使うカードがランク ${confirmedCreditRank} からランク ${creditRank} に変わりました`, {
        actionCardCredits,
        creditRank,
      });
    }
    transaction.create(actionCardDocument, { moveId, rank, redeemedAt: Timestamp.now() } satisfies ActionCardDocument);
    transaction.update(userDocument, { [`actionCardCredits.rank${creditRank}`]: FieldValue.increment(-1) });
    return {
      moveId,
      rank,
      creditRank,
      actionCardCredits: { ...actionCardCredits, [`rank${creditRank}`]: actionCardCredits[`rank${creditRank}`] - 1 },
    };
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
    const [userSnapshot, monsterSnapshot, actionCardSnapshot] = await transaction.getAll(
      firestore.doc(`users/${uid}`),
      monsterDocument,
      firestore.doc(`users/${uid}/actionCards/${moveId}`),
    );
    requireActiveAccount({ userSnapshot });
    if (!monsterSnapshot.exists) {
      throw new HttpsError("not-found", `図鑑にモンスター ${monsterId} はいません`);
    }
    if (!actionCardSnapshot.exists) {
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
