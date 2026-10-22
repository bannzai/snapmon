// 写真からモンスターを生成する状態遷移。callable (generate.ts) と再試行のタスク (resume.ts) の両方がここを呼ぶ。
// 設計は documents/adr/0001-tech-stack.md「サーバーコード」「同じ被写体の判定」「master に無い属性・技」と ADR 0002。
// 冪等性: 要求 ID ごとのレコードを予約 (lease) してから段階を進め、各段階の結果をレコードに書く。再試行は済んだ段階を飛ばすため、
// 有料の API (Vision・Claude・Jev) を同じ段階で 2 回呼ばない。例外は、段階の途中で落ちた時 (結果を書く前) の 1 回分。

import { createHash } from "node:crypto";

import { FieldValue, type Firestore, Timestamp, type Transaction } from "firebase-admin/firestore";
import type { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";

import { ClaudeRefusalError, type DescribeSubject, type ProposeElement } from "./claude";
import { applyMask, downscalePhoto, flattenCutoutForDescription, type SegmentSubject } from "./cutout";
import {
  type AskJev,
  buildClassifyRequest,
  buildDedupeRequests,
  buildJudgeRequest,
  buildSameDefinitionRequest,
  DEDUPE_THRESHOLDS,
  type DedupeCandidate,
  type JevResponse,
  JevUnavailableError,
  readJudgeResponse,
  sameSubjectCandidateIds,
  topCategoryIds,
} from "./jev";
import { type DynamicDefinition, fetchDynamicDefinitions, fetchLatestMaster, fetchMaster, type Master, type MasterElementType, type MasterMove } from "./master";
import { findModerationViolation } from "./moderation";
import {
  baseStatsFromStatGrades,
  buildLearnset,
  CURRENT_STAT_CALCULATION_VERSION,
  fnv1a32,
  individualValuesFromDescription,
  selectElementTypeIds,
} from "./monster_stats";
import { DECORATION_VERSION } from "./prompts/describe_subject";
import { PROPOSED_MOVE_TIERS, proposalRangeViolation } from "./prompts/propose_element";
import {
  canonicalDescriptionText,
  type GenerationRecord,
  type GenerationResult,
  generationResult,
  GENERATION_STAGES,
  type GenerationStage,
  type MonsterDocument,
  TERMINAL_GENERATION_STATUSES,
} from "./records";
import { type AnnotateImage, type RejectionReason, visionRejectionReason } from "./vision";

/** Cloud Storage のバケット。 */
export type StorageBucket = ReturnType<ReturnType<typeof getStorage>["bucket"]>;

/** 生成が使う外部の資源。callable と再試行は本番の実装を、テストはモックを渡す。 */
export interface GenerationDependencies {
  /** Firestore。 */
  firestore: Firestore;
  /** 写真・切り出し・絵を置くバケット。 */
  bucket: StorageBucket;
  /** Cloud Vision。 */
  annotateImage: AnnotateImage;
  /** 自動のマスク。 */
  segmentSubject: SegmentSubject;
  /** Claude の被写体の説明。 */
  describeSubject: DescribeSubject;
  /** Claude の新しい属性の提案。 */
  proposeElement: ProposeElement;
  /** Jev。 */
  askJev: AskJev;
  /** 再試行のタスクを積む。`delaySeconds` 後に `resumeGeneration` が同じ要求 ID と目的で呼ばれる。 */
  enqueueResume: (task: ResumeTask & { delaySeconds: number; taskId?: string }) => Promise<void>;
  /** 現在時刻。 */
  now: () => Date;
}

/**
 * 再試行のタスクの中身。`purpose` は何を引き継ぐタスクかを表す。
 * - lease: 予約が切れた処理中の生成を引き継ぐ (と、終了した生成の消し残したファイルを消す)。判定待ちには触れない
 * - judge: 判定待ちの生成を 1 回分の再試行として続きから進める (1 時間おきの系列を 1 つだけにするため、lease のタスクとは分ける)
 * - discard: 別の要求 ID の結果を使い回した要求の、写真とマスクを消す (その要求にはレコードが無く、ほかに消す経路が無いため)
 */
export interface ResumeTask {
  /** 生成したユーザー。 */
  uid: string;
  /** 生成の要求 ID。 */
  requestId: string;
  /** タスクの目的。 */
  purpose: "lease" | "judge" | "discard";
  /**
   * judge のタスクが進めてよい再試行の回数 (積んだ時点の `judgeRetryCount`)。Cloud Tasks は同じタスクを 2 回届けることがあり、
   * 一度進めた後に届いた同じタスクで再試行を重ねないため、レコードの回数と一致する時だけ進める。
   */
  judgeAttempt?: number;
}

/**
 * 予約 (lease) と uid ごとの生成中ロックの期間 (ADR 0001 の 10 分)。生成の Functions のタイムアウト (generate.ts の 300 秒) より長くし、
 * 元の実行が終わる前に再試行が同じレコードを処理し始めないようにする。
 */
export const LEASE_DURATION_SECONDS = 600;

/** 判定待ちの再試行の間隔と回数 (ADR 0001 の 1 時間おき・最大 24 回)。 */
export const JUDGE_RETRY_INTERVAL_SECONDS = 3_600;
export const JUDGE_RETRY_MAXIMUM_COUNT = 24;

/**
 * 予約を取れる回数の上限。Jev 以外の失敗 (Claude・Vision の一時的なエラー、タイムアウト) で落ちた生成を、期限切れの引き継ぎで
 * やり直す回数を抑える (直らない失敗で有料の API を呼び続けないため)。直して再試行の既定 3 回
 * (~/.claude/documents/rules/retry-limit-and-failure-classification.md) に最初の 1 回を足した値。
 */
const MAXIMUM_ATTEMPT_COUNT = 4;

/** 段階が予期しないエラーで落ちた時に、再試行を始めるまでの秒数。一時的なエラー (API の 5xx・通信の切断) が収まる時間として置いた。 */
const FAILED_STAGE_RETRY_DELAY_SECONDS = 60;

/** Claude の文章が禁止語の検査を通らなかった時に、作り直させる回数の上限 (最初の 1 回を含む)。 */
const DESCRIBE_SUBJECT_MAXIMUM_ATTEMPTS = 2;

/**
 * uid ごとの 1 日の生成の上限。1 体の原価の見積もり (ADR 0002) と、1 日に遊ぶ回数として十分な数から決めた。
 * 利用規約 (docs/Terms.md 第 4 条の 4) は上限を設けることだけを書き、値は書かない。
 */
export const DAILY_GENERATION_LIMIT_PER_USER = 20;
/** プロジェクト全体の 1 日の生成の上限。1 体の原価の見積もり (ADR 0002 の約 0.03 ドル) で、1 日の原価を 30 ドル前後に抑える値。 */
export const DAILY_GENERATION_LIMIT_TOTAL = 1_000;

/** 物の分類を保存する件数 (ADR 0001 の上位 3 件)。 */
const CATEGORY_COUNT = 3;
/** Cloud Vision のラベルのうち、分類の state に入れる確からしさの下限 (Vision のラベルは 0.5 以上で返る。根拠の薄いものを除くため 0.6)。 */
const VISION_LABEL_MINIMUM_SCORE = 0.6;

/**
 * その場で作った属性を、既存のその場で作った属性と同じ意味とみなす Jev の確率の下限。
 * その場で作った属性がまだ 1 件も無く、ラベル付きのサンプルで測れないため未較正 (documents/game-rules.md「Jev の閾値」)。
 * 誤って同じとみなすと別の性質の属性に寄せられるだけで、二重の定義より害が小さいため、低すぎない値を置いた。
 */
const SAME_DEFINITION_PROBABILITY_THRESHOLD = 0.8;

/** 属性と技の数の上限 (ADR 0001 の属性 24 種・技 2,000 件)。 */
const ELEMENT_TYPE_LIMIT = 24;
const MOVE_LIMIT = 2_000;

/** 生成の要求を受け付けられない理由。callable は HttpsError に、それ以外はログに出す。 */
export class GenerationRequestError extends Error {
  /** 理由の種類。 */
  readonly code: "daily_limit_per_user" | "daily_limit_total" | "another_generation_in_progress";

  constructor(code: GenerationRequestError["code"], message: string) {
    super(message);
    this.code = code;
  }
}

/** Asia/Tokyo の日付 (YYYY-MM-DD)。1 日の上限の区切りに使う (利用者の多くが日本にいる前提で、日付の変わり目を日本時間にした)。 */
function tokyoDate(date: Date): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Tokyo" }).format(date);
}

