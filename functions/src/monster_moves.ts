// 図鑑のモンスターの、対戦の前に選ぶ技 (技の枠) を保存する callable (#309)。図鑑のモンスターはクライアントから書けないため、
// 持っている技から選んでいるかを確かめてから書く (.claude/rules/firestore.md)。枠の決め方は action_card_rules.ts の equippedMoveIDs と
// documents/game-rules.md「技」。

import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { availableMoveIDs, selectedMoveIDsRejectionReason } from "./action_card_rules";
import { ENFORCE_APP_CHECK } from "./app_check";
import { requireSignedInUid } from "./battle";
import type { MonsterDocument } from "./generation/records";
import { requireActiveAccount } from "./pvp";
import { isDocumentID } from "./pvp_rules";

/**
 * 本人のモンスターの対戦の前に選ぶ技を保存する callable。
 *
 * 受け取る data: `{ monsterID: string, moveIDs: string[] }` (moveIDs は枠の順)。返す値: `{ selectedMoveIDs: string[] }` (保存した技)。
 * `users/{uid}/monsters/{monsterID}.selectedMoveIDs` を moveIDs で置き換える (同じ値で何度呼んでも同じ。冪等)。
 * 持っていない技・重複・数が 1 つ以上 4 つ以下でない時は invalid-argument、図鑑に無いモンスター (他人のモンスターを含む) は not-found。
 */
export const selectMonsterMoves = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { monsterID, moveIDs } = (request.data ?? {}) as { monsterID?: unknown; moveIDs?: unknown };
  if (!isDocumentID(monsterID) || !Array.isArray(moveIDs) || !moveIDs.every(isDocumentID)) {
    throw new HttpsError("invalid-argument", "monsterID と moveIDs を渡してください");
  }
  const firestore = getFirestore();
  const monsterDocument = firestore.doc(`users/${uid}/monsters/${monsterID}`);
  return firestore.runTransaction(async (transaction) => {
    const [userSnapshot, monsterSnapshot] = await transaction.getAll(firestore.doc(`users/${uid}`), monsterDocument);
    requireActiveAccount({ userSnapshot });
    if (!monsterSnapshot.exists) {
      throw new HttpsError("not-found", `図鑑にモンスター ${monsterID} はいません`);
    }
    const monster = monsterSnapshot.data() as MonsterDocument;
    const rejectionReason = selectedMoveIDsRejectionReason({
      moveIDs,
      availableMoveIDs: availableMoveIDs({
        learnset: monster.definition.learnset,
        level: monster.level,
        actionCardMoveIDs: monster.actionCardMoveIDs ?? [],
      }),
    });
    if (rejectionReason !== null) {
      throw new HttpsError("invalid-argument", rejectionReason);
    }
    transaction.update(monsterDocument, { selectedMoveIDs: moveIDs } satisfies Pick<MonsterDocument, "selectedMoveIDs">);
    return { selectedMoveIDs: moveIDs };
  });
});
