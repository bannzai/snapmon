import { randomInt } from "node:crypto";

import { FieldPath, FieldValue, Timestamp, getFirestore, type DocumentSnapshot, type Firestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { ENFORCE_APP_CHECK } from "./app_check";
import { requireSignedInUid } from "./battle";
import { battleDayKey } from "./battle_rules";
import { ownersHiddenByReports, partyMonsterIDsOf, partyMonstersOf, requireActiveAccount } from "./pvp";
import { finishPvpBattle } from "./pvp_battle_finish";
import {
  MATCH_CANDIDATE_LIMIT,
  MATCH_TICKET_FRESH_SECONDS,
  MATCH_TICKET_SCAN_LIMIT,
  TURN_DEADLINE_GRACE_SECONDS,
  TURN_SECONDS,
  type PvpBattleDocument,
  type PvpMatchTicketDocument,
  type PvpTrainer,
  type PvpTurnDocument,
  isMatchableHostTicket,
  isRulesVersion,
  outcomeAfterReport,
  parsePvpAction,
  pvpTurnDocumentID,
  timeoutOutcome,
} from "./pvp_battle_rules";
import { blockDocumentID, displayNameOf, isDocumentID, profileIconOf, publicMonster } from "./pvp_rules";

// 人との対戦の組み合わせ (joinPvpMatch・leavePvpMatch) と、対戦の同期 (submitPvpAction・claimPvpTimeout・reportPvpResult) の Functions。
// 構造と書き込みの主体は .claude/rules/firestore.md、決めたことと根拠は documents/DIRECTION.md「決めたこと」の 2026-11-19 の人との対戦の行。
// レベルと 1 日の上限は、端末が対戦の後に呼ぶ recordBattle (battle.ts) が CPU との対戦と同じに扱う。

/** [now] に公開したターン (組み合わせた直後の最初のターンを含む) の行動の期限。 */
function turnDeadlineFrom({ now }: { now: Timestamp }): Timestamp {
  return Timestamp.fromMillis(now.toMillis() + (TURN_SECONDS + TURN_DEADLINE_GRACE_SECONDS) * 1000);
}

/**
 * 読んだ `pvpBattles/{battleID}` [battleSnapshot] を、対戦に出ている [uid] の対戦として返す。
 * 無い対戦は not-found、出ていない利用者には permission-denied を投げる (他人の対戦の行動・結果を書かせないため)。
 */
function requireParticipantBattle({ battleSnapshot, uid }: { battleSnapshot: DocumentSnapshot; uid: string }): PvpBattleDocument {
  if (!battleSnapshot.exists) {
    throw new HttpsError("not-found", "対戦が見つかりません");
  }
  const battle = battleSnapshot.data() as PvpBattleDocument;
  if (!battle.participantUIDs.includes(uid)) {
    throw new HttpsError("permission-denied", "この対戦に出ていません");
  }
  return battle;
}

/** 利用者が送った [battleID] が対戦の ID の形でなければ invalid-argument を投げ、形が合えば返す。 */
function requireBattleID({ battleID }: { battleID: unknown }): string {
  if (!isDocumentID(battleID)) {
    throw new HttpsError("invalid-argument", "battleID を渡してください");
  }
  return battleID;
}

/**
 * 今も相手を探している利用者 [waitingUIDs] のうち、[uid] とブロック・通報の関係があって組み合わせない利用者の uid を返す
 * ([uid] がブロックした / された相手、[uid] が通報したモンスターの持ち主、[uid] のモンスターを通報した利用者)。
 * 探している間 3 秒ごとに呼ばれるため、[uid] のブロック・通報の全件ではなく、今待っている相手との関係だけを読む
 * (待っている相手がいなければ何も読まない)。ブロックは 2 人の uid から決まる ID で読み、通報は相手の uid を `in` で絞る。
 * `in` に渡せる値は 30 個まで ( https://firebase.google.com/docs/firestore/query-data/queries の「in」) のため、
 * [waitingUIDs] は [MATCH_TICKET_SCAN_LIMIT] 個以下で渡す。通報の読み取りは firebase/firestore.indexes.json の reports の複合インデックスを使う。
 */
async function unmatchableWaitingUIDs({
  firestore,
  uid,
  waitingUIDs,
}: {
  firestore: Firestore;
  uid: string;
  waitingUIDs: string[];
}): Promise<Set<string>> {
  if (waitingUIDs.length === 0) {
    return new Set();
  }
  const [blocks, reportsByPlayer, reportsAgainstPlayer] = await Promise.all([
    firestore.getAll(
      ...waitingUIDs.flatMap((waitingUID) => [
        firestore.doc(`blocks/${blockDocumentID({ blockerUid: uid, blockedUid: waitingUID })}`),
        firestore.doc(`blocks/${blockDocumentID({ blockerUid: waitingUID, blockedUid: uid })}`),
      ]),
    ),
    firestore.collection("reports").where("reporterUid", "==", uid).where("monsterOwnerUid", "in", waitingUIDs).get(),
    firestore.collection("reports").where("monsterOwnerUid", "==", uid).where("reporterUid", "in", waitingUIDs).get(),
  ]);
  return new Set<string>([
    // ブロックの文書は、待っている相手ごとに「自分がブロックした」「相手にブロックされた」の順に 2 件ずつ読んでいる
    ...waitingUIDs.filter((_, index) => blocks[index * 2].exists || blocks[index * 2 + 1].exists),
    ...reportsByPlayer.docs.map((report) => report.get("monsterOwnerUid") as string),
    ...reportsAgainstPlayer.docs.map((report) => report.get("reporterUid") as string),
  ]);
}

/**
 * 人との対戦の相手を探す callable。探している間、端末が 3 秒ごとに同じ `searchID` で呼び直す。
 *
 * 受け取る data: `{ rulesVersion: string, searchID: string }` (rulesVersion は端末の対戦の計算の版、searchID は 1 回の探す操作ごとに端末が作る ID)。
 * 返す値: `{ battleID: string | null }`。組み合わされたら `pvpBattles/{battleID}` の ID、まだなら null。
 * 呼ぶたびに `pvpMatchTickets/{uid}` の時刻を更新し、今も探している他の利用者の札のうち、同じ版で長く待っている札と組み合わせる
 * (札の読み取りは firebase/firestore.indexes.json の pvpMatchTickets の複合インデックスを使う)。
 * 1 回の呼び出しが読む数は、待っている利用者の数ではなく上限 ([MATCH_TICKET_SCAN_LIMIT]・[MATCH_CANDIDATE_LIMIT]) で決まる。
 * 自分・ブロックした / された相手・自分が通報したモンスターの持ち主・自分のモンスターを通報した利用者・
 * [REPORT_HIDE_THRESHOLD] 人から通報されたモンスターの持ち主 (自分がそうである時は誰とも組み合わせない)・アカウントの削除の途中の利用者・
 * 手持ちが空の利用者とは組み合わせない。fetchOpponents の除外に、自分のモンスターを通報した利用者を足したもの
 * (人との対戦は 2 人が互いの手持ちを見るため、通報した側が先に待っていて、通報された側が後から来た時にも組み合わせない)。
 * 組み合わせた時は、2 人の手持ちの他人に見せてよい項目の写し・表示名・アイコン・乱数の種・対戦日を `pvpBattles/{battleID}` に、
 * 2 人の `users/{uid}/battles/{battleID}` に開始の記録 (`opponentKind: "pvp"`) を、同じトランザクションで書く。
 * 同じ searchID で組み合わされた後に呼び直しても、同じ battleID を返す (冪等)。
 * 自分の手持ちが空の時と、アカウントの削除の途中・削除済みの時は failed-precondition を投げる。
 */
export const joinPvpMatch = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { rulesVersion, searchID } = (request.data ?? {}) as { rulesVersion?: unknown; searchID?: unknown };
  if (!isRulesVersion(rulesVersion)) {
    throw new HttpsError("invalid-argument", "rulesVersion に対戦の計算の版を渡してください");
  }
  if (!isDocumentID(searchID)) {
    throw new HttpsError("invalid-argument", "searchID を渡してください");
  }
  const firestore = getFirestore();
  const now = Timestamp.now();
  const freshSince = Timestamp.fromMillis(now.toMillis() - MATCH_TICKET_FRESH_SECONDS * 1000);
  // 読む数の上限の前に、組み合わせられない札 (組み合わせ済み・別の版) を Firestore の側で外す
  // (上限の数だけそれらが先に並ぶと、組める相手が待っていても読めないため)
  const waitingUIDs = (
    await firestore
      .collection("pvpMatchTickets")
      .where("battleID", "==", null)
      .where("rulesVersion", "==", rulesVersion)
      .where("heartbeatAt", ">=", freshSince)
      .orderBy("heartbeatAt")
      .limit(MATCH_TICKET_SCAN_LIMIT)
      .get()
  ).docs
    .filter((ticket) => ticket.id !== uid)
    .sort((left, right) => (left.get("createdAt") as Timestamp).toMillis() - (right.get("createdAt") as Timestamp).toMillis())
    .map((ticket) => ticket.id);
  // 通報で隠れている利用者は探している間ずっと候補に残るため、手持ちまで読む候補の数 (MATCH_CANDIDATE_LIMIT) に絞る前に外す
  // (絞った後に外すと、隠れている利用者がその数だけ先に待っているだけで、後ろの組める相手に届かなくなる)
  const [unmatchableUIDs, hiddenOwnerUIDs] = await Promise.all([
    unmatchableWaitingUIDs({ firestore, uid, waitingUIDs }),
    ownersHiddenByReports({ firestore, ownerUids: [uid, ...waitingUIDs] }),
  ]);
  // 自分が通報で隠れている時は札の時刻だけを更新し、誰とも組み合わせない (隠れていることを本人に知らせない)
  const candidateUIDs = hiddenOwnerUIDs.has(uid)
    ? []
    : waitingUIDs
        .filter((waitingUID) => !unmatchableUIDs.has(waitingUID) && !hiddenOwnerUIDs.has(waitingUID))
        .slice(0, MATCH_CANDIDATE_LIMIT);
  const memberUIDs = [uid, ...candidateUIDs];
  const [memberUsers, memberParties] = await Promise.all([
    firestore.getAll(...memberUIDs.map((memberUID) => firestore.doc(`users/${memberUID}`))),
    firestore.getAll(...memberUIDs.map((memberUID) => firestore.doc(`users/${memberUID}/party/current`))),
  ]);
  const partyMonstersByUID = await partyMonstersOf({
    firestore,
    partyMonsterIDsByUid: new Map(memberUIDs.map((memberUID, index) => [memberUID, partyMonsterIDsOf(memberParties[index].data())])),
  });
  const trainerOf = (memberUID: string): PvpTrainer => {
    const memberUser = memberUsers[memberUIDs.indexOf(memberUID)];
    return {
      uid: memberUID,
      displayName: displayNameOf({ uid: memberUID, storedDisplayName: memberUser.get("displayName") }),
      iconPath: profileIconOf({ storedIconPath: memberUser.get("iconPath") }),
      monsters: partyMonstersByUID.get(memberUID)!.map(publicMonster),
    };
  };
  // 長く待っている順に、アカウントの削除の途中でなく手持ちのある最初の候補と組み合わせる
  const hostUID = candidateUIDs.find((candidateUID) => {
    const candidateUser = memberUsers[memberUIDs.indexOf(candidateUID)];
    return (
      candidateUser.exists &&
      candidateUser.get("accountDeletionStartedAt") === undefined &&
      partyMonstersByUID.get(candidateUID)!.length > 0
    );
  });
  const ticketDocument = firestore.doc(`pvpMatchTickets/${uid}`);
  const battleDocument = firestore.collection("pvpBattles").doc();
  return firestore.runTransaction(async (transaction): Promise<{ battleID: string | null }> => {
    // 相手のブロックの 2 件 (どちらかがもう片方をブロックした記録) もトランザクションの中で読み直す。候補を読んだ後に片方がブロックした時、
    // blockUser はまだ無い対戦を終えられないため、ここで組み合わせを止める (先に済んだブロックは組み合わせを止め、後のブロックは対戦を終える)
    const [userSnapshot, ticketSnapshot, ...hostSnapshots] = await transaction.getAll(
      firestore.doc(`users/${uid}`),
      ticketDocument,
      ...(hostUID === undefined
        ? []
        : [
            firestore.doc(`users/${hostUID}`),
            firestore.doc(`pvpMatchTickets/${hostUID}`),
            firestore.doc(`blocks/${blockDocumentID({ blockerUid: uid, blockedUid: hostUID })}`),
            firestore.doc(`blocks/${blockDocumentID({ blockerUid: hostUID, blockedUid: uid })}`),
          ]),
    );
    requireActiveAccount({ userSnapshot });
    const isSameSearch = ticketSnapshot.get("searchID") === searchID;
    const matchedBattleID: unknown = ticketSnapshot.get("battleID");
    if (isSameSearch && typeof matchedBattleID === "string") {
      return { battleID: matchedBattleID };
    }
    // 組み合わせ済みの確認の後に確かめる。対戦は組み合わせた時点の手持ちの写しで進むため、組み合わされた後に手持ちを空にした利用者の
    // 呼び直しにも対戦の ID を返す (先に断ると、本人は対戦に入れず、相手は行動の期限まで待たされる)
    if (partyMonstersByUID.get(uid)!.length === 0) {
      throw new HttpsError("failed-precondition", "手持ちを入れてから相手を探してください");
    }
    const ticket: PvpMatchTicketDocument = {
      rulesVersion,
      searchID,
      createdAt: isSameSearch ? (ticketSnapshot.get("createdAt") as Timestamp) : now,
      heartbeatAt: now,
      battleID: null,
    };
    const [hostUser, hostTicket, ...blockSnapshots] = hostSnapshots;
    // 候補を読んだ後に、相手が組み合わせられなくなった (札が替わった・削除を始めた・どちらかがブロックした) 時は、札だけを更新して次の呼び出しで探し直す
    if (
      hostUID === undefined ||
      !hostUser.exists ||
      hostUser.get("accountDeletionStartedAt") !== undefined ||
      blockSnapshots.some((blockSnapshot) => blockSnapshot.exists) ||
      !isMatchableHostTicket({ hostTicket: hostTicket.data() as PvpMatchTicketDocument | undefined, rulesVersion, freshSince })
    ) {
      transaction.set(ticketDocument, ticket);
      return { battleID: null };
    }
    const host = trainerOf(hostUID);
    const guest = trainerOf(uid);
    transaction.create(battleDocument, {
      host,
      guest,
      participantUIDs: [hostUID, uid],
      // 端末の乱数 (lib/domain/random/deterministic_random.dart の xorshift32) の状態は 32 ビットで、0 は別の値に置き換えられるため、
      // 置き換えの起きない 1 以上の 32 ビットの整数にする
      randomSeed: randomInt(1, 2 ** 32),
      battleDate: battleDayKey({ now: now.toDate() }),
      turnNumber: 0,
      turnSeconds: TURN_SECONDS,
      turnDeadline: turnDeadlineFrom({ now }),
      status: "active",
      winnerUID: null,
      finishReason: null,
      reportedWinnerUIDs: {},
      createdAt: now,
    } satisfies PvpBattleDocument);
    transaction.set(ticketDocument, { ...ticket, battleID: battleDocument.id });
    transaction.update(firestore.doc(`pvpMatchTickets/${hostUID}`), { battleID: battleDocument.id });
    for (const trainer of [host, guest]) {
      transaction.create(firestore.doc(`users/${trainer.uid}/battles/${battleDocument.id}`), {
        status: "started",
        partyMonsterIDs: trainer.monsters.map((monster) => monster.definition.id),
        opponentKind: "pvp",
        startedAt: FieldValue.serverTimestamp(),
      });
    }
    return { battleID: battleDocument.id };
  });
});

