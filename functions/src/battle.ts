import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";

import {
  DAILY_BATTLE_LIMIT,
  battleDayKey,
  isMonsterIdList,
  isSubsetOfParty,
  levelAfterBattle,
} from "./battle_rules";

/**
 * 年齢の確認を通ったログイン (confirmAge が付けるカスタムクレーム ageVerified) の uid を返す。無ければ HttpsError を投げる。
 * バトル結果の Functions はクレームを必須にする (documents/adr/0001-tech-stack.md の対象年齢の行)。
 */
function requireAgeVerifiedUid({ request }: { request: CallableRequest }): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "匿名ログインの後に呼んでください");
  }
  if (request.auth.token.ageVerified !== true) {
    throw new HttpsError("permission-denied", "年齢の確認の後に呼んでください");
  }
  return request.auth.uid;
}

/**
 * バトルの開始を記録し、結果の送信 (recordBattle) に使う `battleId` を発行する callable。
 *
 * 受け取る data: `{ partyMonsterIds: string[] }` (自分の図鑑にあるモンスターの ID を重複なく 1〜3 件。バトルに連れて行く手持ち)。
 * 返す値: `{ battleId: string }`。`users/{uid}/battles/{battleId}` を未完了 (`status: "started"`) で作り、手持ちを保存する。
 * 冪等ではない: 呼ぶたびに別のバトルとして新しい battleId を作る (1 回の挑戦が 1 回の呼び出しに当たるため)。
 * 完了しなかったバトル (にげた等) はレベルにも 1 日の上限の数にも効かない。
 */
export const startBattle = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAgeVerifiedUid({ request });
  const { partyMonsterIds } = (request.data ?? {}) as { partyMonsterIds?: unknown };
  if (!isMonsterIdList(partyMonsterIds)) {
    throw new HttpsError("invalid-argument", "partyMonsterIds にモンスターの ID を重複なく 1〜3 件渡してください");
  }
  const firestore = getFirestore();
  const battleDocument = firestore.collection(`users/${uid}/battles`).doc();
  // 確認と作成を 1 つのトランザクションにする。アカウントの削除 (account.ts) が始まった後と消し終えた後 (confirmAge が付けた
  // ageAccepted ごと users/{uid} が消える) にバトルの記録を作ると、消し終えた後に残るため
  await firestore.runTransaction(async (transaction) => {
    const [userSnapshot, ...monsterSnapshots] = await transaction.getAll(
      firestore.doc(`users/${uid}`),
      ...partyMonsterIds.map((monsterId) => firestore.doc(`users/${uid}/monsters/${monsterId}`)),
    );
    if (userSnapshot.get("accountDeletionStartedAt") !== undefined || userSnapshot.get("ageAccepted") !== true) {
      throw new HttpsError("failed-precondition", "アカウントの削除が進んでいるか、アカウントが見つかりません");
    }
    if (monsterSnapshots.some((snapshot) => !snapshot.exists)) {
      throw new HttpsError("not-found", "図鑑に無いモンスターが手持ちに入っています");
    }
    transaction.create(battleDocument, {
      status: "started",
      partyMonsterIds,
      startedAt: FieldValue.serverTimestamp(),
    });
  });
  return { battleId: battleDocument.id };
});

/**
 * バトルの結果を記録し、戦闘に出た手持ちのレベルを 1 上げる callable。
 *
 * 受け取る data: `{ battleId: string, participantMonsterIds: string[], winner: "player" | "opponent", turnCount: number }`。
 * participantMonsterIds は場に出たことがある自分のモンスター (startBattle で記録した手持ちの部分集合)。
 * 勝敗とターン数は端末の計算をそのまま記録し、検証しない (レベルは勝敗に関係なく +1 のため。ADR 0001 の DB の行)。
 * 返す値: `{ levels: { [monsterId]: number } }` (上がった後のレベル)。
 * トランザクションでバトルの完了状態を確かめ、未完了の時だけ、1 日 (日本時間) の上限 [DAILY_BATTLE_LIMIT] 戦を検証して
 * レベル・経験の加算、1 日の数、完了の記録を同時に書く。完了済みの battleId の再送は加算せず、記録済みの levels を返す (冪等)。
 */
