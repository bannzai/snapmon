// 非同期 PvP (相手の選び方・他人に見せるモンスターの項目・表示名) と通報の、Firestore に依存しない規則。
// 決めた値と根拠は documents/DIRECTION.md「決めたこと」の 2026-10-22 の PvP の行。

import { createHash } from "node:crypto";

import { findModerationViolation } from "./generation/moderation";
import type { MonsterDocument } from "./generation/records";

/**
 * 相手の候補として読む、最近手持ちを変えたユーザーの数。
 * 対戦の画面を開くたびに、この数の手持ちと最大 3 倍の図鑑のモンスターを読むため、読み取りの回数を抑えつつ
 * 最近遊んでいる (手持ちを触った) ユーザーから選べる数にした。
 */
export const OPPONENT_CANDIDATE_SCAN_LIMIT = 50;

/** 1 回に返す相手の数 (issue #16 の「相手の候補 3 人」)。 */
export const OPPONENT_COUNT = 3;

/**
 * このユーザー数から通報されたモンスターを持つ相手を、全員の候補から外す。
 * 1 人の通報だけで他人を消せないようにしつつ、公開直後の少ない利用者でも早く効く数にした。
 * 通報は 1 件ごとに #snapmon-notification に届き、この数に届く前でも人が見て対応できる。
 */
export const REPORT_HIDE_THRESHOLD = 3;

/** 表示名の最大の文字数。対戦相手の画面のカード (幅 390 の画面) で「平均 Lv.」と同じ行に収まる長さにした。 */
export const DISPLAY_NAME_MAX_LENGTH = 12;

/** 通報の理由。クライアントの選択肢 (lib/features/opponent/report_reason.dart) と同じ値。 */
export const REPORT_REASONS = ["inappropriate_picture", "inappropriate_text", "person_in_picture", "other"] as const;

/** 通報の理由。 */
export type ReportReason = (typeof REPORT_REASONS)[number];

/** 通報の理由の、Slack の通知に書く日本語。 */
const REPORT_REASON_LABELS: Record<ReportReason, string> = {
  inappropriate_picture: "不適切な絵",
  inappropriate_text: "不適切な名前・文章",
  person_in_picture: "人が写っている",
  other: "その他",
};

/** [value] が通報の理由か。 */
export function isReportReason(value: unknown): value is ReportReason {
  return typeof value === "string" && (REPORT_REASONS as readonly string[]).includes(value);
}

/** Firestore のドキュメント ID に使える uid・monsterId か (空でなく `/` を含まない)。 */
export function isDocumentId(value: unknown): value is string {
  return typeof value === "string" && value !== "" && !value.includes("/");
}

/** 相手の候補 1 人。候補を読んだ順 (手持ちを変えた新しい順) に並べて [selectOpponents] に渡す。 */
export interface OpponentCandidate {
  /** 相手の uid。 */
  uid: string;
  /** 手持ちのうち図鑑にあるモンスターのレベル。 */
  partyLevels: number[];
}

/** [levels] (1 件以上) の平均 (切り捨て)。クライアントの averagePartyLevel と同じ数え方。 */
export function averageLevel(levels: number[]): number {
  return Math.floor(levels.reduce((sum, level) => sum + level, 0) / levels.length);
}

/**
 * [candidates] から、手持ちの平均レベルが [playerAverageLevel] に近い順に [OPPONENT_COUNT] 人を選び、その uid を返す。
 * 差が同じ時は [candidates] の順 (手持ちを変えた新しい順) を保つ。手持ちが空の候補は選ばない。
 */
export function selectOpponents({
  candidates,
  playerAverageLevel,
}: {
  candidates: OpponentCandidate[];
  playerAverageLevel: number;
}): string[] {
  return candidates
    .filter((candidate) => candidate.partyLevels.length > 0)
    .map((candidate, order) => ({
      uid: candidate.uid,
      order,
      distance: Math.abs(averageLevel(candidate.partyLevels) - playerAverageLevel),
    }))
    .sort((left, right) => left.distance - right.distance || left.order - right.order)
    .slice(0, OPPONENT_COUNT)
    .map((candidate) => candidate.uid);
}

/**
 * 表示名を設定していないユーザーの表示名 (「トレーナー」+ uid から決まる 4 桁)。同じ uid からは同じ名前になる。
 * 匿名ログインの既定 (issue #16) で、名前を保存しなくても相手の画面と本人の設定で同じ名前を出せるよう uid から決める。
 */
export function defaultDisplayName(uid: string): string {
  const number = createHash("sha256").update(uid).digest().readUInt32BE(0) % 10000;
  return `トレーナー ${number.toString().padStart(4, "0")}`;
}

/** 保存した表示名 [storedDisplayName] があればそれを、無ければ [defaultDisplayName] を返す。 */
export function displayNameOf({ uid, storedDisplayName }: { uid: string; storedDisplayName: unknown }): string {
  return typeof storedDisplayName === "string" ? storedDisplayName : defaultDisplayName(uid);
}

