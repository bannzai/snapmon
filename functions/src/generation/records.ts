// 生成の状態遷移のレコード (`users/{uid}/generations/{requestId}`) と、生まれたモンスター (`users/{uid}/monsters/{monsterId}`) の形。
// 段階と終了状態は documents/adr/0001-tech-stack.md「サーバーコード」の行。

import type { Timestamp } from "firebase-admin/firestore";

import type { ClaudeUsage } from "./claude";
import type { LearnsetEntry, MonsterStats } from "./monster_stats";
import type { DescribeSubjectOutput, MonsterDecoration, SubjectDescription } from "./prompts/describe_subject";
import type { ProposeElementOutput } from "./prompts/propose_element";
import type { RejectionReason } from "./vision";

/** 済んだ段階。順に進み、再試行は最後に済んだ段階の次から始める。 */
export const GENERATION_STAGES = ["uploaded", "safesearch", "cutout", "claude", "classify", "dedupe", "judge", "saved"] as const;

/** 生成の段階。 */
export type GenerationStage = (typeof GENERATION_STAGES)[number];

/** 生成の状態。processing と pending_judge 以外は終了状態で、以後変わらない。 */
export type GenerationStatus = "processing" | "pending_judge" | "saved" | "duplicate" | "rejected" | "failed";

/** 終了状態。 */
export const TERMINAL_GENERATION_STATUSES: GenerationStatus[] = ["saved", "duplicate", "rejected", "failed"];

/** 生成の状態遷移のレコード。 */
export interface GenerationRecord {
  /** 状態。 */
  status: GenerationStatus;
  /** 最後に済んだ段階。 */
  completedStage: GenerationStage;
  /** 元の写真の Storage のパス。 */
  photoPath: string;
  /** クライアントが送ったマスクの Storage のパス。無ければ null (サーバーで自動のマスクを作る)。 */
  maskPath: string | null;
  /** 画像のハッシュとマスクのハッシュの組 (補助キー)。同じ組の生成は結果を使い回す。 */
  inputKey: string;
  /** 処理の予約の期限。期限までは別の実行が同じレコードを処理しない。 */
  leaseExpiresAt: Timestamp;
  /** 今の予約のトークン。予約を取るたびに変わり、古い実行が引き継がれた後の結果を書かないための照合に使う。 */
  leaseToken: string;
  /** 予約を取った回数 (呼び出しと、期限切れの引き継ぎ)。上限を超えたら failed にする。 */
  attemptCount: number;
  /** 判定待ちから再試行した回数。 */
  judgeRetryCount: number;
  /** 終わった生成の要らなくなったファイル (pipeline.ts の deleteDiscardedFiles) を消し終えたか。消し残しは再試行のタスクが消す。 */
  filesDeleted?: boolean;
  /** rejected の理由。 */
  rejectionReason?: RejectionReason;
  /** failed の理由 (ログと調査のため)。 */
  failureMessage?: string;
  /** Cloud Vision のラベル。 */
  visionLabels?: string[];
  /** 切り出した画像 (中間) の Storage のパス。saved の後は消す。 */
  cutoutPath?: string;
  /** 被写体の面積が写真に占める割合。 */
  cutoutCoverage?: number;
  /** マスクを作った場所。 */
  maskSource?: "client" | "server";
  /** Claude が返した説明・名前・文章・装飾。 */
  subject?: DescribeSubjectOutput;
  /** 説明を正規化した JSON 文字列。個体値の seed と同じ被写体の判定に使う。 */
  subjectDescriptionText?: string;
  /** Claude の使用量 (呼び出しごと)。原価の実測のため残す。 */
  claudeUsages?: ClaudeUsage[];
  /** Jev の入力トークン数の合計。原価の実測のため残す。 */
  jevInputTokens?: number;
  /** 判定に使った master の版。 */
  masterVersion?: number;
  /** 物の分類の上位 3 件。 */
  categoryIds?: string[];
  /** 新しい属性の提案 (Jev が答えずに判定待ちになっても、再試行で Claude を呼び直さないため残す)。 */
  elementProposal?: ProposeElementOutput;
  /** judge の段階で決めた、生まれるモンスターの値。 */
  judgement?: {
    elementTypeIds: string[];
    learnset: LearnsetEntry[];
    baseStats: MonsterStats;
    individualValues: MonsterStats;
    definitionIds: string[];
  };
  /** saved なら生まれたモンスター、duplicate なら同じ被写体の既存のモンスターの ID。 */
  monsterId?: string;
  /** 作った時刻。 */
  createdAt: Timestamp;
  /** 最後に書いた時刻。 */
  updatedAt: Timestamp;
}

/** `users/{uid}/monsters/{monsterId}` に保存するモンスター。`definition` は Dart の `MonsterDefinition.fromJson` が読む形。 */
export interface MonsterDocument {
  /** 生まれた時に決まる部分。 */
  definition: {
    id: string;
    sourcePhotoReference: string;
    name: string;
    encyclopediaText: string;
    elementTypeIds: string[];
    learnset: LearnsetEntry[];
    baseStats: MonsterStats;
    individualValues: MonsterStats;
    statCalculationVersion: number;
    masterVersion: number;
  };
  /** レベル。 */
  level: number;
  /** 戦ったバトルの回数の累計。 */
  experience: number;
  /** 切り出した被写体の画像の Storage のパス (`monsters/{monsterId}/art.png`)。 */
  artPath: string;
  /** 装飾のパラメータ。 */
  decoration: MonsterDecoration;
  /** 装飾の描画の版。 */
  decorationVersion: number;
  /** 被写体の説明 (同じ被写体の判定の比較に使う)。 */
  subjectDescription: SubjectDescription;
  /** 物の分類の上位 3 件 (同じ被写体の判定の候補の絞り込みに使う)。 */
  categoryIds: string[];
  /** 参照するその場で作った定義の ID。 */
  definitionIds: string[];
  /** 生まれた生成の requestId。 */
  generationRequestId: string;
  /** 生まれた時刻。 */
  createdAt: Timestamp;
}

/** callable と再試行が返す結果。 */
export interface GenerationResult {
  /** 生成の要求 ID。 */
  requestId: string;
  /** 状態。 */
  status: GenerationStatus;
  /** saved・duplicate の時のモンスターの ID。 */
  monsterId?: string;
  /** rejected の理由。 */
  rejectionReason?: RejectionReason;
}

/** レコードから、クライアントに返す結果を作る。 */
export function generationResult({ requestId, record }: { requestId: string; record: GenerationRecord }): GenerationResult {
  return {
    requestId,
    status: record.status,
    ...(record.monsterId ? { monsterId: record.monsterId } : {}),
    ...(record.rejectionReason ? { rejectionReason: record.rejectionReason } : {}),
  };
}

/** 説明を、キーの順を固定した JSON 文字列にする (同じ説明からは同じ文字列 = 同じ個体値の seed になるように)。 */
export function canonicalDescriptionText(description: SubjectDescription): string {
  const sortKeys = (value: unknown): unknown =>
    Array.isArray(value)
      ? value.map(sortKeys)
      : value && typeof value === "object"
        ? Object.fromEntries(Object.entries(value as Record<string, unknown>).sort(([left], [right]) => left.localeCompare(right)).map(([key, item]) => [key, sortKeys(item)]))
        : value;
  return JSON.stringify(sortKeys(description));
}
