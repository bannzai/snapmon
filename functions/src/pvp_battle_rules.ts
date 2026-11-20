// 人との対戦 (同じ時に相手を探している 2 人を組み合わせ、互いに自分の端末で行動を選ぶ) の、Firestore に依存しない規則。
// 決めた値と根拠は documents/DIRECTION.md「決めたこと」の 2026-11-19 の人との対戦の行。
// バトルの計算はサーバーに無く、2 人の端末が同じ手持ちの写し・乱数の種・行動の列から同じ結果を出す (lib/features/opponent/pvp_battle_session.dart)。

import type { Timestamp } from "firebase-admin/firestore";

import type { PublicMonster } from "./pvp_rules";

/**
 * 待ちの札を「今も相手を探している」と扱う秒数。
 * 端末は探している間 3 秒ごとに joinPvpMatch を呼び直す (lib/features/opponent/pvp_match_search.dart)。1 回の呼び出しが遅れても
 * 途切れず、アプリを閉じた利用者の札が早く相手に選ばれなくなる長さにした (閉じた利用者と組むと、相手は時間切れまで待つことになる)。
 */
export const MATCH_TICKET_FRESH_SECONDS = 10;

/**
 * 1 回の joinPvpMatch が読む、同じ版でまだ組み合わされていない、今も探している待ちの札の数。
 * 探している間 3 秒ごとに読むため、読み取りの回数を抑えつつ、ブロック・通報で組めない札が混ざっても組める相手に届く数にした。
 */
export const MATCH_TICKET_SCAN_LIMIT = 20;

/**
 * 1 回の joinPvpMatch が手持ちまで読む候補の数 (長く待っている順)。
 * 候補 1 人につき利用者・手持ち・図鑑のモンスター最大 3 体を読むため、先頭の候補が削除の途中・手持ちが空でも次に進める最小限の数にした。
 */
export const MATCH_CANDIDATE_LIMIT = 5;

/**
 * 1 ターンの行動を選ぶ時間 (秒)。端末はこの秒数を残り時間として出す。
 * 前のターンの演出 (長いターンで 20 秒ほど) が流れた後に、初めて対戦する利用者が技の説明を読んで選べる長さを残しつつ、
 * 相手がアプリを閉じた時に待つ時間が 1 分ほどで終わる長さにした。
 */
export const TURN_SECONDS = 60;

/**
 * 行動の期限に足す猶予 (秒)。端末は対戦のドキュメントを受け取った時から [TURN_SECONDS] を数える。
 * 先に待っていた側は 3 秒ごとの joinPvpMatch で組み合わせを知るため最初のターンを最大 3 秒遅れて数え始め、そこに受け取りと送信の遅れが足される。
 * 残り時間のある間に選んだ行動が期限切れにならないよう、その合計より長くした。
 */
export const TURN_DEADLINE_GRACE_SECONDS = 10;

/** 対戦の計算の版 (端末がバトルの計算の版と master の版から作る文字列。lib/features/opponent/pvp_match_search.dart) の最大の長さ。札に保存する文字列を小さく保つ。 */
const RULES_VERSION_MAX_LENGTH = 64;

/** [value] が対戦の計算の版 (空でない [RULES_VERSION_MAX_LENGTH] 文字以下の文字列) か。同じ版の利用者だけを組み合わせる。 */
export function isRulesVersion(value: unknown): value is string {
  return typeof value === "string" && value !== "" && value.length <= RULES_VERSION_MAX_LENGTH;
}

/** 技の ID の最大の長さ。生成が作る技の ID (`definitions/` の ID) より十分長く、行動のドキュメントを小さく保つ。 */
const MOVE_ID_MAX_LENGTH = 200;

/**
 * 対戦で 1 ターンに選ぶ行動。端末のバトルの計算の BattleAction (lib/domain/battle/battle_state.dart) と同じ 3 種類で、
 * 選べる行動か (PP・覚えている技・交代できる相手) は端末の計算が 2 台で同じに判定する。
 */
export type PvpAction =
  /** 技を使う。 */
  | { kind: "move"; moveID: string }
  /** わるあがき (使える技が無い時)。 */
  | { kind: "struggle" }
  /** 手持ちの [memberIndex] 番目 (0 始まり) と交代する。 */
  | { kind: "switch"; memberIndex: number };

/** 利用者が送った [value] が [PvpAction] の形なら、その項目だけを写して返す (余分な項目を保存しない)。形が違えば undefined。 */
export function parsePvpAction(value: unknown): PvpAction | undefined {
  if (typeof value !== "object" || value === null) {
    return undefined;
  }
  const { kind, moveID, memberIndex } = value as { kind?: unknown; moveID?: unknown; memberIndex?: unknown };
  if (kind === "move" && typeof moveID === "string" && moveID !== "" && moveID.length <= MOVE_ID_MAX_LENGTH) {
    return { kind, moveID };
  }
  if (kind === "struggle") {
    return { kind };
  }
  if (kind === "switch" && typeof memberIndex === "number" && Number.isInteger(memberIndex) && memberIndex >= 0 && memberIndex <= 2) {
    return { kind, memberIndex };
  }
  return undefined;
}

