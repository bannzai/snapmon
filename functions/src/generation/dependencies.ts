// 本番 (と Emulator) の生成が使う外部の資源をまとめる。テストはここを通らず、pipeline.ts の GenerationDependencies にモックを渡す。

import { getFirestore } from "firebase-admin/firestore";
import { getFunctions } from "firebase-admin/functions";
import { getStorage } from "firebase-admin/storage";
import { GoogleAuth } from "google-auth-library";

import { createAnthropicClient } from "../anthropic";
import { typesafeApiKey } from "../secrets";
import { createDescribeSubject, createProposeElement } from "./claude";
import { createSegmentSubject, SEGMENTATION_MODEL_PATH } from "./cutout";
import { createAskJev } from "./jev";
import type { GenerationDependencies } from "./pipeline";
import { createAnnotateImage } from "./vision";

/**
 * 写真と絵を置くバケット。snapmon-prod は既定のバケット (`snapmon-prod.firebasestorage.app`) を作らず `snapmon-prod-storage` を使う
 * (.claude/rules/firebase-config-files.md)。Emulator のテストも同じ名前のバケットに Rules を当てている (test/emulator/storage_rules.test.ts)。
 */
const STORAGE_BUCKET_NAME = "snapmon-prod-storage";

/** 再試行のタスクのキューの関数名 (index.ts の export と同じ名前)。 */
const RESUME_QUEUE_FUNCTION_NAME = "locations/asia-northeast1/functions/resumeGeneration";

let anthropicClient: ReturnType<typeof createAnthropicClient> | undefined;
let segmentSubject: ReturnType<typeof createSegmentSubject> | undefined;
let accessTokenClient: GoogleAuth | undefined;

/**
 * 本番の資源で生成の依存を作る。Claude のクライアントと切り出しのモデルは、最初に使う時に作る
 * (どちらも作るのに時間がかかり、インスタンスの中で使い回すため)。
 */
export function createProductionDependencies(): GenerationDependencies {
  segmentSubject ??= createSegmentSubject({ modelPath: SEGMENTATION_MODEL_PATH });
  accessTokenClient ??= new GoogleAuth({ scopes: ["https://www.googleapis.com/auth/cloud-platform"] });
  const getAnthropicClient = () => (anthropicClient ??= createAnthropicClient({ env: process.env, fetchFunction: fetch }));
  return {
    firestore: getFirestore(),
    bucket: getStorage().bucket(STORAGE_BUCKET_NAME),
    annotateImage: createAnnotateImage({
      getAccessToken: async () => {
        const token = await accessTokenClient!.getAccessToken();
        if (!token) {
          throw new Error("Cloud Vision のアクセストークンを取得できませんでした");
        }
        return token;
      },
      fetchFunction: fetch,
    }),
    segmentSubject,
    describeSubject: createDescribeSubject(getAnthropicClient),
    proposeElement: createProposeElement(getAnthropicClient),
    // Secret は使う時に読む (入力の検査で弾く呼び出しと、Secret の無い Emulator で読まないため)。
    askJev: (request) => createAskJev({ apiKey: typesafeApiKey.value(), fetchFunction: fetch })(request),
    enqueueResume: async ({ uid, requestId, delaySeconds }) => {
      await getFunctions().taskQueue(RESUME_QUEUE_FUNCTION_NAME).enqueue({ uid, requestId }, { scheduleDelaySeconds: delaySeconds });
    },
    now: () => new Date(),
  };
}