function sha256(buffer: Buffer): string {
  return createHash("sha256").update(buffer).digest("hex");
}

function generationDocument({ firestore, uid, requestId }: { firestore: Firestore; uid: string; requestId: string }) {
  return firestore.doc(`users/${uid}/generations/${requestId}`);
}

/** 別の要求 ID の結果を使い回した要求の、使い回し先 (`reusedRequestId`) の記録。 */
function generationAliasDocument({ firestore, uid, requestId }: { firestore: Firestore; uid: string; requestId: string }) {
  return firestore.doc(`users/${uid}/generationAliases/${requestId}`);
}

async function downloadFile(bucket: StorageBucket, path: string): Promise<Buffer> {
  const [contents] = await bucket.file(path).download();
  return contents;
}

/** 同じ被写体と判定した相手がまだ保存前の生成で、その結果を待つ必要があることを表す。Jev が答えない時と同じく判定待ちにする。 */
class WaitingForOtherGenerationError extends Error {}

/** 受け付けた後に写真かマスクが差し替えられたこと (検査した画像と切り出す画像が別物になる) を表す。生成は failed にする。 */
class InputChangedError extends Error {}

/**
 * 写真 (とマスク) を読み、受付時のハッシュ (`inputKey`) と同じ中身であることを確かめて返す。
 * クライアントは同じパスを上書きできる (Storage の Rules) ため、検査した写真と切り出す写真を同じ中身に固定する。
 */
async function downloadVerifiedInput(bucket: StorageBucket, record: GenerationRecord): Promise<{ photo: Buffer; mask: Buffer | undefined }> {
  const [photoHash, maskHash] = record.inputKey.split(":");
  const photo = await downloadFile(bucket, record.photoPath);
  const mask = record.maskPath ? await downloadFile(bucket, record.maskPath) : undefined;
  if (sha256(photo) !== photoHash || (mask ? sha256(mask) : "auto") !== maskHash) {
    throw new InputChangedError("受け付けた後に写真かマスクが差し替えられました");
  }
  return { photo, mask };
}

/** 中間のファイルを消す。無いファイルは無視する (再試行で 2 回目に呼ばれても成功させるため)。 */
async function deleteFiles(bucket: StorageBucket, paths: (string | null | undefined)[]): Promise<void> {
  await Promise.all(paths.filter((path): path is string => !!path).map((path) => bucket.file(path).delete({ ignoreNotFound: true })));
}

/**
 * 生成の要求を受け付け、終了状態か判定待ちになるまで進めて結果を返す (callable の本体)。
 * 同じ要求 ID の 2 回目以降は、保存済みの結果を返す (処理中なら processing を返し、二重に処理しない)。
 * 画像とマスクの組が同じ生成が既にあれば、新しいレコードを作らずにその結果を返す。
 */