/**
 * 人との対戦の相手を探すのをやめる callable。
 *
 * 受け取る data: `{ searchID: string }` (joinPvpMatch に渡した ID)。
 * 返す値: `{ battleID: string | null }`。やめる前に組み合わされていたらその対戦の ID (相手は既に対戦に入っているため、端末はその対戦を始める)、
 * そうでなければ null で、`pvpMatchTickets/{uid}` を消す。札が無い時と、別の探す操作の札の時は何もせず null を返す (冪等)。
 */
export const leavePvpMatch = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { searchID } = (request.data ?? {}) as { searchID?: unknown };
  if (!isDocumentID(searchID)) {
    throw new HttpsError("invalid-argument", "searchID を渡してください");
  }
  const firestore = getFirestore();
  const ticketDocument = firestore.doc(`pvpMatchTickets/${uid}`);
  return firestore.runTransaction(async (transaction): Promise<{ battleID: string | null }> => {
    const ticketSnapshot = await transaction.get(ticketDocument);
    if (ticketSnapshot.get("searchID") !== searchID) {
      return { battleID: null };
    }
    const matchedBattleID: unknown = ticketSnapshot.get("battleID");
    if (typeof matchedBattleID === "string") {
      return { battleID: matchedBattleID };
    }
    transaction.delete(ticketDocument);
    return { battleID: null };
  });
});