/**
 * `pvpBattles/{battleID}/turns/{uid}_{turnNumber}` に保存する、利用者が 1 ターンに出した行動 1 件。対戦の行動の置き場はここだけで、
 * 誰がどのターンに出したかは ID が持つ ([pvpTurnDocumentID])。書くのは Functions だけ。
 * 利用者は、自分が同じターンの行動を出した後にだけ、そのターンの行動を 1 件ずつ読める (相手の行動を見てから選べないようにするため。
 * 条件は firebase/firestore.rules が、読む利用者の同じターンの行動があるかで確かめる)。
 */
export interface PvpTurnDocument {
  /** 出した行動。出した後は変えられない。 */
  action: PvpAction;
}

/**
 * 利用者 [uid] が対戦のターン [turnNumber] (0 始まりの番号) に出した行動 ([PvpTurnDocument]) の ID を返す。
 * 同じターンの出し直しは同じ ID になる。
 */
export function pvpTurnDocumentID({ uid, turnNumber }: { uid: string; turnNumber: number }): string {
  return `${uid}_${turnNumber}`;
}

/** 対戦に出る 1 人。相手の端末が読むため、他人に見せてよい項目だけを持つ。 */
export interface PvpTrainer {
  /** uid。相手の通報・ブロックの宛先と、勝者の判定に使う。 */
  uid: string;
  /** 表示名 (pvp_rules.ts の displayNameOf)。 */
  displayName: string;
  /** 検査を通したアイコンの Storage のパス。登録していなければ null。 */
  iconPath: string | null;
  /** 組み合わせた時点の手持ちの写し (手持ちの順)。2 人の端末がこの写しから同じ計算をする。 */
  monsters: PublicMonster[];
}

/** 対戦がどう終わったか。 */
export type PvpFinishReason =
  /** 端末の計算の決着を利用者が報告した。 */
  | "result"
  /** 行動の期限を過ぎた。 */
  | "timeout"
  /** 2 人の報告した勝者が食い違った。 */
  | "mismatch"
  /** 片方が相手をブロックした。 */
  | "blocked";

/** 対戦の終わり方。勝者がいる終わり ([winnerUID] が入る) と、勝敗を付けない終わり ([winnerUID] が null)。 */
export type PvpBattleOutcome =
  | { winnerUID: string; finishReason: Extract<PvpFinishReason, "result" | "timeout"> }
  | { winnerUID: null; finishReason: Extract<PvpFinishReason, "timeout" | "mismatch" | "blocked"> };

/** 人との対戦 1 戦の進み具合。進行中 ([finishReason] が null) か、どう終わったか。 */
export type PvpBattleProgress =
  /** 進行中。[turnDeadline] は今のターンの行動の期限で、過ぎると行動を受け付けず、時間切れとして終える。 */
  | { winnerUID: null; finishReason: null; turnDeadline: Timestamp }
  /** 終わった。終わった対戦に行動の期限は無い。 */
  | (PvpBattleOutcome & { turnDeadline: null });

/**
 * `pvpBattles/{battleID}` に保存する人との対戦 1 戦。2 人の利用者だけが読み、書くのは Functions だけ。
 * 進み具合の項目 (winnerUID・finishReason・turnDeadline) は [PvpBattleProgress] のどれかの組み合わせになる。
 */
export type PvpBattleDocument = PvpBattleProgress & {
  /**
   * 先に待っていた側。端末の計算では、同じ素早さの時の乱数と相打ちの扱いをこの側を基準に決める。
   * [host] と [guest] の uid は、読める利用者の判定 (Rules) と、アカウントの削除が本人の対戦を探すのにも使う。
   */
  host: PvpTrainer;
  /** 後から来た側。 */
  guest: PvpTrainer;
  /** バトルの乱数の種 (1 以上の 32 ビットの整数)。サーバーが決め、2 人の端末が同じ乱数の列を使う。 */
  randomSeed: number;
  /** 対戦日 (日本時間の `YYYY-MM-DD`)。対戦日で効果が変わる技を、2 人の端末の時計に関係なく同じに計算する。 */
  battleDate: string;
  /**
   * 今のターンの番号 (0 始まり)。2 人の行動がそろうたびに 1 増える (これより小さい番号のターンは、2 人とも行動を出している)。
   * 端末のバトルの計算の `BattleState.turnNumber` (片方の行動ごとに進む 1 始まりの番号) とは別の数で、
   * 端末は進め終えたターンを自分で数えてこの番号と比べる (lib/features/opponent/pvp_battle_session.dart)。
   * 行動を受け付けるターンと、期限切れの時に行動を読むターンを決めるのに使う (行動そのものは `turns` のサブコレクションにある)。
   */
  turnNumber: number;
  /** 1 ターンの行動を選ぶ時間 (秒)。端末が残り時間として出す。 */
  turnSeconds: number;
  /** 利用者ごとの、端末の計算が出した勝者の uid の報告 (決着していないという報告は null)。1 人 1 回で、後から変えられない。 */
  reportedWinnerUIDs: Record<string, string | null>;
  /** 組み合わせた時刻。 */
  createdAt: Timestamp;
};