export async function startGeneration(
  dependencies: GenerationDependencies,
  { uid, requestId, photoPath, maskPath }: { uid: string; requestId: string; photoPath: string; maskPath: string | null },
): Promise<GenerationResult> {
  const { firestore, bucket } = dependencies;
  const document = generationDocument({ firestore, uid, requestId });
  const existing = await document.get();
  if (existing.exists) {
    return continueExistingGeneration(dependencies, { uid, requestId, record: existing.data() as GenerationRecord });
  }
  // 別の要求 ID の結果を使い回した要求の再送 (写真は消してあるため、記録した使い回し先の結果を返す)
  const alias = await generationAliasDocument({ firestore, uid, requestId }).get();
  if (alias.exists) {
    const reusedRequestId = alias.get("reusedRequestId") as string;
    return generationResult({ requestId: reusedRequestId, record: (await generationDocument({ firestore, uid, requestId: reusedRequestId }).get()).data() as GenerationRecord });
  }

  const photo = await downloadFile(bucket, photoPath);
  const mask = maskPath ? await downloadFile(bucket, maskPath) : undefined;
  const inputKey = `${sha256(photo)}:${mask ? sha256(mask) : "auto"}`;
  const now = dependencies.now();
  const today = tokyoDate(now);

  // 予約より先に積む (予約の後で積むのに失敗すると、引き継ぐタスクの無い予約が残るため)。予約しなかった時のタスクは、
  // レコードが無いか予約の取れない状態を見て何もしない。
  await enqueueLeaseRecovery(dependencies, { uid, requestId });
  const reservation = await firestore.runTransaction(async (transaction): Promise<GenerationResult | "reserved"> => {
    // failed は使い回さない (撮り直さずに同じ写真で再挑戦できるように)。状態は複合インデックスを増やさないようコードで絞る。
    const sameInput = (await transaction.get(firestore.collection(`users/${uid}/generations`).where("inputKey", "==", inputKey))).docs.find(
      (document) => (document.data() as GenerationRecord).status !== "failed",
    );
    if (sameInput) {
      // 写真を消す前に、この要求 ID と使い回し先の対応を残す (応答を受け取れずに同じ要求 ID で再送されても結果を返せるように)
      transaction.set(generationAliasDocument({ firestore, uid, requestId }), { reusedRequestId: sameInput.id, createdAt: Timestamp.fromDate(now) });
      return generationResult({ requestId: sameInput.id, record: sameInput.data() as GenerationRecord });
    }
    const current = await transaction.get(document);
    if (current.exists) {
      return generationResult({ requestId, record: current.data() as GenerationRecord });
    }
    const userDocument = firestore.doc(`users/${uid}`);
    const totalCounterDocument = firestore.doc(`generationDailyCounts/${today}`);
    const [userSnapshot, totalCounterSnapshot] = await Promise.all([transaction.get(userDocument), transaction.get(totalCounterDocument)]);
    assertGenerationLockAvailable({ lock: userSnapshot.get("generationLock"), requestId, now });
    const userCount = userSnapshot.get("dailyGeneration.date") === today ? (userSnapshot.get("dailyGeneration.count") as number) : 0;
    if (userCount >= DAILY_GENERATION_LIMIT_PER_USER) {
      throw new GenerationRequestError("daily_limit_per_user", `今日の生成は ${DAILY_GENERATION_LIMIT_PER_USER} 回までです`);
    }
    if (((totalCounterSnapshot.get("count") as number | undefined) ?? 0) >= DAILY_GENERATION_LIMIT_TOTAL) {
      throw new GenerationRequestError("daily_limit_total", "今日は生成が混み合っています。明日またためしてください");
    }
    const leaseExpiresAt = Timestamp.fromMillis(now.getTime() + LEASE_DURATION_SECONDS * 1000);
    transaction.set(
      userDocument,
      { generationLock: { requestId, expiresAt: leaseExpiresAt }, dailyGeneration: { date: today, count: userCount + 1 } },
      { merge: true },
    );
    transaction.set(totalCounterDocument, { count: FieldValue.increment(1) }, { merge: true });
    const record: GenerationRecord = {
      status: "processing",
      completedStage: "uploaded",
      photoPath,
      maskPath,
      inputKey,
      leaseExpiresAt,
      attemptCount: 1,
      judgeRetryCount: 0,
      createdAt: Timestamp.fromDate(now),
      updatedAt: Timestamp.fromDate(now),
    };
    transaction.create(document, record);
    return "reserved";
  });
  if (reservation !== "reserved") {
    // 別の要求 ID の結果を使い回した時は、今回の要求で置かれた写真とマスクにはレコードが無く、誰も消さないため、ここで消す。
    // 消すのに失敗した時のために、消すタスクを先に積む (タスクも同じパスを消し、無いファイルは無視する)。
    if (reservation.requestId !== requestId) {
      await dependencies.enqueueResume({ uid, requestId, purpose: "discard", delaySeconds: FAILED_STAGE_RETRY_DELAY_SECONDS });
      await deleteFiles(bucket, [photoPath, maskPath]);
    }
    return reservation;
  }
  return advanceGeneration(dependencies, { uid, requestId });
}

/**
 * 実行が予約の期限までに終わらなかった時 (タイムアウト・インスタンスの停止) に、期限切れの予約を引き継ぐタスクを積む。
 * 予約を取る直前に毎回積む (引き継いだ実行も止まり得るため。予約の後に積むと、積むのに失敗した時に引き継ぐタスクが無くなるため)。
 */
function enqueueLeaseRecovery(dependencies: GenerationDependencies, { uid, requestId }: { uid: string; requestId: string }): Promise<void> {
  return dependencies.enqueueResume({ uid, requestId, purpose: "lease", delaySeconds: LEASE_DURATION_SECONDS + 60 });
}

/** 既にレコードがある要求 ID の呼び出し。終了状態・判定待ち・予約中はそのまま返し、予約が切れた処理中は引き継ぐ。 */
async function continueExistingGeneration(
  dependencies: GenerationDependencies,
  { uid, requestId, record }: { uid: string; requestId: string; record: GenerationRecord },
): Promise<GenerationResult> {
  if (!isLeaseAcquirable({ record, now: dependencies.now(), resumingFromPendingJudge: false })) {
    return generationResult({ requestId, record });
  }
  await enqueueLeaseRecovery(dependencies, { uid, requestId });
  const acquired = await acquireLease(dependencies, { uid, requestId, resumingFromPendingJudge: false });
  if (acquired !== "acquired") {
    return acquired;
  }
  return advanceGeneration(dependencies, { uid, requestId });
}

/**
 * 予約を取れる状態か (予約の切れた処理中か、judge のタスクから見た判定待ち)。予約を取る前のタスクを積むかの判断に使う
 * (取れない状態で積むと、何もしないタスクが次のタスクを積み続けるため)。最終の判断は acquireLease のトランザクションが行う。
 */
function isLeaseAcquirable({ record, now, resumingFromPendingJudge }: { record: GenerationRecord; now: Date; resumingFromPendingJudge: boolean }): boolean {
  return (record.status === "processing" && record.leaseExpiresAt.toMillis() <= now.getTime()) || (record.status === "pending_judge" && resumingFromPendingJudge);
}

/** uid ごとの生成中ロックが、別の要求 ID に期限内で取られていれば throw する。 */
function assertGenerationLockAvailable({ lock, requestId, now }: { lock: { requestId: string; expiresAt: Timestamp } | undefined; requestId: string; now: Date }) {
  if (lock && lock.requestId !== requestId && lock.expiresAt.toMillis() > now.getTime()) {
    throw new GenerationRequestError("another_generation_in_progress", "別の生成が進んでいます。終わってからためしてください");
  }
}

