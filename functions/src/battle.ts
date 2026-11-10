import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";

import { equippedMoveIDs } from "./action_card_rules";
import { ENFORCE_APP_CHECK } from "./app_check";
import {
  DAILY_BATTLE_LIMIT,
  battleDayKey,
  isMonsterIDList,
  isSubsetOfParty,
  levelAfterBattle,
} from "./battle_rules";

/** ログイン (匿名ログインを含む) の uid を返す。ログインしていなければ HttpsError を投げる。 */
export function requireSignedInUid({ request }: { request: CallableRequest }): string {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "匿名ログインの後に呼んでください");
  }
  return request.auth.uid;
}

/**
 * バトルの開始を記録し、結果の送信 (recordBattle) に使う `battleID` を発行する callable。
 *
 * 受け取る data: `{ partyMonsterIDs: string[] }` (自分の図鑑にあるモンスターの ID を重複なく 1〜3 件。バトルに連れて行く手持ち)。
 * 返す値: `{ battleID: string }`。`users/{uid}/battles/{battleID}` を未完了 (`status: "started"`) で作り、手持ちを保存する。
 * 冪等ではない: 呼ぶたびに別のバトルとして新しい battleID を作る (1 回の挑戦が 1 回の呼び出しに当たるため)。
 * 完了しなかったバトル (にげた等) はレベルにも 1 日の上限の数にも効かない。
 */
export const startBattle = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { partyMonsterIDs } = (request.data ?? {}) as { partyMonsterIDs?: unknown };
  if (!isMonsterIDList(partyMonsterIDs)) {
    throw new HttpsError("invalid-argument", "partyMonsterIDs にモンスターの ID を重複なく 1〜3 件渡してください");
  }
  const firestore = getFirestore();
  const battleDocument = firestore.collection(`users/${uid}/battles`).doc();
  // 確認と作成を 1 つのトランザクションにする。アカウントの削除 (account.ts) が始まった後と消し終えた後 (users/{uid} ごと消える) に
  // バトルの記録を作ると、消し終えた後に残るため。図鑑のモンスターがあるユーザーは、生成 (pipeline.ts の startGeneration) が
  // users/{uid} を作っているため、users/{uid} が無いことを消し終えた印として扱える
  await firestore.runTransaction(async (transaction) => {
    const [userSnapshot, ...monsterSnapshots] = await transaction.getAll(
      firestore.doc(`users/${uid}`),
      ...partyMonsterIDs.map((monsterID) => firestore.doc(`users/${uid}/monsters/${monsterID}`)),
    );
    if (!userSnapshot.exists || userSnapshot.get("accountDeletionStartedAt") !== undefined) {
      throw new HttpsError("failed-precondition", "アカウントの削除が進んでいるか、アカウントが見つかりません");
    }
    if (monsterSnapshots.some((snapshot) => !snapshot.exists)) {
      throw new HttpsError("not-found", "図鑑に無いモンスターが手持ちに入っています");
    }
    transaction.create(battleDocument, {
      status: "started",
      partyMonsterIDs,
      startedAt: FieldValue.serverTimestamp(),
    });
  });
  return { battleID: battleDocument.id };
});

/**
 * バトルの結果を記録し、戦闘に出た手持ちのレベルを 1 上げる callable。
 *
 * 受け取る data: `{ battleID: string, participantMonsterIDs: string[], winner: "player" | "opponent", turnCount: number }`。
 * participantMonsterIDs は場に出たことがある自分のモンスター (startBattle で記録した手持ちの部分集合)。
 * 勝敗とターン数は端末の計算をそのまま記録し、検証しない (レベルは勝敗に関係なく +1 のため。ADR 0001 の DB の行)。
 * 返す値: `{ levels: { [monsterID]: number } }` (上がった後のレベル)。
 * トランザクションでバトルの完了状態を確かめ、未完了の時だけ、1 日 (日本時間) の上限 [DAILY_BATTLE_LIMIT] 戦を検証して
 * レベル・経験の加算、1 日の数、完了の記録を同時に書く。コミットの後に、参加したモンスターの技の枠の技の使用回数
 * (`moveUsageDailyCounts/{日本時間の日付}`) をトランザクションの外で足す (書けなくてもレベルの記録は成功として返し、その回は数えない)。
 * 完了済みの battleID の再送は加算も使用回数の加算もせず、記録済みの levels を返す (冪等)。
 */