/**
 * 人との対戦で、今のターンの自分の行動を出す callable。
 *
 * 受け取る data: `{ battleID: string, turnNumber: number, action: PvpAction }` (turnNumber は今のターンの 0 始まりの番号)。
 * 返す値: `{ submitted: true }`。行動を `pvpBattles/{battleID}/turns/{uid}_{turnNumber}` に置き (相手は、自分の行動を出すまで読めない)、
 * 相手も同じターンの行動を出していれば、次のターンに進めて期限を決める。
 * 出した行動は変えられず、同じターンの出し直しと公開済みのターンの再送は何もしない (冪等)。
 * 終わった対戦には failed-precondition、期限を過ぎたターンには deadline-exceeded、まだ来ていないターンの番号には invalid-argument を投げる。
 * 行動の形だけを確かめ、選べる行動かは確かめない (端末の計算が 2 台で同じに判定し、選べない行動を出した側の負けにする)。
 */
export const submitPvpAction = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const {
    battleID: requestedBattleID,
    turnNumber,
    action,
  } = (request.data ?? {}) as { battleID?: unknown; turnNumber?: unknown; action?: unknown };
  const battleID = requireBattleID({ battleID: requestedBattleID });
  if (typeof turnNumber !== "number" || !Number.isInteger(turnNumber) || turnNumber < 0) {
    throw new HttpsError("invalid-argument", "turnNumber に 0 以上の整数を渡してください");
  }
  const parsedAction = parsePvpAction(action);
  if (parsedAction === undefined) {
    throw new HttpsError("invalid-argument", "action に行動を渡してください");
  }
  const firestore = getFirestore();
  const battleDocument = firestore.doc(`pvpBattles/${battleID}`);
  await firestore.runTransaction(async (transaction) => {
    const battle = requireParticipantBattle({ battleSnapshot: await transaction.get(battleDocument), uid });
    if (turnNumber < battle.turnNumber) {
      return;
    }
    if (battle.status !== "active") {
      throw new HttpsError("failed-precondition", "対戦は終わっています");
    }
    if (turnNumber > battle.turnNumber) {
      throw new HttpsError("invalid-argument", "まだ始まっていないターンです");
    }
    const now = Timestamp.now();
    if (now.toMillis() > battle.turnDeadline.toMillis()) {
      throw new HttpsError("deadline-exceeded", "行動を選ぶ時間を過ぎました");
    }
    const turnDocument = firestore.doc(`pvpBattles/${battleID}/turns/${pvpTurnDocumentID({ uid, turnNumber })}`);
    const [turnSnapshot, opponentTurnSnapshot] = await transaction.getAll(
      turnDocument,
      firestore.doc(
        `pvpBattles/${battleID}/turns/${pvpTurnDocumentID({
          uid: battle.participantUIDs.find((participantUID) => participantUID !== uid)!,
          turnNumber,
        })}`,
      ),
    );
    if (turnSnapshot.exists) {
      return;
    }
    transaction.create(turnDocument, { action: parsedAction } satisfies PvpTurnDocument);
    if (!opponentTurnSnapshot.exists) {
      return;
    }
    transaction.update(battleDocument, { turnNumber: turnNumber + 1, turnDeadline: turnDeadlineFrom({ now }) });
  });
  return { submitted: true };
});