/**
 * 既存のレコードの予約を取る。取れたら "acquired"、取れない (終了状態・予約中・判定待ちで再試行からの呼び出しでない) なら現在の結果を返す。
 * 予約を取る回数が上限を超えたら failed にする。
 */
async function acquireLease(
  dependencies: GenerationDependencies,
  {
    uid,
    requestId,
    resumingFromPendingJudge,
    judgeAttempt,
  }: { uid: string; requestId: string; resumingFromPendingJudge: boolean; judgeAttempt?: number },
): Promise<GenerationResult | "acquired"> {
  const { firestore } = dependencies;
  const document = generationDocument({ firestore, uid, requestId });
  const now = dependencies.now();
  const outcome = await firestore.runTransaction(async (transaction): Promise<GenerationResult | "acquired" | "exhausted"> => {
    const snapshot = await transaction.get(document);
    const record = snapshot.data() as GenerationRecord;
    const userDocument = firestore.doc(`users/${uid}`);
    const userSnapshot = await transaction.get(userDocument);
    // 同じ回の judge のタスクが同時に 2 つ届いても、回数が一致する方の 1 つだけが予約を取る
    const isWaitingJudge = record.status === "pending_judge" && record.judgeRetryCount === judgeAttempt;
    const isExpiredProcessing = record.status === "processing" && record.leaseExpiresAt.toMillis() <= now.getTime();
    if (!(isExpiredProcessing || (isWaitingJudge && resumingFromPendingJudge))) {
      return generationResult({ requestId, record });
    }
    if (isExpiredProcessing && record.attemptCount >= MAXIMUM_ATTEMPT_COUNT) {
      return "exhausted";
    }
    assertGenerationLockAvailable({ lock: userSnapshot.get("generationLock"), requestId, now });
    const leaseExpiresAt = Timestamp.fromMillis(now.getTime() + LEASE_DURATION_SECONDS * 1000);
    transaction.set(userDocument, { generationLock: { requestId, expiresAt: leaseExpiresAt } }, { merge: true });
    transaction.update(document, {
      status: "processing",
      leaseExpiresAt,
      updatedAt: Timestamp.fromDate(now),
      ...(isWaitingJudge ? { judgeRetryCount: FieldValue.increment(1) } : { attemptCount: FieldValue.increment(1) }),
    });
    return "acquired";
  });
  if (outcome === "exhausted") {
    return finishGeneration(dependencies, { uid, requestId, update: { status: "failed", failureMessage: `予約を ${MAXIMUM_ATTEMPT_COUNT} 回取っても終わりませんでした` } });
  }
  return outcome;
}

/**
 * 再試行のタスクの本体。judge のタスクは、判定待ちなら 1 回分の再試行として続きから進め、回数の上限を超えたら failed にする。
 * どちらのタスクも、予約が切れた処理中なら引き継ぎ、終了した生成に消し残したファイルがあれば消す。それ以外 (予約中・目的の違う判定待ち) は何もしない。
 */
export async function resumeGeneration(dependencies: GenerationDependencies, { uid, requestId, purpose, judgeAttempt }: ResumeTask): Promise<GenerationResult> {
  const snapshot = await generationDocument({ firestore: dependencies.firestore, uid, requestId }).get();
  if (!snapshot.exists) {
    // レコードの無い要求の写真とマスクだけを消す (パスは uid と要求 ID から決め、タスクの中身からは受け取らない)
    if (purpose === "discard") {
      await deleteFiles(dependencies.bucket, [`users/${uid}/photos/${requestId}`, `users/${uid}/masks/${requestId}`]);
    }
    return { requestId, status: "failed" };
  }
  const record = snapshot.data() as GenerationRecord;
  if (purpose === "discard") {
    return generationResult({ requestId, record });
  }
  if (record.status === "pending_judge" && purpose === "judge" && judgeAttempt !== record.judgeRetryCount) {
    // 進め終えた回の judge のタスクがもう一度届いた
    return generationResult({ requestId, record });
  }
  if (TERMINAL_GENERATION_STATUSES.includes(record.status)) {
    await deleteDiscardedFiles(dependencies, { uid, requestId, record });
    return generationResult({ requestId, record });
  }
  if (record.status === "pending_judge" && purpose !== "judge") {
    return generationResult({ requestId, record });
  }
  if (record.status === "pending_judge" && record.judgeRetryCount >= JUDGE_RETRY_MAXIMUM_COUNT) {
    return finishGeneration(dependencies, {
      uid,
      requestId,
      update: { status: "failed", failureMessage: `Jev が ${JUDGE_RETRY_MAXIMUM_COUNT} 回の再試行でも答えませんでした` },
    });
  }
  if (!isLeaseAcquirable({ record, now: dependencies.now(), resumingFromPendingJudge: purpose === "judge" })) {
    return generationResult({ requestId, record });
  }
  await enqueueLeaseRecovery(dependencies, { uid, requestId });
  let acquired: GenerationResult | "acquired";
  try {
    acquired = await acquireLease(dependencies, { uid, requestId, resumingFromPendingJudge: purpose === "judge", judgeAttempt });
  } catch (error) {
    if (error instanceof GenerationRequestError && error.code === "another_generation_in_progress") {
      // 同じ uid の別の生成が終わるまで待ってから続ける (直列にするため。ADR 0001「同じ被写体の判定」)。
      // lease のタスクは直前に積んだタスク (ロックの期限より後に届く) が続きを受け持つため、judge のタスクだけを積み直す。
      if (purpose === "judge") {
        await dependencies.enqueueResume({ uid, requestId, purpose, judgeAttempt, delaySeconds: LEASE_DURATION_SECONDS });
      }
      return generationResult({ requestId, record });
    }
    throw error;
  }
  if (acquired !== "acquired") {
    return acquired;
  }
  return advanceGeneration(dependencies, { uid, requestId });
}

/** 段階の処理が返す、レコードへの書き込みと次の行き先。 */
type StageOutcome =
  | { kind: "next"; update: Partial<GenerationRecord> }
  | { kind: "finish"; update: Partial<GenerationRecord> & { status: GenerationRecord["status"] } };

