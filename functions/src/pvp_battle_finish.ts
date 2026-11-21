import { FieldValue, type Firestore, type Transaction } from "firebase-admin/firestore";

import { type PvpBattleDocument, type PvpBattleOutcome, pvpParticipantUIDs } from "./pvp_battle_rules";

/**
 * トランザクション [transaction] の中で、人との対戦 [battleID] ([battle]) を [outcome] で終える。
 *
 * `pvpBattles/{battleID}` に終わり方を書き、2 人の `users/{uid}/battles/{battleID}` の `winner` を
 * 勝者がいれば本人から見た勝敗 ("player" / "opponent") にし、勝敗を付けない終わりなら消す (戦績はこの値を数える。lib/firebase/pvp.dart)。
 * アカウントの削除で記録が消えた利用者には書かない (消えた `users/{uid}` の配下を作り直さないため)。
 * この関数は読み取りを含むため、呼ぶ側はこの前に自分の読み取りを済ませ、書き込みを後に置く。
 */
export async function finishPvpBattle({
  transaction,
  firestore,
  battleID,
  battle,
  outcome,
}: {
  transaction: Transaction;
  firestore: Firestore;
  battleID: string;
  battle: PvpBattleDocument;
  outcome: PvpBattleOutcome;
}): Promise<void> {
  const participantUIDs = pvpParticipantUIDs({ battle });
  const recordSnapshots = await transaction.getAll(...participantUIDs.map((uid) => firestore.doc(`users/${uid}/battles/${battleID}`)));
  transaction.update(firestore.doc(`pvpBattles/${battleID}`), { ...outcome, turnDeadline: null });
  for (const [index, recordSnapshot] of recordSnapshots.entries()) {
    if (recordSnapshot.exists) {
      transaction.update(recordSnapshot.ref, {
        winner: outcome.winnerUID === null ? FieldValue.delete() : outcome.winnerUID === participantUIDs[index] ? "player" : "opponent",
        ...(outcome.winnerUID === null ? { levels: FieldValue.delete(), turnCount: FieldValue.delete() } : {}),
      });
    }
  }
}
