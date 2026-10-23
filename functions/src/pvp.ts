import { FieldValue, getFirestore, type DocumentData, type DocumentSnapshot, type Firestore } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { requireAgeVerifiedUid } from "./battle";
import type { MonsterDocument } from "./generation/records";
import {
  OPPONENT_CANDIDATE_SCAN_LIMIT,
  REPORT_HIDE_THRESHOLD,
  type ReportDocument,
  averageLevel,
  blockDocumentId,
  displayNameOf,
  isDocumentId,
  isReportReason,
  publicMonster,
  reportDocumentId,
  reportNotificationText,
  selectOpponents,
  validateDisplayName,
} from "./pvp_rules";
import { slackBotToken } from "./secrets";
import { NOTIFICATION_CHANNEL, postSlackMessage, type SendSlackMessage } from "./slack";

// 非同期 PvP の相手の取得と、ストアの UGC 要件 (通報・ブロック) と表示名の Functions。
// 構造と書き込みの主体は .claude/rules/firestore.md、他人に見せる項目は documents/adr/0001-tech-stack.md の画像ストレージの行。

/**
 * 書き込みと同じトランザクションで読んだ本人の `users/{uid}` [userSnapshot] が、削除の途中でも削除済みでもないことを確かめる
 * (battle.ts の startBattle と同じ条件)。アカウントの削除 (account.ts) の後も別の端末の ID トークンは期限まで通るため、
 * 確かめずに書くと、削除が消し終えた後に本人の通報・ブロック・表示名が残る。満たさない時は failed-precondition を投げる。
 */
function requireActiveAccount({ userSnapshot }: { userSnapshot: DocumentSnapshot }): void {
  if (userSnapshot.get("accountDeletionStartedAt") !== undefined || userSnapshot.get("ageAccepted") !== true) {
    throw new HttpsError("failed-precondition", "アカウントの削除が進んでいるか、アカウントが見つかりません");
  }
}

/** `users/{uid}/party/current` の monsterIds のうち、文字列の ID だけを返す (無ければ空)。 */
function partyMonsterIdsOf(partyData: DocumentData | undefined): string[] {
  const monsterIds: unknown = partyData?.monsterIds;
  return Array.isArray(monsterIds) ? monsterIds.filter(isDocumentId) : [];
}

/**
 * [partyMonsterIdsByUid] (uid ごとの手持ちの ID) の図鑑のモンスターを 1 回の getAll で読み、uid ごとに図鑑にあるものだけを返す
 * (手持ちの ID は消えたモンスターを指すことがあるため、無いものは落とす)。
 */
async function partyMonstersOf({
  firestore,
  partyMonsterIdsByUid,
}: {
  firestore: Firestore;
  partyMonsterIdsByUid: Map<string, string[]>;
}): Promise<Map<string, MonsterDocument[]>> {
  const references = [...partyMonsterIdsByUid].flatMap(([uid, monsterIds]) =>
    monsterIds.map((monsterId) => ({ uid, document: firestore.doc(`users/${uid}/monsters/${monsterId}`) })),
  );
  const snapshots = references.length === 0 ? [] : await firestore.getAll(...references.map(({ document }) => document));
  const monstersByUid = new Map<string, MonsterDocument[]>([...partyMonsterIdsByUid.keys()].map((uid) => [uid, []]));
  for (const [index, snapshot] of snapshots.entries()) {
    if (snapshot.exists) {
      monstersByUid.get(references[index].uid)!.push(snapshot.data() as MonsterDocument);
    }
  }
  return monstersByUid;
}

/**
 * 非同期 PvP の相手の候補を返す callable。
 *
 * 受け取る data: なし。
 * 返す値: `{ opponents: [{ opponentUid, displayName, monsters: PublicMonster[] }] }` (最大 3 人。手持ちの平均レベルが自分に近い順)。
 * 候補は手持ちを最近変えたユーザー [OPPONENT_CANDIDATE_SCAN_LIMIT] 人から選び、自分・ブロックした / された相手・
 * 自分が通報したモンスターの持ち主・[REPORT_HIDE_THRESHOLD] 人から通報されたモンスターの持ち主を除く。
 * モンスターは他人に見せてよい項目だけを返し (pvp_rules.ts の publicMonster)、元の写真の参照は返さない。
 * opponentUid は通報・ブロックの宛先に要るため返す。
 * 自分の手持ちが空の時は failed-precondition を投げる (平均レベルを決められないため)。読み取りだけで冪等。
 */