/**
 * 人との対戦で、行動の期限を過ぎたターンを時間切れとして終える callable。相手を待っている端末と、期限まで選ばなかった端末が呼ぶ。
 *
 * 受け取る data: `{ battleID: string }`。
 * 返す値: `{ status: "active" | "finished" | "void" }` (呼んだ後の対戦の状態)。
 * 期限はサーバーの時計で判定し、過ぎていなければ何もせず `active` を返す (端末の時計が進んでいても早く終わらせない)。
 * 過ぎていれば、今のターンの行動を出したのが片方だけならその側の勝ち、どちらも出していなければ勝敗を付けずに終える (pvp_battle_rules.ts の timeoutOutcome)。
 * 終わった対戦に呼んでも何もせず、その状態を返す (冪等)。
 */
export const claimPvpTimeout = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const battleID = requireBattleID({ battleID: ((request.data ?? {}) as { battleID?: unknown }).battleID });
  const firestore = getFirestore();
  return firestore.runTransaction(async (transaction): Promise<{ status: PvpBattleDocument["status"] }> => {
    const battle = requireParticipantBattle({ battleSnapshot: await transaction.get(firestore.doc(`pvpBattles/${battleID}`)), uid });
    if (battle.status !== "active" || Timestamp.now().toMillis() <= battle.turnDeadline.toMillis()) {
      return { status: battle.status };
    }
    // 過去のターンの行動も残っているため、今のターンの行動だけを読む
    const turnSnapshots = await transaction.getAll(
      ...battle.participantUIDs.map((participantUID) =>
        firestore.doc(`pvpBattles/${battleID}/turns/${pvpTurnDocumentID({ uid: participantUID, turnNumber: battle.turnNumber })}`),
      ),
    );
    const outcome = timeoutOutcome({
      submittedUIDs: battle.participantUIDs.filter((_, index) => turnSnapshots[index].exists),
    });
    await finishPvpBattle({ transaction, firestore, battleID, battle, outcome });
    return { status: outcome.status };
  });
});

