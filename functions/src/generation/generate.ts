import { getAuth } from "firebase-admin/auth";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";
import { onTaskDispatched } from "firebase-functions/v2/tasks";

import { rejectDeletedAccount } from "../account";
import { ENFORCE_APP_CHECK } from "../app_check";
import { typesafeApiKey } from "../secrets";
import { createProductionDependencies } from "./dependencies";
import { type GenerationDependencies, GenerationRequestError, resumeGeneration, type ResumeTask, startGeneration } from "./pipeline";
import type { GenerationResult, MaskSource } from "./records";

/** 要求 ID の形 (クライアントが要求ごとに作る UUID)。 */
const REQUEST_ID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/**
 * `generate` の受け取る data を検査し、生成を始める (callable の本体。テストは依存を差し替えて直接呼ぶ)。
 *
 * 受け取る data: `{ requestId: string (UUID), photoPath: string, maskPath?: string, maskSource?: "ios_subject" | "crop" | "none" }`。
 * `photoPath` は `users/{uid}/photos/{requestId}`、`maskPath` は `users/{uid}/masks/{requestId}` でなければならない
 * (Admin SDK は Storage の Rules を通らないため、他人の写真を読ませないようパスを本人と要求 ID に固定する)。
 * `maskSource` は `maskPath` を渡す時は `ios_subject` か `crop` を必ず渡し、渡さない時は省くか `none` にする
 * (2026-10-28 より前の端末は `maskPath` も `maskSource` も送らないため、どちらも無い呼び出しはマスク無しとして受け付ける)。
 * 返す値: `GenerationResult`。1 日の上限・生成中のロックに当たる時は `resource-exhausted` / `failed-precondition` を投げる。
 */
export async function handleGenerateRequest(dependencies: GenerationDependencies, request: Pick<CallableRequest, "auth" | "data">): Promise<GenerationResult> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "匿名ログインの後に呼んでください");
  }
  const uid = request.auth.uid;
  const { requestId, photoPath, maskPath, maskSource } = (request.data ?? {}) as {
    requestId?: unknown;
    photoPath?: unknown;
    maskPath?: unknown;
    maskSource?: unknown;
  };
  if (typeof requestId !== "string" || !REQUEST_ID_PATTERN.test(requestId)) {
    throw new HttpsError("invalid-argument", "requestId を UUID の文字列で渡してください");
  }
  if (photoPath !== `users/${uid}/photos/${requestId}`) {
    throw new HttpsError("invalid-argument", "photoPath は users/{uid}/photos/{requestId} にしてください");
  }
  if (maskPath !== undefined && maskPath !== null && maskPath !== `users/${uid}/masks/${requestId}`) {
    throw new HttpsError("invalid-argument", "maskPath は users/{uid}/masks/{requestId} にしてください");
  }
  const hasMask = typeof maskPath === "string";
  if (hasMask ? maskSource !== "ios_subject" && maskSource !== "crop" : maskSource !== undefined && maskSource !== null && maskSource !== "none") {
    throw new HttpsError("invalid-argument", "maskSource は maskPath を渡す時は ios_subject か crop、渡さない時は none にしてください");
  }
  try {
    return await startGeneration(dependencies, {
      uid,
      requestId,
      photoPath,
      maskPath: hasMask ? maskPath : null,
      maskSource: hasMask ? (maskSource as MaskSource) : "none",
    });
  } catch (error) {
    if (error instanceof GenerationRequestError) {
      throw new HttpsError(error.code.startsWith("daily_limit") ? "resource-exhausted" : "failed-precondition", error.message, { reason: error.code });
    }
    throw error;
  }
}

/**
 * 生成を動かす関数 (callable と再試行のタスク) の共通の設定。
 * timeoutSeconds 300: 予約の期間 (pipeline.ts の 10 分) より短くし、元の実行と再試行が同時に API を呼ばないため (ADR 0001 の 5 分)。
 * memory 1GiB: 1 つの要求が長辺 1024px の写真を展開した RGB・RGBA (約 7 MB) と sharp の作業領域を持つ。cpu と concurrency は
 * firebase-functions の既定 (メモリ 2GB 以下は CPU 1、CPU 1 以上は同時に 80 要求。lib/v2/options.d.ts の cpu・concurrency の説明と
 * https://firebase.google.com/docs/functions/manage-functions ) にし、1 つのインスタンスで要求が重なっても足りる値として置いた
 * (待ち時間の大半は外部の API の応答待ち)。本番のメモリの使用量は未実測で、デプロイ後に Cloud Run のメトリクスで見直す (ADR 0002)。
 */
const GENERATION_FUNCTION_OPTIONS = { timeoutSeconds: 300, memory: "1GiB" as const, secrets: [typesafeApiKey] };

/** 写真からモンスターを生成する callable (App Check の強制は app_check.ts)。設計は pipeline.ts の冒頭。 */
export const generate = onCall({ ...GENERATION_FUNCTION_OPTIONS, enforceAppCheck: ENFORCE_APP_CHECK }, async (request) => {
  const dependencies = createProductionDependencies();
  if (request.auth) {
    await rejectDeletedAccount({ auth: getAuth(), bucket: dependencies.bucket, uid: request.auth.uid });
  }
  return handleGenerateRequest(dependencies, request);
});

/**
 * 生成の再試行のタスク (Cloud Tasks のキュー)。判定待ちの生成を 1 時間おきに続きから進め、予約が切れた生成を引き継ぐ。
 * 積むのは pipeline.ts だけで、間隔はタスクを積む時の `scheduleDelaySeconds` で決める。
 * retryConfig: 段階の失敗は pipeline.ts が新しいタスクを積んで再試行し、タスクは成功で終えるため、Cloud Tasks の再試行は
 * 予約を取る前の失敗 (Firestore・Cloud Tasks の障害、インスタンスの起動の失敗) だけを受け持つ。judge のタスクは次のタスクを自分で
 * 積むため、再試行を使い切ると判定待ちが進まなくなる。障害が数時間続いても使い切らないよう、10 回・最大 1 時間の間隔にした。
 * rateLimits: 同時に動く再試行を maxInstances (index.ts の 10) に収める。
 */
export const resumeGenerationTask = onTaskDispatched<ResumeTask>(
  {
    ...GENERATION_FUNCTION_OPTIONS,
    retryConfig: { maxAttempts: 10, minBackoffSeconds: 60, maxBackoffSeconds: 3_600 },
    rateLimits: { maxConcurrentDispatches: 10 },
  },
  async (request) => {
    await resumeGeneration(createProductionDependencies(), request.data);
  },
);