/** 予約を取った生成を、終了状態か判定待ちになるまで段階ごとに進める。 */
async function advanceGeneration(dependencies: GenerationDependencies, { uid, requestId }: { uid: string; requestId: string }): Promise<GenerationResult> {
  const document = generationDocument({ firestore: dependencies.firestore, uid, requestId });
  for (;;) {
    const record = (await document.get()).data() as GenerationRecord;
    if (record.status !== "processing") {
      return generationResult({ requestId, record });
    }
    const nextStage = GENERATION_STAGES[GENERATION_STAGES.indexOf(record.completedStage) + 1];
    let outcome: StageOutcome;
    try {
      outcome = await runStage(dependencies, { uid, requestId, record, stage: nextStage });
    } catch (error) {
      if (error instanceof JevUnavailableError || error instanceof WaitingForOtherGenerationError) {
        logger.warn("判定待ちにします", { uid, requestId, stage: nextStage, error: error.message });
        // タスクを先に積んでから判定待ちにする。逆の順で積むのに失敗すると、判定待ちを進めるタスクが無いまま止まるため
        // (先に積んで状態の更新が失敗した時は、処理中のまま予約切れを引き継ぐタスクが拾う)。
        // タスクの ID を再試行の回数で決め、同じ回の再試行のタスクが 2 つ積まれないようにする。
        await dependencies.enqueueResume({
          uid,
          requestId,
          purpose: "judge",
          delaySeconds: JUDGE_RETRY_INTERVAL_SECONDS,
          judgeAttempt: record.judgeRetryCount,
          taskId: `${uid}-${requestId}-judge-${record.judgeRetryCount}`,
        });
        await releaseLock(dependencies, { uid, requestId, update: { status: "pending_judge" } });
        return { requestId, status: "pending_judge" };
      }
      if (error instanceof ClaudeRefusalError) {
        return finishGeneration(dependencies, { uid, requestId, update: { status: "rejected", rejectionReason: "refused" } });
      }
      if (error instanceof InputChangedError) {
        return finishGeneration(dependencies, { uid, requestId, update: { status: "failed", failureMessage: error.message } });
      }
      // それ以外 (Claude・Vision・Storage の一時的なエラー) は、予約を今すぐ切れた扱いにしてロックを外し、少し後の再試行に引き継ぐ。
      // 予約を取る回数の上限 (MAXIMUM_ATTEMPT_COUNT) で、直らない失敗は failed になる。
      logger.error("生成の段階が失敗しました。再試行に回します", { uid, requestId, stage: nextStage, error });
      await releaseLock(dependencies, { uid, requestId, update: { leaseExpiresAt: Timestamp.fromDate(dependencies.now()) } });
      await dependencies.enqueueResume({ uid, requestId, purpose: "lease", delaySeconds: FAILED_STAGE_RETRY_DELAY_SECONDS });
      throw error;
    }
    if (outcome.kind === "finish") {
      return finishGeneration(dependencies, { uid, requestId, update: outcome.update });
    }
    await document.update({ ...outcome.update, completedStage: nextStage, updatedAt: Timestamp.fromDate(dependencies.now()) });
  }
}

/** uid の生成中ロックを、自分の要求 ID のものなら外し、レコードに書く。 */
async function releaseLock(
  dependencies: GenerationDependencies,
  { uid, requestId, update }: { uid: string; requestId: string; update: Partial<GenerationRecord> },
): Promise<GenerationRecord> {
  const { firestore } = dependencies;
  const document = generationDocument({ firestore, uid, requestId });
  return firestore.runTransaction(async (transaction) => {
    const userDocument = firestore.doc(`users/${uid}`);
    const [userSnapshot, snapshot] = await Promise.all([transaction.get(userDocument), transaction.get(document)]);
    if (userSnapshot.get("generationLock.requestId") === requestId) {
      transaction.update(userDocument, { generationLock: FieldValue.delete() });
    }
    transaction.update(document, { ...update, updatedAt: Timestamp.fromDate(dependencies.now()) });
    return { ...(snapshot.data() as GenerationRecord), ...update };
  });
}

/** 終了状態にし、ロックを外し、拒否・重複なら元の写真と中間のファイルを消す (ADR 0001「画像ストレージ」)。 */
async function finishGeneration(
  dependencies: GenerationDependencies,
  { uid, requestId, update }: { uid: string; requestId: string; update: Partial<GenerationRecord> & { status: GenerationRecord["status"] } },
): Promise<GenerationResult> {
  const record = await releaseLock(dependencies, { uid, requestId, update });
  logger.info("生成を終えました", { uid, requestId, status: record.status, rejectionReason: record.rejectionReason, failureMessage: record.failureMessage });
  try {
    await deleteDiscardedFiles(dependencies, { uid, requestId, record });
  } catch (error) {
    // 終了状態は記録済みのため、消し残しは後のタスクで消す (ADR 0001「画像ストレージ」の削除の再試行)。
    logger.error("生成の後片付けのファイルを消せませんでした。再試行に回します", { uid, requestId, error });
    await dependencies.enqueueResume({ uid, requestId, purpose: "lease", delaySeconds: FAILED_STAGE_RETRY_DELAY_SECONDS });
  }
  return generationResult({ requestId, record });
}

/**
 * 終わった生成の要らなくなったファイルを消し、消し終えたことを `filesDeleted` に記録する。rejected・duplicate は元の写真・マスク・
 * 中間の切り出し画像を、saved はマスクと中間の切り出し画像を消す (元の写真は本人の図鑑のために残す)。
 * 消し終えている生成と、終わっていない・failed の生成には何もしない (何度呼んでもよい)。
 */
async function deleteDiscardedFiles(
  dependencies: GenerationDependencies,
  { uid, requestId, record }: { uid: string; requestId: string; record: GenerationRecord },
): Promise<void> {
  if (!(record.status === "rejected" || record.status === "duplicate" || record.status === "saved") || record.filesDeleted) {
    return;
  }
  await deleteFiles(dependencies.bucket, [record.status === "saved" ? undefined : record.photoPath, record.maskPath, record.cutoutPath]);
  await generationDocument({ firestore: dependencies.firestore, uid, requestId }).update({ filesDeleted: true });
}