/** `pvpMatchTickets/{uid}` に保存する、相手を探している利用者の待ちの札。クライアントは読み書きしない。 */
export interface PvpMatchTicketDocument {
  /** 対戦の計算の版。同じ版の札とだけ組み合わせる。 */
  rulesVersion: string;
  /** 端末が 1 回の「探す」ごとに作る ID。前の探す操作で組み合わされた対戦を、新しい探す操作の結果として返さないために使う。 */
  searchID: string;
  /** この探す操作を始めた時刻。長く待っている札から組み合わせる。 */
  createdAt: Timestamp;
  /** 最後に joinPvpMatch を呼んだ時刻。[MATCH_TICKET_FRESH_SECONDS] より古い札とは組み合わせない。 */
  heartbeatAt: Timestamp;
  /** 組み合わされた対戦の ID。まだ組み合わされていなければ null。 */
  battleID: string | null;
}

/** 対戦 [battle] に出ている 2 人の uid を、先に待っていた側・後から来た側の順で返す。 */
export function pvpParticipantUIDs({ battle }: { battle: Pick<PvpBattleDocument, "host" | "guest"> }): [string, string] {
  return [battle.host.uid, battle.guest.uid];
}

/**
 * トランザクションの中で読み直した、組み合わせる相手 (先に待っていた側) の札 [hostTicket] (無ければ undefined) が、
 * 今も対戦の計算の版 [rulesVersion] の相手として組み合わせられるか。
 * 候補を読んでからトランザクションまでの間に、相手が探すのをやめた (札が無い)・他の利用者と組み合わされた・別の版で探し直した・
 * 最後の呼び出しが [freshSince] より前のまま止まった時は false (呼ぶ側は自分の札だけを更新し、次の呼び出しで探し直す)。
 */
export function isMatchableHostTicket({
  hostTicket,
  rulesVersion,
  freshSince,
}: {
  hostTicket: PvpMatchTicketDocument | undefined;
  rulesVersion: string;
  freshSince: Timestamp;
}): boolean {
  return (
    hostTicket !== undefined &&
    hostTicket.battleID === null &&
    hostTicket.rulesVersion === rulesVersion &&
    hostTicket.heartbeatAt.toMillis() >= freshSince.toMillis()
  );
}

/**
 * 行動の期限を過ぎた対戦の終わり方を返す。[submittedUIDs] は今のターンの行動を出し終えた利用者の uid。
 * 片方だけが出していれば出した側の勝ち、どちらも出していなければ勝敗を付けない (どちらが操作をやめたかをサーバーは見分けられないため)。
 */
export function timeoutOutcome({ submittedUIDs }: { submittedUIDs: string[] }): PvpBattleOutcome {
  return submittedUIDs.length === 1
    ? { winnerUID: submittedUIDs[0], finishReason: "timeout" }
    : { winnerUID: null, finishReason: "timeout" };
}

/**
 * [battle] に、端末の計算の勝者の報告 [reportedWinnerUID] (決着していないという報告は null) が届いた後の終わり方を返す。変わらない時は undefined。
 * 進行中の対戦は最初の報告で終え (相手がアプリを閉じても勝者の記録が残るようにするため)、報告で終わった対戦に食い違う報告が届いたら
 * 勝敗を付けない。期限切れ・ブロックで終わった対戦は、サーバーが見た事実で決めているため報告で変えない。
 */
export function outcomeAfterReport({
  battle,
  reportedWinnerUID,
}: {
  battle: PvpBattleDocument;
  reportedWinnerUID: string | null;
}): PvpBattleOutcome | undefined {
  if (battle.finishReason === null) {
    return reportedWinnerUID === null ? undefined : { winnerUID: reportedWinnerUID, finishReason: "result" };
  }
  if (battle.finishReason === "result" && reportedWinnerUID !== battle.winnerUID) {
    return { winnerUID: null, finishReason: "mismatch" };
  }
  return undefined;
}