export const fetchOpponents = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAgeVerifiedUid({ request });
  const firestore = getFirestore();
  const [playerParty, blockedByPlayer, blockingPlayer, reportedByPlayer, hiddenByReports, candidateParties] = await Promise.all([
    firestore.doc(`users/${uid}/party/current`).get(),
    firestore.collection("blocks").where("blockerUid", "==", uid).get(),
    firestore.collection("blocks").where("blockedUid", "==", uid).get(),
    firestore.collection("reports").where("reporterUid", "==", uid).get(),
    firestore.collection("reportedMonsters").where("reporterCount", ">=", REPORT_HIDE_THRESHOLD).get(),
    firestore.collectionGroup("party").orderBy("updatedAt", "desc").limit(OPPONENT_CANDIDATE_SCAN_LIMIT).get(),
  ]);
  const excludedUids = new Set<unknown>([
    uid,
    ...blockedByPlayer.docs.map((snapshot) => snapshot.get("blockedUid")),
    ...blockingPlayer.docs.map((snapshot) => snapshot.get("blockerUid")),
    ...reportedByPlayer.docs.map((snapshot) => snapshot.get("monsterOwnerUid")),
    ...hiddenByReports.docs.map((snapshot) => snapshot.get("monsterOwnerUid")),
  ]);
  const partyMonsterIdsByUid = new Map<string, string[]>([[uid, partyMonsterIdsOf(playerParty.data())]]);
  for (const party of candidateParties.docs) {
    // コレクショングループは users/{uid}/party/current 以外の party という名前のコレクションも拾うため、パスで絞る
    const owner = party.ref.parent.parent;
    if (party.id !== "current" || owner === null || owner.parent.id !== "users" || excludedUids.has(owner.id)) {
      continue;
    }
    partyMonsterIdsByUid.set(owner.id, partyMonsterIdsOf(party.data()));
  }
  const partyMonstersByUid = await partyMonstersOf({ firestore, partyMonsterIdsByUid });
  const playerPartyMonsters = partyMonstersByUid.get(uid)!;
  if (playerPartyMonsters.length === 0) {
    throw new HttpsError("failed-precondition", "手持ちを入れてから相手を探してください");
  }
  const opponentUids = selectOpponents({
    candidates: [...partyMonstersByUid]
      .filter(([candidateUid]) => candidateUid !== uid)
      .map(([candidateUid, monsters]) => ({ uid: candidateUid, partyLevels: monsters.map((monster) => monster.level) })),
    playerAverageLevel: averageLevel(playerPartyMonsters.map((monster) => monster.level)),
  });
  const opponentUsers =
    opponentUids.length === 0 ? [] : await firestore.getAll(...opponentUids.map((opponentUid) => firestore.doc(`users/${opponentUid}`)));
  return {
    opponents: opponentUids.map((opponentUid, index) => ({
      opponentUid,
      displayName: displayNameOf({ uid: opponentUid, storedDisplayName: opponentUsers[index].get("displayName") }),
      monsters: partyMonstersByUid.get(opponentUid)!.map(publicMonster),
    })),
  };
});

/**
 * 他のユーザーのモンスターを通報する callable (ストアの UGC 要件の通報)。
 *
 * 受け取る data: `{ monsterOwnerUid: string, monsterId: string, reason: ReportReason }`。
 * 返す値: `{ reported: true }`。`reports/{reporterUid}_{monsterId}` を作り、同じトランザクションで `reportedMonsters/{monsterId}` の
 * 通報したユーザー数を 1 増やす。作られた通報は notifyReport が #snapmon-notification に知らせる。
 * 同じユーザーが同じモンスターを通報し直しても、通報もユーザー数も増やさない (冪等)。
 * 自分のモンスターは通報できない (invalid-argument)。モンスターが無い時は not-found。
 */
export const reportMonster = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAgeVerifiedUid({ request });
  const { monsterOwnerUid, monsterId, reason } = (request.data ?? {}) as {
    monsterOwnerUid?: unknown;
    monsterId?: unknown;
    reason?: unknown;
  };
  if (!isDocumentId(monsterOwnerUid) || !isDocumentId(monsterId)) {
    throw new HttpsError("invalid-argument", "monsterOwnerUid と monsterId を渡してください");
  }
  if (!isReportReason(reason)) {
    throw new HttpsError("invalid-argument", "reason に通報の理由を渡してください");
  }
  if (monsterOwnerUid === uid) {
    throw new HttpsError("invalid-argument", "自分のモンスターは通報できません");
  }
  const firestore = getFirestore();
  const monsterDocument = firestore.doc(`users/${monsterOwnerUid}/monsters/${monsterId}`);
  const reportDocument = firestore.doc(`reports/${reportDocumentId({ reporterUid: uid, monsterId })}`);
  await firestore.runTransaction(async (transaction) => {
    const [userSnapshot, monsterSnapshot, reportSnapshot] = await transaction.getAll(
      firestore.doc(`users/${uid}`),
      monsterDocument,
      reportDocument,
    );
    requireActiveAccount({ userSnapshot });
    if (!monsterSnapshot.exists) {
      throw new HttpsError("not-found", "通報するモンスターが見つかりません");
    }
    if (reportSnapshot.exists) {
      return;
    }
    const monster = monsterSnapshot.data() as MonsterDocument;
    const report: ReportDocument = {
      reporterUid: uid,
      monsterOwnerUid,
      monsterId,
      monsterName: monster.definition.name,
      monsterArtPath: monster.artPath,
      reason,
    };
    transaction.create(reportDocument, { ...report, createdAt: FieldValue.serverTimestamp() });
    transaction.set(
      firestore.doc(`reportedMonsters/${monsterId}`),
      { monsterOwnerUid, reporterCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() },
      { merge: true },
    );
  });
  return { reported: true };
});