/** 段階を 1 つ進める。 */
async function runStage(
  dependencies: GenerationDependencies,
  { uid, requestId, record, stage }: { uid: string; requestId: string; record: GenerationRecord; stage: GenerationStage },
): Promise<StageOutcome> {
  switch (stage) {
    case "safesearch":
      return runSafeSearchStage(dependencies, record);
    case "cutout":
      return runCutoutStage(dependencies, { uid, requestId, record });
    case "claude":
      return runClaudeStage(dependencies, record);
    case "classify":
      return runClassifyStage(dependencies, record);
    case "dedupe":
      return runDedupeStage(dependencies, { uid, requestId, record });
    case "judge":
      return runJudgeStage(dependencies, { uid, requestId, record });
    case "saved":
      return runSaveStage(dependencies, { uid, requestId, record });
    case "uploaded":
      throw new Error("uploaded は予約の時に済む段階で、ここには来ない");
  }
}

function rejected(rejectionReason: RejectionReason): StageOutcome {
  return { kind: "finish", update: { status: "rejected", rejectionReason } };
}

async function runSafeSearchStage(dependencies: GenerationDependencies, record: GenerationRecord): Promise<StageOutcome> {
  // Vision にも縮めた写真を送る (顔・露骨な内容の判定は長辺 1024px で足り、送る量を抑えるため)。
  const annotation = await dependencies.annotateImage(await downscalePhoto((await downloadVerifiedInput(dependencies.bucket, record)).photo));
  const rejectionReason = visionRejectionReason(annotation);
  if (rejectionReason) {
    return rejected(rejectionReason);
  }
  return {
    kind: "next",
    update: {
      visionLabels: (annotation.labelAnnotations ?? []).filter((label) => label.score >= VISION_LABEL_MINIMUM_SCORE).map((label) => label.description),
    },
  };
}

async function runCutoutStage(
  dependencies: GenerationDependencies,
  { uid, requestId, record }: { uid: string; requestId: string; record: GenerationRecord },
): Promise<StageOutcome> {
  const input = await downloadVerifiedInput(dependencies.bucket, record);
  const photo = await downscalePhoto(input.photo);
  const mask = input.mask ?? (await dependencies.segmentSubject(photo));
  const { cutoutPng, coverage } = await applyMask({ photo, mask });
  if (!cutoutPng) {
    return { kind: "finish", update: { status: "rejected", rejectionReason: "no_subject", cutoutCoverage: coverage } };
  }
  const cutoutPath = `users/${uid}/generations/${requestId}/cutout.png`;
  await dependencies.bucket.file(cutoutPath).save(cutoutPng, { contentType: "image/png", resumable: false });
  return { kind: "next", update: { cutoutPath, cutoutCoverage: coverage, maskSource: record.maskPath ? "client" : "server" } };
}

async function runClaudeStage(dependencies: GenerationDependencies, record: GenerationRecord): Promise<StageOutcome> {
  const cutoutJpeg = await flattenCutoutForDescription(await downloadFile(dependencies.bucket, record.cutoutPath!));
  const claudeUsages = [...(record.claudeUsages ?? [])];
  for (let attempt = 1; attempt <= DESCRIBE_SUBJECT_MAXIMUM_ATTEMPTS; attempt++) {
    const { output, usage } = await dependencies.describeSubject(cutoutJpeg);
    claudeUsages.push(usage);
    if (output.containsPerson) {
      return { kind: "finish", update: { status: "rejected", rejectionReason: "person_detected", claudeUsages } };
    }
    const violation = findModerationViolation(`${output.name}\n${output.encyclopediaText}\n${output.description.what}`);
    if (!violation) {
      return { kind: "next", update: { subject: output, subjectDescriptionText: canonicalDescriptionText(output.description), claudeUsages } };
    }
    logger.warn("生成した文章が禁止語の検査を通りませんでした", { attempt, violation });
  }
  return { kind: "finish", update: { status: "rejected", rejectionReason: "inappropriate_text", claudeUsages } };
}

/** Jev を呼び、入力トークン数をレコードの合計に足す値を返す。 */
async function askJevCounting(dependencies: GenerationDependencies, record: GenerationRecord, requests: Parameters<AskJev>[0][]) {
  const responses: JevResponse[] = [];
  for (const request of requests) {
    responses.push(await dependencies.askJev(request));
  }
  return { responses, jevInputTokens: (record.jevInputTokens ?? 0) + responses.reduce((sum, response) => sum + response.usage.input_tokens, 0) };
}

async function runClassifyStage(dependencies: GenerationDependencies, record: GenerationRecord): Promise<StageOutcome> {
  const master = await fetchLatestMaster(dependencies.firestore);
  const { responses, jevInputTokens } = await askJevCounting(dependencies, record, [
    buildClassifyRequest({ description: record.subject!.description, visionLabels: record.visionLabels ?? [], subjectCategories: master.subjectCategories }),
  ]);
  return { kind: "next", update: { categoryIds: topCategoryIds({ response: responses[0], count: CATEGORY_COUNT }), masterVersion: master.version, jevInputTokens } };
}

async function runDedupeStage(
  dependencies: GenerationDependencies,
  { uid, requestId, record }: { uid: string; requestId: string; record: GenerationRecord },
): Promise<StageOutcome> {
  const { firestore } = dependencies;
  const categoryIds = record.categoryIds!;
  const [monsters, generations] = await Promise.all([
    firestore.collection(`users/${uid}/monsters`).where("categoryIds", "array-contains-any", categoryIds).get(),
    firestore.collection(`users/${uid}/generations`).where("categoryIds", "array-contains-any", categoryIds).get(),
  ]);
  const candidates: DedupeCandidate[] = [
    ...monsters.docs.map((document) => ({ candidateId: document.id, description: (document.data() as MonsterDocument).subjectDescription })),
    // 保存前で止まっている生成 (判定待ち・一時的なエラーで再試行を待つ処理中) も候補にする。ロックを外した後に同じ被写体を送られても、
    // 止まっている方が再開時に dedupe を飛ばして保存し、二重に登録されないように。
    // 候補にするのは自分より先に受け付けた生成だけにする (待つ向きを後から来た方 → 先の方の一方向にし、互いに待ち合わないため)。
    ...generations.docs
      .filter((document) => {
        const generation = document.data() as GenerationRecord;
        const isEarlier =
          generation.createdAt.toMillis() < record.createdAt.toMillis() || (generation.createdAt.toMillis() === record.createdAt.toMillis() && document.id < requestId);
        return document.id !== requestId && isEarlier && (generation.status === "pending_judge" || generation.status === "processing") && generation.subject;
      })
      .map((document) => ({ candidateId: `generation:${document.id}`, description: (document.data() as GenerationRecord).subject!.description })),
  ];
  if (candidates.length === 0) {
    return { kind: "next", update: {} };
  }
  const { responses, jevInputTokens } = await askJevCounting(dependencies, record, buildDedupeRequests({ description: record.subject!.description, candidates }));
  const [sameCandidateId] = sameSubjectCandidateIds({ responses, candidates, thresholds: DEDUPE_THRESHOLDS });
  if (!sameCandidateId) {
    return { kind: "next", update: { jevInputTokens } };
  }
  if (sameCandidateId.startsWith("generation:")) {
    // 同じ被写体の生成がまだ保存前なら、結果が出るまで判定待ちにして dedupe からやり直す
    // (相手が保存されれば重複としてそのモンスターを返し、失敗すれば候補から外れて保存に進む)。
    await generationDocument({ firestore, uid, requestId }).update({ jevInputTokens });
    throw new WaitingForOtherGenerationError(`同じ被写体の生成 ${sameCandidateId} の結果を待ちます`);
  }
  return { kind: "finish", update: { status: "duplicate", jevInputTokens, monsterId: sameCandidateId } };
}

