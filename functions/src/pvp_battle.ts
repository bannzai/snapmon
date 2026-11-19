import { randomInt } from "node:crypto";

import { FieldPath, FieldValue, Timestamp, getFirestore, type DocumentSnapshot } from "firebase-admin/firestore";
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
  type PvpAction,
  type PvpBattleDocument,
  type PvpMatchTicketDocument,
  type PvpTrainer,
  type PvpTurn,
  isMatchableHostTicket,
  isRulesVersion,
  outcomeAfterReport,
  parsePvpAction,
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
  if (!battle.participantUids.includes(uid)) {
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
 * 人との対戦の相手を探す callable。探している間、端末が 3 秒ごとに同じ `searchID` で呼び直す。
 *
 * 受け取る data: `{ rulesVersion: string, searchID: string }` (rulesVersion は端末の対戦の計算の版、searchID は 1 回の探す操作ごとに端末が作る ID)。
 * 返す値: `{ battleID: string | null }`。組み合わされたら `pvpBattles/{battleID}` の ID、まだなら null。
 * 呼ぶたびに `pvpMatchTickets/{uid}` の時刻を更新し、今も探している他の利用者の札のうち、同じ版で長く待っている札と組み合わせる
 * (札の読み取りは firebase/firestore.indexes.json の pvpMatchTickets の複合インデックスを使う)。
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
  const [blockedByPlayer, blockingPlayer, reportedByPlayer, reportingPlayer, waitingTickets] = await Promise.all([
    firestore.collection("blocks").where("blockerUid", "==", uid).get(),
    firestore.collection("blocks").where("blockedUid", "==", uid).get(),
    firestore.collection("reports").where("reporterUid", "==", uid).get(),
    firestore.collection("reports").where("monsterOwnerUid", "==", uid).get(),
    // 読む数の上限の前に、組み合わせられない札 (組み合わせ済み・別の版) を Firestore の側で外す
    // (上限の数だけそれらが先に並ぶと、組める相手が待っていても読めないため)
    firestore
      .collection("pvpMatchTickets")
      .where("battleID", "==", null)
      .where("rulesVersion", "==", rulesVersion)
      .where("heartbeatAt", ">=", freshSince)
      .orderBy("heartbeatAt")
      .limit(MATCH_TICKET_SCAN_LIMIT)
      .get(),
  ]);
  const excludedUids = new Set<unknown>([
    uid,
    ...blockedByPlayer.docs.map((snapshot) => snapshot.get("blockedUid")),
    ...blockingPlayer.docs.map((snapshot) => snapshot.get("blockerUid")),
    ...reportedByPlayer.docs.map((snapshot) => snapshot.get("monsterOwnerUid")),
    ...reportingPlayer.docs.map((snapshot) => snapshot.get("reporterUid")),
  ]);
  const candidateUids = waitingTickets.docs
    .filter((ticket) => !excludedUids.has(ticket.id))
    .sort((left, right) => (left.get("createdAt") as Timestamp).toMillis() - (right.get("createdAt") as Timestamp).toMillis())
    .slice(0, MATCH_CANDIDATE_LIMIT)
    .map((ticket) => ticket.id);
  const memberUids = [uid, ...candidateUids];
  const [hiddenOwnerUids, memberUsers, memberParties] = await Promise.all([
    ownersHiddenByReports({ firestore, ownerUids: memberUids }),
    firestore.getAll(...memberUids.map((memberUid) => firestore.doc(`users/${memberUid}`))),
    firestore.getAll(...memberUids.map((memberUid) => firestore.doc(`users/${memberUid}/party/current`))),
  ]);
  const partyMonstersByUid = await partyMonstersOf({
    firestore,
    partyMonsterIDsByUid: new Map(memberUids.map((memberUid, index) => [memberUid, partyMonsterIDsOf(memberParties[index].data())])),
  });
  if (partyMonstersByUid.get(uid)!.length === 0) {
    throw new HttpsError("failed-precondition", "手持ちを入れてから相手を探してください");
  }
  const trainerOf = (memberUid: string): PvpTrainer => {
    const memberUser = memberUsers[memberUids.indexOf(memberUid)];
    return {
      uid: memberUid,
      displayName: displayNameOf({ uid: memberUid, storedDisplayName: memberUser.get("displayName") }),
      iconPath: profileIconOf({ storedIconPath: memberUser.get("iconPath") }),
      monsters: partyMonstersByUid.get(memberUid)!.map(publicMonster),
    };
  };
  // 自分が通報で隠れている時は札の時刻だけを更新し、誰とも組み合わせない (隠れていることを本人に知らせない)
  const hostUid = hiddenOwnerUids.has(uid)
    ? undefined
    : candidateUids.find((candidateUid) => !hiddenOwnerUids.has(candidateUid) && partyMonstersByUid.get(candidateUid)!.length > 0);
  const ticketDocument = firestore.doc(`pvpMatchTickets/${uid}`);
  const battleDocument = firestore.collection("pvpBattles").doc();
  return firestore.runTransaction(async (transaction): Promise<{ battleID: string | null }> => {
    // 相手のブロックの 2 件 (どちらかがもう片方をブロックした記録) もトランザクションの中で読み直す。候補を読んだ後に片方がブロックした時、
    // blockUser はまだ無い対戦を終えられないため、ここで組み合わせを止める (先に済んだブロックは組み合わせを止め、後のブロックは対戦を終える)
    const [userSnapshot, ticketSnapshot, ...hostSnapshots] = await transaction.getAll(
      firestore.doc(`users/${uid}`),
      ticketDocument,
      ...(hostUid === undefined
        ? []
        : [
            firestore.doc(`users/${hostUid}`),
            firestore.doc(`pvpMatchTickets/${hostUid}`),
            firestore.doc(`blocks/${blockDocumentID({ blockerUid: uid, blockedUid: hostUid })}`),
            firestore.doc(`blocks/${blockDocumentID({ blockerUid: hostUid, blockedUid: uid })}`),
          ]),
    );
    requireActiveAccount({ userSnapshot });
    const isSameSearch = ticketSnapshot.get("searchID") === searchID;
    const matchedBattleID: unknown = ticketSnapshot.get("battleID");
    if (isSameSearch && typeof matchedBattleID === "string") {
      return { battleID: matchedBattleID };
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
      hostUid === undefined ||
      !hostUser.exists ||
      hostUser.get("accountDeletionStartedAt") !== undefined ||
      blockSnapshots.some((blockSnapshot) => blockSnapshot.exists) ||
      !isMatchableHostTicket({ hostTicket: hostTicket.data() as PvpMatchTicketDocument | undefined, rulesVersion, freshSince })
    ) {
      transaction.set(ticketDocument, ticket);
      return { battleID: null };
    }
    const host = trainerOf(hostUid);
    const guest = trainerOf(uid);
    transaction.create(battleDocument, {
      host,
      guest,
      participantUids: [hostUid, uid],
      // 端末の乱数 (lib/domain/random/deterministic_random.dart の xorshift32) の状態は 32 ビットで、0 は別の値に置き換えられるため、
      // 置き換えの起きない 1 以上の 32 ビットの整数にする
      randomSeed: randomInt(1, 2 ** 32),
      battleDate: battleDayKey({ now: now.toDate() }),
      turns: [],
      turnSeconds: TURN_SECONDS,
      turnDeadline: turnDeadlineFrom({ now }),
      status: "active",
      winnerUid: null,
      finishReason: null,
      reportedWinnerUids: {},
      createdAt: now,
    } satisfies PvpBattleDocument);
    transaction.set(ticketDocument, { ...ticket, battleID: battleDocument.id });
    transaction.update(firestore.doc(`pvpMatchTickets/${hostUid}`), { battleID: battleDocument.id });
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
 * 受け取る data: `{ battleID: string, round: number, action: PvpAction }` (round は公開済みのターンの数 = 今のターンの 0 始まりの番号)。
 * 返す値: `{ submitted: true }`。相手がまだ出していなければ `pvpBattles/{battleID}/pendingActions/{uid}` に置き (相手は読めない)、
 * 相手が出していれば 2 人の行動を `turns` に足して公開し、次のターンの期限を決める。
 * 出した行動は変えられず、同じターンの出し直しと公開済みのターンの再送は何もしない (冪等)。
 * 終わった対戦には failed-precondition、期限を過ぎたターンには deadline-exceeded、まだ来ていないターンの番号には invalid-argument を投げる。
 * 行動の形だけを確かめ、選べる行動かは確かめない (端末の計算が 2 台で同じに判定し、選べない行動を出した側の負けにする)。
 */
export const submitPvpAction = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { battleID: requestedBattleID, round, action } = (request.data ?? {}) as { battleID?: unknown; round?: unknown; action?: unknown };
  const battleID = requireBattleID({ battleID: requestedBattleID });
  if (typeof round !== "number" || !Number.isInteger(round) || round < 0) {
    throw new HttpsError("invalid-argument", "round に 0 以上の整数を渡してください");
  }
  const parsedAction = parsePvpAction(action);
  if (parsedAction === undefined) {
    throw new HttpsError("invalid-argument", "action に行動を渡してください");
  }
  const firestore = getFirestore();
  const battleDocument = firestore.doc(`pvpBattles/${battleID}`);
  await firestore.runTransaction(async (transaction) => {
    const battle = requireParticipantBattle({ battleSnapshot: await transaction.get(battleDocument), uid });
    if (round < battle.turns.length) {
      return;
    }
    if (battle.status !== "active") {
      throw new HttpsError("failed-precondition", "対戦は終わっています");
    }
    if (round > battle.turns.length) {
      throw new HttpsError("invalid-argument", "まだ始まっていないターンです");
    }
    const now = Timestamp.now();
    if (now.toMillis() > battle.turnDeadline.toMillis()) {
      throw new HttpsError("deadline-exceeded", "行動を選ぶ時間を過ぎました");
    }
    const opponentUid = battle.participantUids.find((participantUid) => participantUid !== uid)!;
    const pendingDocument = firestore.doc(`pvpBattles/${battleID}/pendingActions/${uid}`);
    const [pendingSnapshot, opponentPendingSnapshot] = await transaction.getAll(
      pendingDocument,
      firestore.doc(`pvpBattles/${battleID}/pendingActions/${opponentUid}`),
    );
    if (pendingSnapshot.exists) {
      return;
    }
    if (!opponentPendingSnapshot.exists) {
      transaction.create(pendingDocument, { action: parsedAction });
      return;
    }
    const opponentAction = opponentPendingSnapshot.get("action") as PvpAction;
    // 同じ行動のターンが続いても足せるよう、arrayUnion (同じ値を足さない) ではなく配列ごと書く
    transaction.update(battleDocument, {
      turns: [
        ...battle.turns,
        (battle.host.uid === uid
          ? { hostAction: parsedAction, guestAction: opponentAction }
          : { hostAction: opponentAction, guestAction: parsedAction }) satisfies PvpTurn,
      ],
      turnDeadline: turnDeadlineFrom({ now }),
    });
    transaction.delete(opponentPendingSnapshot.ref);
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
    const pendingSnapshots = await transaction.getAll(
      ...battle.participantUids.map((participantUid) => firestore.doc(`pvpBattles/${battleID}/pendingActions/${participantUid}`)),
    );
    const outcome = timeoutOutcome({
      submittedUids: pendingSnapshots.filter((snapshot) => snapshot.exists).map((snapshot) => snapshot.id),
    });
    await finishPvpBattle({ transaction, firestore, battleID, battle, outcome });
    return { status: outcome.status };
  });
});

/**
 * 人との対戦で、自分の端末の計算が出した勝者を報告する callable。端末は決着の後、recordBattle (レベルの記録) の前に呼ぶ。
 *
 * 受け取る data: `{ battleID: string, winnerUid: string | null }` (winnerUid は 2 人のどちらかの uid。公開されたターンでは決着していない、という報告は null)。
 * 返す値: `{ status: "active" | "finished" | "void" }` (呼んだ後の対戦の状態)。
 * 進行中の対戦は最初の報告の勝者で終え、2 人の `users/{uid}/battles/{battleID}` に勝敗を書く。報告で終わった対戦に、食い違う報告
 * (別の勝者・決着していない) が届いたら、勝敗を付けない終わりに変えて書いた勝敗を消す (pvp_battle_rules.ts の outcomeAfterReport)。
 * 報告は 1 人 1 回で、出し直しは何も変えない (冪等)。期限切れ・ブロックで終わった対戦は報告で変わらない。
 * 計算がサーバーに無いため、改造した端末は負けた対戦を勝敗なしにできるが、相手の報告と食い違う勝ちは記録に残らない。
 */
export const reportPvpResult = onCall({ enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { battleID: requestedBattleID, winnerUid } = (request.data ?? {}) as { battleID?: unknown; winnerUid?: unknown };
  const battleID = requireBattleID({ battleID: requestedBattleID });
  const firestore = getFirestore();
  const battleDocument = firestore.doc(`pvpBattles/${battleID}`);
  return firestore.runTransaction(async (transaction): Promise<{ status: PvpBattleDocument["status"] }> => {
    const battle = requireParticipantBattle({ battleSnapshot: await transaction.get(battleDocument), uid });
    if (winnerUid !== null && !battle.participantUids.includes(winnerUid as string)) {
      throw new HttpsError("invalid-argument", "winnerUid に対戦に出ている利用者の uid か null を渡してください");
    }
    const reportedWinnerUid = winnerUid as string | null;
    if (uid in battle.reportedWinnerUids) {
      return { status: battle.status };
    }
    const outcome = outcomeAfterReport({ battle, reportedWinnerUid });
    // 進行中の対戦への「決着していない」は、変えるものが無いため報告として残さない (後で出す本当の勝者の報告を塞がないため)
    if (battle.status === "active" && outcome === undefined) {
      return { status: battle.status };
    }
    if (outcome !== undefined) {
      await finishPvpBattle({ transaction, firestore, battleID, battle, outcome });
    }
    transaction.update(battleDocument, new FieldPath("reportedWinnerUids", uid), reportedWinnerUid);
    return { status: outcome?.status ?? battle.status };
  });
});