/**
 * 他のユーザーをブロックする callable (ストアの UGC 要件のブロック)。
 *
 * 受け取る data: `{ blockedUid: string }`。
 * 返す値: `{ blocked: true }`。`blocks/{blockerUid}_{blockedUid}` を作る。ブロックした相手とブロックされた相手は、互いの
 * fetchOpponents の候補に出ない。同じ相手をブロックし直しても 1 件のまま (冪等)。自分はブロックできない (invalid-argument)。
 */
export const blockUser = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAgeVerifiedUid({ request });
  const { blockedUid } = (request.data ?? {}) as { blockedUid?: unknown };
  if (!isDocumentId(blockedUid)) {
    throw new HttpsError("invalid-argument", "blockedUid を渡してください");
  }
  if (blockedUid === uid) {
    throw new HttpsError("invalid-argument", "自分はブロックできません");
  }
  const firestore = getFirestore();
  const blockDocument = firestore.doc(`blocks/${blockDocumentId({ blockerUid: uid, blockedUid })}`);
  await firestore.runTransaction(async (transaction) => {
    const [userSnapshot, blockSnapshot] = await transaction.getAll(firestore.doc(`users/${uid}`), blockDocument);
    requireActiveAccount({ userSnapshot });
    if (!blockSnapshot.exists) {
      transaction.create(blockDocument, { blockerUid: uid, blockedUid, createdAt: FieldValue.serverTimestamp() });
    }
  });
  return { blocked: true };
});

/**
 * 自分の表示名を返す callable。
 *
 * 受け取る data: なし。返す値: `{ displayName: string }` (設定していなければ「トレーナー」+ uid から決まる 4 桁)。
 * 既定の名前はサーバーだけが決め、クライアントは返った値を出す。読み取りだけで冪等。
 */
export const getDisplayName = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAgeVerifiedUid({ request });
  const user = await getFirestore().doc(`users/${uid}`).get();
  return { displayName: displayNameOf({ uid, storedDisplayName: user.get("displayName") }) };
});

/**
 * 自分の表示名を変える callable。
 *
 * 受け取る data: `{ displayName: string }`。返す値: `{ displayName: string }` (保存した、前後の空白を除いた名前)。
 * 空・長すぎる・制御文字・禁止語 (pvp_rules.ts の validateDisplayName) は invalid-argument で、利用者に出す文言を返す。
 * `users/{uid}` の displayName はクライアントから書けない (Rules) ため、検査を通った名前だけが他のユーザーに見える。同じ名前で呼び直しても同じ (冪等)。
 */
export const setDisplayName = onCall({ enforceAppCheck: true }, async (request) => {
  const uid = requireAgeVerifiedUid({ request });
  const validation = validateDisplayName(((request.data ?? {}) as { displayName?: unknown }).displayName);
  if ("error" in validation) {
    throw new HttpsError("invalid-argument", validation.error);
  }
  const firestore = getFirestore();
  const userDocument = firestore.doc(`users/${uid}`);
  await firestore.runTransaction(async (transaction) => {
    requireActiveAccount({ userSnapshot: await transaction.get(userDocument) });
    transaction.set(userDocument, { displayName: validation.displayName }, { merge: true });
  });
  return { displayName: validation.displayName };
});

/** 作られた通報 [report] ([reportId]) を [sendMessage] で知らせる。 */
export async function handleReportCreated({
  reportId,
  report,
  sendMessage,
}: {
  reportId: string;
  report: ReportDocument;
  sendMessage: SendSlackMessage;
}): Promise<void> {
  await sendMessage({ text: reportNotificationText({ reportId, report }) });
}

/**
 * 通報 (`reports/{reportId}`) が作られたら #snapmon-notification に知らせる (ストアの UGC 要件の「懸念へのすみやかな対応」のため)。
 * 送れなかった時は例外をログに残す (再試行はしない。通報そのものは Firestore に残っている)。
 */
export const notifyReport = onDocumentCreated({ document: "reports/{reportId}", secrets: [slackBotToken] }, async (event) => {
  if (!event.data) {
    return;
  }
  await handleReportCreated({
    reportId: event.params.reportId,
    report: event.data.data() as ReportDocument,
    sendMessage: ({ text }) =>
      postSlackMessage({ token: slackBotToken.value(), channel: NOTIFICATION_CHANNEL, text, fetchFunction: fetch }),
  });
});