/** master とその場で作った定義の属性・技を合わせる。 */
function mergeDefinitions({ master, dynamicDefinitions }: { master: Master; dynamicDefinitions: { id: string; definition: DynamicDefinition }[] }) {
  const masterElementIds = new Set(master.elementTypes.map((elementType) => elementType.id));
  const masterMoveIds = new Set(master.moves.map((move) => move.id));
  return {
    elementTypes: [...master.elementTypes, ...dynamicDefinitions.flatMap(({ definition }) => definition.elementTypes).filter((elementType) => !masterElementIds.has(elementType.id))],
    moves: [...master.moves, ...dynamicDefinitions.flatMap(({ definition }) => definition.moves).filter((move) => !masterMoveIds.has(move.id))],
  };
}

async function runJudgeStage(
  dependencies: GenerationDependencies,
  { uid, requestId, record }: { uid: string; requestId: string; record: GenerationRecord },
): Promise<StageOutcome> {
  const { firestore } = dependencies;
  // classify で記録した版を使う (判定待ちの間に新しい版が入っても、モンスターに記録する版と判定に使った版を揃えるため)。
  const master = await fetchMaster({ firestore, version: record.masterVersion! });
  const dynamicDefinitions = await fetchDynamicDefinitions(firestore);
  const { elementTypes, moves } = mergeDefinitions({ master, dynamicDefinitions });
  const description = record.subject!.description;
  const { responses, jevInputTokens } = await askJevCounting(dependencies, record, [buildJudgeRequest({ description, elementTypes, moves, statGrades: master.statGrades })]);
  const judged = readJudgeResponse({ response: responses[0], statGrades: master.statGrades });
  let elementTypeIds = selectElementTypeIds({ elementProbabilities: judged.elementProbabilities, master });
  let judgedMoves = moves;
  let update: Partial<GenerationRecord> = { jevInputTokens };
  let definitionIds = dynamicDefinitions.map(({ id }) => id);
  if (elementTypeIds.length === 0) {
    const resolved = await resolveNewElementType(dependencies, {
      uid,
      requestId,
      record: { ...record, jevInputTokens },
      master,
      elementTypes,
      dynamicDefinitions,
      elementProbabilities: judged.elementProbabilities,
    });
    elementTypeIds = [resolved.elementTypeId];
    judgedMoves = [...moves, ...resolved.createdDefinition.moves];
    definitionIds = [...definitionIds, ...(resolved.createdDefinition.moves.length > 0 ? [resolved.elementTypeId] : [])];
    update = { ...update, ...resolved.update };
  }
  return {
    kind: "next",
    update: {
      ...update,
      judgement: {
        elementTypeIds,
        learnset: buildLearnset({ elementTypeIds, moveProbabilitiesByElement: judged.moveProbabilitiesByElement, moves: judgedMoves }),
        baseStats: baseStatsFromStatGrades({ statGradeIds: judged.statGradeIds, master }),
        individualValues: individualValuesFromDescription(record.subjectDescriptionText!),
        // その場で作った定義のうち、このモンスターの属性を持つものだけを参照として残す (定義の ID は属性の ID と同じ)。
        definitionIds: definitionIds.filter((definitionId) => elementTypeIds.includes(definitionId)),
      },
      // 生まれるモンスターの ID を先に決めて残す。保存の段階を再試行しても同じ ID の 1 体だけになるように。
      monsterId: firestore.collection(`users/${uid}/monsters`).doc().id,
    },
  };
}

/**
 * どの属性にも当てはまらない時に、新しい属性を作るか既存の属性に寄せる (ADR 0001「master に無い属性・技」)。
 * Claude の提案が範囲外・禁止語に当たる・上限に達した時は、Jev の当てはまりが最も高い既存の属性を使う。
 */