/**
 * 利用者が入力した表示名 [input] を検査し、保存する形 (前後の空白を除いた文字列) を返す。
 * 不適切な時は `{ error }` に利用者に出す文言を入れて返す。禁止語は生成した文章と同じ一覧で照らす (moderation.ts)。
 */
export function validateDisplayName(input: unknown): { displayName: string } | { error: string } {
  if (typeof input !== "string") {
    return { error: "表示名を入力してください" };
  }
  const displayName = input.trim();
  if (displayName === "") {
    return { error: "表示名を入力してください" };
  }
  if ([...displayName].length > DISPLAY_NAME_MAX_LENGTH) {
    return { error: `表示名は ${DISPLAY_NAME_MAX_LENGTH} 文字までです` };
  }
  // 改行・タブ等の制御文字と、見えない書式文字 (幅の無い空白・向きの制御) は、表示を崩すか別の名前に見せられるため弾く
  if (/[\p{Cc}\p{Cf}]/u.test(displayName)) {
    return { error: "表示名に使えない文字が含まれています" };
  }
  if (findModerationViolation(displayName) !== undefined) {
    return { error: "この表示名は使えません" };
  }
  return { displayName };
}

/** 他のユーザーに見せるモンスター。`definition` は Dart の `MonsterDefinition.fromJson` が読む形で、元の写真の参照を持たない。 */
export interface PublicMonster {
  /** 生まれた時に決まる部分のうち、他人に見せてよい項目。 */
  definition: Omit<MonsterDocument["definition"], "sourcePhotoReference">;
  /** レベル。 */
  level: number;
  /** 切り出した被写体の画像の Storage のパス (ログインした全員が読める)。 */
  artPath: string;
  /** 参照するその場で作った定義の ID (クライアントが `definitions/` から属性・技を引く)。 */
  definitionIds: string[];
  /** 装飾のパラメータ。 */
  decoration: MonsterDocument["decoration"];
  /** 装飾の描画の版。 */
  decorationVersion: number;
}

/**
 * 図鑑のモンスター [monster] から、他のユーザーに見せてよい項目だけを写す。
 * 元の写真の参照・被写体の説明・分類・生成の要求 ID は他人に返さないため、返してよい項目を 1 つずつ名指しで写す
 * (ドキュメントに項目が増えても、ここに足さない限り返らない)。
 */
export function publicMonster(monster: MonsterDocument): PublicMonster {
  const { definition } = monster;
  return {
    definition: {
      id: definition.id,
      name: definition.name,
      encyclopediaText: definition.encyclopediaText,
      elementTypeIds: definition.elementTypeIds,
      learnset: definition.learnset,
      baseStats: definition.baseStats,
      individualValues: definition.individualValues,
      statCalculationVersion: definition.statCalculationVersion,
      masterVersion: definition.masterVersion,
    },
    level: monster.level,
    artPath: monster.artPath,
    definitionIds: monster.definitionIds,
    decoration: monster.decoration,
    decorationVersion: monster.decorationVersion,
  };
}

/** `reports/{reportId}` に保存する通報 (reportMonster が書く)。 */
export interface ReportDocument {
  /** 通報したユーザーの uid。 */
  reporterUid: string;
  /** 通報されたモンスターの持ち主の uid。 */
  monsterOwnerUid: string;
  /** 通報されたモンスターの ID。 */
  monsterId: string;
  /** 通報されたモンスターの名前 (通知に出すため、通報した時点の名前を写す)。 */
  monsterName: string;
  /** 通報されたモンスターの切り出した画像の Storage のパス。 */
  monsterArtPath: string;
  /** 理由。 */
  reason: ReportReason;
}

/** 通報 1 件の ID。同じユーザーが同じモンスターを何度通報しても 1 件として数えるため、2 つの ID から決める。 */
export function reportDocumentId({ reporterUid, monsterId }: { reporterUid: string; monsterId: string }): string {
  return `${reporterUid}_${monsterId}`;
}

/** ブロック 1 件の ID。同じ相手を何度ブロックしても 1 件にするため、2 つの uid から決める。 */
export function blockDocumentId({ blockerUid, blockedUid }: { blockerUid: string; blockedUid: string }): string {
  return `${blockerUid}_${blockedUid}`;
}

/** 通報 [report] を #snapmon-notification に知らせる文章。 */
export function reportNotificationText({ reportId, report }: { reportId: string; report: ReportDocument }): string {
  return [
    `PvP の通報: ${REPORT_REASON_LABELS[report.reason]}`,
    `モンスター: ${report.monsterName} (${report.monsterId})`,
    `持ち主: ${report.monsterOwnerUid}`,
    `通報した人: ${report.reporterUid}`,
    `絵: ${report.monsterArtPath}`,
    `通報: reports/${reportId}`,
    `${REPORT_HIDE_THRESHOLD} 人から通報されると、持ち主は対戦の相手の候補から外れる`,
    // 通報者の数は匿名ログインの uid で数えるため、1 人が複数のアカウントで数を作れる。外れた持ち主を戻す手順を通知に添える
    `不当な通報で外れた持ち主を戻す時は reportedMonsters/${report.monsterId} を消す`,
  ].join("\n");
}