/**
 * 人との対戦で、自分の端末の計算が出した勝者を報告する callable。端末は決着の後、recordBattle (レベルの記録) の前に呼ぶ。
 *
 * 受け取る data: `{ battleID: string, winnerUID: string | null }` (winnerUID は 2 人のどちらかの uid。2 人が出した行動では決着していない、という報告は null)。
 * 返す値: `{ status: "active" | "finished" | "void" }` (呼んだ後の対戦の状態)。
 * 進行中の対戦は最初の報告の勝者で終え、2 人の `users/{uid}/battles/{battleID}` に勝敗を書く。報告で終わった対戦に、食い違う報告
 * (別の勝者・決着していない) が届いたら、勝敗を付けない終わりに変えて書いた勝敗を消す (pvp_battle_rules.ts の outcomeAfterReport)。
 * 報告は 1 人 1 回で、出し直しは何も変えない (冪等)。期限切れ・ブロックで終わった対戦は報告で変わらない。
 * 計算がサーバーに無いため、改造した端末は負けた対戦を勝敗なしにできるが、相手の報告と食い違う勝ちは記録に残らない。
 */
export const reportPvpResult = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { battleID: requestedBattleID, winnerUID } = (request.data ?? {}) as { battleID?: unknown; winnerUID?: unknown };
  const battleID = requireBattleID({ battleID: requestedBattleID });
  const firestore = getFirestore();
  const battleDocument = firestore.doc(`pvpBattles/${battleID}`);
  return firestore.runTransaction(async (transaction): Promise<{ status: PvpBattleDocument["status"] }> => {
    const battle = requireParticipantBattle({ battleSnapshot: await transaction.get(battleDocument), uid });
    if (winnerUID !== null && !battle.participantUIDs.includes(winnerUID as string)) {
      throw new HttpsError("invalid-argument", "winnerUID に対戦に出ている利用者の uid か null を渡してください");
    }
    const reportedWinnerUID = winnerUID as string | null;
    if (uid in battle.reportedWinnerUIDs) {
      return { status: battle.status };
    }
    const outcome = outcomeAfterReport({ battle, reportedWinnerUID });
    // 進行中の対戦への「決着していない」は、変えるものが無いため報告として残さない (後で出す本当の勝者の報告を塞がないため)
    if (battle.status === "active" && outcome === undefined) {
      return { status: battle.status };
    }
    if (outcome !== undefined) {
      await finishPvpBattle({ transaction, firestore, battleID, battle, outcome });
    }
    transaction.update(battleDocument, new FieldPath("reportedWinnerUIDs", uid), reportedWinnerUID);
    return { status: outcome?.status ?? battle.status };
  });
});