export const recordBattle = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAgeVerifiedUid({ request });
  const { battleId, participantMonsterIds, winner, turnCount } = (request.data ?? {}) as {
    battleId?: unknown;
    participantMonsterIds?: unknown;
    winner?: unknown;
    turnCount?: unknown;
  };
  if (typeof battleId !== "string" || battleId === "" || battleId.includes("/")) {
    throw new HttpsError("invalid-argument", "battleId を渡してください");
  }
  if (!isMonsterIdList(participantMonsterIds)) {
    throw new HttpsError("invalid-argument", "participantMonsterIds にモンスターの ID を重複なく 1〜3 件渡してください");
  }
  if (winner !== "player" && winner !== "opponent") {
    throw new HttpsError("invalid-argument", "winner は player か opponent を渡してください");
  }
  if (typeof turnCount !== "number" || !Number.isInteger(turnCount) || turnCount < 1) {
    throw new HttpsError("invalid-argument", "turnCount に 1 以上の整数を渡してください");
  }
  const firestore = getFirestore();
  const userDocument = firestore.doc(`users/${uid}`);
  const battleDocument = firestore.doc(`users/${uid}/battles/${battleId}`);
  const levels = await firestore.runTransaction(async (transaction) => {
    const battleSnapshot = await transaction.get(battleDocument);
    if (!battleSnapshot.exists) {
      throw new HttpsError("not-found", `バトル ${battleId} は始まっていません`);
    }
    if (battleSnapshot.get("status") === "completed") {
      return battleSnapshot.get("levels") as Record<string, number>;
    }
    if (
      !isSubsetOfParty({
        participantMonsterIds,
        partyMonsterIds: battleSnapshot.get("partyMonsterIds") as string[],
      })
    ) {
      throw new HttpsError("invalid-argument", "バトルの開始時の手持ちに無いモンスターが含まれています");
    }
    const userSnapshot = await transaction.get(userDocument);
    const today = battleDayKey({ now: new Date() });
    const battleCountOfToday =
      userSnapshot.get("dailyBattleDate") === today ? (userSnapshot.get("dailyBattleCount") as number) : 0;
    if (battleCountOfToday >= DAILY_BATTLE_LIMIT) {
      throw new HttpsError("resource-exhausted", `1 日に記録できるバトルは ${DAILY_BATTLE_LIMIT} 戦までです`);
    }
    const monsterDocuments = participantMonsterIds.map((monsterId) =>
      firestore.doc(`users/${uid}/monsters/${monsterId}`),
    );
    const monsterSnapshots = await transaction.getAll(...monsterDocuments);
    const nextLevels: Record<string, number> = {};
    for (const [index, monsterSnapshot] of monsterSnapshots.entries()) {
      const level = monsterSnapshot.get("level");
      if (!monsterSnapshot.exists || typeof level !== "number") {
        throw new HttpsError("not-found", `図鑑に無いモンスター ${participantMonsterIds[index]} が含まれています`);
      }
      nextLevels[participantMonsterIds[index]] = levelAfterBattle({ level });
    }
    for (const [index, monsterDocument] of monsterDocuments.entries()) {
      transaction.update(monsterDocument, {
        level: nextLevels[participantMonsterIds[index]],
        // 経験は場に出て決着まで戦ったバトルの回数の累計 (documents/game-rules.md「レベルアップ」)
        experience: FieldValue.increment(1),
      });
    }
    transaction.set(
      userDocument,
      { dailyBattleDate: today, dailyBattleCount: battleCountOfToday + 1 },
      { merge: true },
    );
    transaction.update(battleDocument, {
      status: "completed",
      participantMonsterIds,
      winner,
      turnCount,
      levels: nextLevels,
      completedAt: FieldValue.serverTimestamp(),
    });
    return nextLevels;
  });
  return { levels };
});
