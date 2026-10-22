import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { onTaskDispatched } from "firebase-functions/v2/tasks";

import { typesafeApiKey } from "../secrets";
import { createProductionDependencies } from "./dependencies";
import { type GenerationDependencies, GenerationRequestError, resumeGeneration, startGeneration } from "./pipeline";
import type { GenerationResult } from "./records";

/** 要求 ID の形 (クライアントが要求ごとに作る UUID)。 */
const REQUEST_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/**
 * `generate` の受け取る data を検査し、生成を始める (callable の本体。テストは依存を差し替えて直接呼ぶ)。
 *
 * 受け取る data: `{ requestId: string (UUID), photoPath: string, maskPath?: string }`。
 * `photoPath` は `users/{uid}/photos/{requestId}`、`maskPath` は `users/{uid}/masks/{requestId}` でなければならない
 * (Admin SDK は Storage の Rules を通らないため、他人の写真を読ませないようパスを本人と要求 ID に固定する)。
 * 返す値: `GenerationResult`。1 日の上限・生成中のロックに当たる時は `resource-exhausted` / `failed-precondition` を投げる。
 */
export async function handleGenerateRequest(dependencies: GenerationDependencies, request: Pick<CallableRequest, "auth" | "data">): Promise<GenerationResult> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "匿名ログインの後に呼んでください");
  }
  if (request.auth.token.ageVerified !== true) {
    throw new HttpsError("permission-denied", "年齢の確認の後に呼んでください");
  }
  const uid = request.auth.uid;
  const { requestId, photoPath, maskPath } = (request.data ?? {}) as { requestId?: unknown; photoPath?: unknown; maskPath?: unknown };
  if (typeof requestId !== "string" || !REQUEST_ID_PATTERN.test(requestId)) {
    throw new HttpsError("invalid-argument", "requestId を UUID の文字列で渡してください");
  }
  if (photoPath !== `users/${uid}/photos/${requestId}`) {
    throw new HttpsError("invalid-argument", "photoPath は users/{uid}/photos/{requestId} にしてください");
  }
  if (maskPath !== undefined && maskPath !== null && maskPath !== `users/${uid}/masks/${requestId}`) {
    throw new HttpsError("invalid-argument", "maskPath は users/{uid}/masks/{requestId} にしてください");
  }
  try {
    return await startGeneration(dependencies, { uid, requestId, photoPath, maskPath: typeof maskPath === "string" ? maskPath : null });
  } catch (error) {
    if (error instanceof GenerationRequestError) {
      throw new HttpsError(error.code === "another_generation_in_progress" ? "failed-precondition" : "resource-exhausted", error.message, { reason: error.code });
    }
    throw error;
  }
}

/**
 * 生成を動かす関数 (callable と再試行のタスク) の共通の設定。
 * timeoutSeconds 300: 予約の期間 (pipeline.ts の 10 分) より短くし、元の実行と再試行が同時に API を呼ばないため (ADR 0001 の 5 分)。
 * memory 4GiB: 切り出しのモデルの推論で常駐メモリが 2.6 GB まで増えた実測 (ADR 0002) に余裕を持たせた。
 * concurrency 1: 2nd gen の既定 (CPU が 1 以上なら 80) のままだと、1 つのインスタンスで推論が重なってメモリが足りなくなるため。
 * cpu 2: 推論 (onnxruntime-node) を 2 スレッドで回す。メモリ 4GiB の既定の CPU に頼らず明示した。
 */
const GENERATION_FUNCTION_OPTIONS = { timeoutSeconds: 300, memory: "4GiB" as const, concurrency: 1, cpu: 2, secrets: [typesafeApiKey] };

/** 写真からモンスターを生成する callable (App Check 必須)。設計は pipeline.ts の冒頭。 */
export const generate = onCall({ ...GENERATION_FUNCTION_OPTIONS, enforceAppCheck: true }, (request) => handleGenerateRequest(createProductionDependencies(), request));

/**
 * 生成の再試行のタスク (Cloud Tasks のキュー)。判定待ちの生成を 1 時間おきに続きから進め、予約が切れた生成を引き継ぐ。
 * 積むのは pipeline.ts だけで、間隔はタスクを積む時の `scheduleDelaySeconds` で決める。
 * retryConfig: 段階の失敗は pipeline.ts が新しいタスクを積んで再試行するため、Cloud Tasks の再試行はタスクの配送の失敗
 * (インスタンスの起動の失敗等) だけを受け持つ。回数は直して再試行の既定 3 回 (~/.claude/documents/rules/retry-limit-and-failure-classification.md)。
 * rateLimits: 同時に動く再試行を maxInstances (index.ts の 10) に収める。
 */
export const resumeGenerationTask = onTaskDispatched<{ uid: string; requestId: string }>(
  {
    ...GENERATION_FUNCTION_OPTIONS,
    retryConfig: { maxAttempts: 3, minBackoffSeconds: 60 },
    rateLimits: { maxConcurrentDispatches: 10 },
  },
  async (request) => {
    await resumeGeneration(createProductionDependencies(), request.data);
  },
);