async function resolveNewElementType(
  dependencies: GenerationDependencies,
  {
    uid,
    requestId,
    record,
    master,
    elementTypes,
    dynamicDefinitions,
    elementProbabilities,
  }: {
    uid: string;
    requestId: string;
    record: GenerationRecord;
    master: Master;
    elementTypes: MasterElementType[];
    dynamicDefinitions: { id: string; definition: DynamicDefinition }[];
    elementProbabilities: Record<string, number>;
  },
): Promise<{ elementTypeId: string; createdDefinition: { moves: MasterMove[] }; update: Partial<GenerationRecord> }> {
  const [bestExistingElementTypeId] = Object.entries(elementProbabilities).sort(([, left], [, right]) => right - left)[0];
  const reuse = ({ elementTypeId, update }: { elementTypeId: string; update: Partial<GenerationRecord> }) => ({ elementTypeId, createdDefinition: { moves: [] }, update });
  const fallback = (update: Partial<GenerationRecord>) => reuse({ elementTypeId: bestExistingElementTypeId, update });

  let proposal = record.elementProposal;
  const claudeUsages = [...(record.claudeUsages ?? [])];
  if (!proposal) {
    const proposed = await dependencies.proposeElement({ description: record.subject!.description, existingElementNames: elementTypes.map((elementType) => elementType.displayName) });
    proposal = proposed.output;
    claudeUsages.push(proposed.usage);
    // Jev が答えず判定待ちになっても、再試行で Claude を呼び直さないよう先に書く。
    await generationDocument({ firestore: dependencies.firestore, uid, requestId }).update({
      elementProposal: proposal,
      claudeUsages,
    });
  }
  const baseUpdate: Partial<GenerationRecord> = { elementProposal: proposal, claudeUsages };
  const violation =
    proposalRangeViolation(proposal) ??
    findModerationViolation([proposal.element.displayName, proposal.element.description, ...proposal.moves.map((move) => move.displayName)].join("\n"));
  if (violation) {
    logger.warn("新しい属性の提案を使いません", { violation });
    return fallback(baseUpdate);
  }
  const sameName = elementTypes.find((elementType) => elementType.displayName === proposal.element.displayName);
  if (sameName) {
    return reuse({ elementTypeId: sameName.id, update: baseUpdate });
  }
  const dynamicElementTypes = dynamicDefinitions.flatMap(({ definition }) => definition.elementTypes);
  let jevInputTokens = record.jevInputTokens ?? 0;
  if (dynamicElementTypes.length > 0) {
    const response = await dependencies.askJev(
      buildSameDefinitionRequest({ proposal: { id: "proposed", displayName: proposal.element.displayName, description: proposal.element.description }, existingElementTypes: dynamicElementTypes }),
    );
    jevInputTokens += response.usage.input_tokens;
    const same = dynamicElementTypes.find((elementType) => {
      const answer = response.answers[`same_element__${elementType.id}`];
      return answer?.type === "noul" && answer.noul >= SAME_DEFINITION_PROBABILITY_THRESHOLD;
    });
    if (same) {
      return reuse({ elementTypeId: same.id, update: { ...baseUpdate, jevInputTokens } });
    }
  }
  const elementTypeId = `element_${fnv1a32(proposal.element.displayName).toString(16)}`;
  const definition: DynamicDefinition & { effects: { id: string; displayName: string; kind: string; colorHex: string }[] } = {
    version: 1,
    elementTypes: [{ id: elementTypeId, displayName: proposal.element.displayName, description: proposal.element.description }],
    moves: proposal.moves.map((move, index) => ({
      id: `${elementTypeId}_${index + 1}`,
      displayName: move.displayName,
      elementTypeId,
      power: move.power,
      powerPoints: move.powerPoints,
      category: "attack",
      effectId: `${elementTypeId}_particle`,
      learnableLevelMinimum: PROPOSED_MOVE_TIERS[index].learnableLevelMinimum,
      learnableLevelMaximum: PROPOSED_MOVE_TIERS[index].learnableLevelMaximum,
    })),
    effects: [{ id: `${elementTypeId}_particle`, displayName: `${proposal.element.displayName}のパーティクル`, kind: "particle", colorHex: proposal.element.colorHex }],
  };
  const created = await dependencies.firestore.runTransaction(async (transaction: Transaction) => {
    const definitionDocument = dependencies.firestore.doc(`definitions/${elementTypeId}`);
    const counterDocument = dependencies.firestore.doc("definitionCounters/global");
    const [definitionSnapshot, counterSnapshot] = await Promise.all([transaction.get(definitionDocument), transaction.get(counterDocument)]);
    if (definitionSnapshot.exists) {
      return "exists" as const;
    }
    const elementCount = master.elementTypes.length + ((counterSnapshot.get("elementCount") as number | undefined) ?? 0);
    const moveCount = master.moves.length + ((counterSnapshot.get("moveCount") as number | undefined) ?? 0);
    if (elementCount + 1 > ELEMENT_TYPE_LIMIT || moveCount + definition.moves.length > MOVE_LIMIT) {
      return "limit" as const;
    }
    transaction.create(definitionDocument, { ...definition, createdAt: Timestamp.fromDate(dependencies.now()) });
    transaction.set(counterDocument, { elementCount: FieldValue.increment(1), moveCount: FieldValue.increment(definition.moves.length) }, { merge: true });
    return "created" as const;
  });
  if (created === "limit") {
    logger.warn("属性・技の上限に達したため、新しい属性を作りません");
    return fallback({ ...baseUpdate, jevInputTokens });
  }
  // "exists" は同じ名前の定義を別の生成が先に作った時で、その定義の技は既存の定義の一覧に含まれていないため、作った定義の技として返す。
  return { elementTypeId, createdDefinition: { moves: definition.moves }, update: { ...baseUpdate, jevInputTokens } };
}

async function runSaveStage(
  dependencies: GenerationDependencies,
  { uid, requestId, record }: { uid: string; requestId: string; record: GenerationRecord },
): Promise<StageOutcome> {
  const { firestore, bucket } = dependencies;
  const monsterId = record.monsterId!;
  const artPath = `monsters/${monsterId}/art.png`;
  // 絵を先に置く。保存のトランザクションの前に落ちても、再試行が同じ ID で置き直す (同じ中身の上書きで冪等)。
  if (!(await bucket.file(artPath).exists())[0]) {
    await bucket.file(record.cutoutPath!).copy(bucket.file(artPath));
  }
  const subject = record.subject!;
  const judgement = record.judgement!;
  const monster: MonsterDocument = {
    definition: {
      id: monsterId,
      sourcePhotoReference: record.photoPath,
      name: subject.name,
      encyclopediaText: subject.encyclopediaText,
      elementTypeIds: judgement.elementTypeIds,
      learnset: judgement.learnset,
      baseStats: judgement.baseStats,
      individualValues: judgement.individualValues,
      statCalculationVersion: CURRENT_STAT_CALCULATION_VERSION,
      masterVersion: record.masterVersion!,
    },
    level: 1,
    experience: 0,
    artPath,
    decoration: subject.decoration,
    decorationVersion: DECORATION_VERSION,
    subjectDescription: subject.description,
    categoryIds: record.categoryIds!,
    definitionIds: judgement.definitionIds,
    generationRequestId: requestId,
    createdAt: Timestamp.fromDate(dependencies.now()),
  };
  const monsterDocument = firestore.doc(`users/${uid}/monsters/${monsterId}`);
  await firestore.runTransaction(async (transaction) => {
    if (!(await transaction.get(monsterDocument)).exists) {
      transaction.create(monsterDocument, monster);
    }
  });
  // 中間のファイルは saved を記録した後に finishGeneration が消す (消すのに失敗しても保存の成功を失敗にしないため)。
  return { kind: "finish", update: { status: "saved", completedStage: "saved" } };
}