export const recordBattle = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { battleID, participantMonsterIDs, winner, turnCount } = (request.data ?? {}) as {
    battleID?: unknown;
    participantMonsterIDs?: unknown;
    winner?: unknown;
    turnCount?: unknown;
  };
  if (typeof battleID !== "string" || battleID === "" || battleID.includes("/")) {
    throw new HttpsError("invalid-argument", "battleID を渡してください");
  }
  if (!isMonsterIDList(participantMonsterIDs)) {
    throw new HttpsError("invalid-argument", "participantMonsterIDs にモンスターの ID を重複なく 1〜3 件渡してください");
  }
  if (winner !== "player" && winner !== "opponent") {
    throw new HttpsError("invalid-argument", "winner は player か opponent を渡してください");
  }
  if (typeof turnCount !== "number" || !Number.isInteger(turnCount) || turnCount < 1) {
    throw new HttpsError("invalid-argument", "turnCount に 1 以上の整数を渡してください");
  }
  const firestore = getFirestore();
  const userDocument = firestore.doc(`users/${uid}`);
  const battleDocument = firestore.doc(`users/${uid}/battles/${battleID}`);
  const { levels, moveUsage } = await firestore.runTransaction(
    async (transaction): Promise<{ levels: Record<string, number>; moveUsage?: { dayKey: string; counts: Record<string, number> } }> => {
    const battleSnapshot = await transaction.get(battleDocument);
    if (!battleSnapshot.exists) {
      throw new HttpsError("not-found", `バトル ${battleID} は始まっていません`);
    }
    if (battleSnapshot.get("status") === "completed") {
      return { levels: battleSnapshot.get("levels") as Record<string, number> };
    }
    if (
      !isSubsetOfParty({
        participantMonsterIDs,
        partyMonsterIDs: battleSnapshot.get("partyMonsterIDs") as string[],
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
    const monsterDocuments = participantMonsterIDs.map((monsterID) =>
      firestore.doc(`users/${uid}/monsters/${monsterID}`),
    );
    const monsterSnapshots = await transaction.getAll(...monsterDocuments);
    const nextLevels: Record<string, number> = {};
    // 技のランク (action_cards.ts の updateMoveRanks) に使う、参加したモンスターのバトルの時点の技の枠の技の数。
    // クライアントから技を受け取らず図鑑から決める (改ざんでランクを動かさせないため)。同じ技を持つモンスターが 2 体いれば 2 回数える
    const moveUsageCounts: Record<string, number> = {};
    for (const [index, monsterSnapshot] of monsterSnapshots.entries()) {
      const level = monsterSnapshot.get("level");
      if (!monsterSnapshot.exists || typeof level !== "number") {
        throw new HttpsError("not-found", `図鑑に無いモンスター ${participantMonsterIDs[index]} が含まれています`);
      }
      nextLevels[participantMonsterIDs[index]] = levelAfterBattle({ level });
      const learnset: unknown = monsterSnapshot.get("definition.learnset");
      // 生成が作るモンスターは必ず learnset を持つ。持たない文書は数えずに進め、集計のためにレベルの記録を失敗させない
      if (Array.isArray(learnset)) {
        for (const moveID of equippedMoveIDs({ learnset, level, actionCardMoveIDs: monsterSnapshot.get("actionCardMoveIDs") ?? [] })) {
          moveUsageCounts[moveID] = (moveUsageCounts[moveID] ?? 0) + 1;
        }
      }
    }
    for (const [index, monsterDocument] of monsterDocuments.entries()) {
      transaction.update(monsterDocument, {
        level: nextLevels[participantMonsterIDs[index]],
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
      participantMonsterIDs,
      winner,
      turnCount,
      levels: nextLevels,
      completedAt: FieldValue.serverTimestamp(),
    });
    return { levels: nextLevels, moveUsage: { dayKey: today, counts: moveUsageCounts } };
  });
  if (moveUsage !== undefined && Object.keys(moveUsage.counts).length > 0) {
    // 使用回数の文書は全ユーザーのバトルの記録が書くため、レベルの記録のトランザクションの外で書く。1 文書への書き込みの頻度には
    // 上限があり ("you can't update a single document at an unlimited rate." https://firebase.google.com/docs/firestore/solutions/counters )、
    // 同じトランザクションに入れると、ぶつかった時にレベルの記録まで失敗するため。書けなくてもレベルの記録は済んでいるため、失敗させずにログだけ残す。
    // 完了済みの battleID の再送は上で数えずに返すため、ここに来るのは記録した 1 回だけ (書き損じた分はランクの集計から抜けるが、二重には数えない)
    try {
      // ドット区切りの update は文書が無いと失敗し、技の ID の `.` を区切りと読むため、入れ子の値を merge で書く
      await firestore
        .doc(`moveUsageDailyCounts/${moveUsage.dayKey}`)
        .set({ counts: Object.fromEntries(Object.entries(moveUsage.counts).map(([moveID, count]) => [moveID, FieldValue.increment(count)])) }, { merge: true });
    } catch (error) {
      logger.error("技の使用回数を書けませんでした", { error, battleID });
    }
  }
  return { levels };
});
