// アカウントの削除。消すデータと手順の説明は docs/AccountDeletion.md、置き場は .claude/rules/firestore.md と ADR 0001「画像ストレージ」。

import { type Auth, getAuth } from "firebase-admin/auth";
import { type Firestore, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getFunctions } from "firebase-admin/functions";
import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { onTaskDispatched } from "firebase-functions/v2/tasks";

import { STORAGE_BUCKET_NAME } from "./generation/dependencies";
import type { StorageBucket } from "./generation/pipeline";

/** 消し残したファイルと `users/{uid}` を消すタスクの中身。 */
export interface AccountFileDeletionTask {
  /** 削除したユーザー。Storage の `users/{uid}/` の配下と Firestore の `users/{uid}` を消す。 */
  uid: string;
  /** そのユーザーのモンスターの絵 (`monsters/{monsterId}/art.png`)。Firestore を消した後は引けないため、タスクに持たせる。 */
  artPaths: string[];
}

/** アカウントの削除が使う外部の資源。callable は本番の実装を、テストは Emulator の資源と差し替えたタスクの積み方を渡す。 */
export interface AccountDeletionDependencies {
  /** Firestore。 */
  firestore: Firestore;
  /** 写真・絵を置くバケット。 */
  bucket: StorageBucket;
  /** Firebase Authentication。 */
  auth: Auth;
  /** ファイルか、Auth を消した後の `users/{uid}` を消し残した時に、消すタスク (deleteAccountLeftovers) を積む。 */
  enqueueFileDeletion: (task: AccountFileDeletionTask) => Promise<void>;
  /** 現在時刻。 */
  now: () => Date;
}

/** 削除の受付を断る理由。callable は HttpsError に変える。 */
export class AccountDeletionRequestError extends Error {}

/** 消し残したファイルを消すタスクのキューの関数名 (index.ts の export と同じ名前)。 */
const FILE_DELETION_QUEUE_FUNCTION_NAME = "locations/asia-northeast1/functions/deleteAccountFiles";

/** モンスターの絵のパスの形。タスクの中身から消すパスを、この形のものだけに限る。 */
const ART_PATH_PATTERN = /^monsters\/[^/]+\/art\.png$/;

/**
 * [uid] のアカウントを消す (callable の本体。テストは依存を差し替えて直接呼ぶ)。
 *
 * 消す順: Storage (元の写真・マスク・中間の切り出し・モンスターの絵) → 本人の通報・ブロック → `users/{uid}` のサブコレクション →
 * Auth のユーザー → `users/{uid}`。`users/{uid}` に削除の始まりの印 (`accountDeletionStartedAt`) を最後まで残し、
 * 削除の途中に生成 (pipeline.ts の startGeneration) が始まらないようにする。Auth を消すまでに失敗した時は、もう一度呼べば続きから消せる (冪等)。
 * Storage を消すのに失敗した時は、消すタスクを積んでから先へ進む (ADR 0001「画像ストレージ」の削除の再試行)。
 * Auth を消した後に `users/{uid}` を消すのに失敗した時も、同じタスクを積む (クライアントはもう呼び直せないため)。
 * 生成の途中 (生成中ロックが期限内) は断る (消し終えた後に生成がモンスターを書いて残るため)。
 */
export async function deleteAccountData(dependencies: AccountDeletionDependencies, { uid }: { uid: string }): Promise<void> {
  const { firestore, bucket, auth } = dependencies;
  const userDocument = firestore.doc(`users/${uid}`);
  await firestore.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userDocument);
    const lock = userSnapshot.get("generationLock") as { expiresAt: Timestamp } | undefined;
    if (lock && lock.expiresAt.toMillis() > dependencies.now().getTime()) {
      throw new AccountDeletionRequestError("モンスターの生成が終わってから、もう一度削除してください");
    }
    if (userSnapshot.get("accountDeletionStartedAt") === undefined) {
      transaction.set(userDocument, { accountDeletionStartedAt: Timestamp.fromDate(dependencies.now()) }, { merge: true });
    }
  });

  // 絵は図鑑のモンスターと、保存の後に failed になった生成 (pipeline.ts の deleteDiscardedFiles) が持つ。どちらも本人のモンスターの ID
  const [monsters, generations] = await Promise.all([userDocument.collection("monsters").get(), userDocument.collection("generations").get()]);
  const artPaths = [
    ...new Set([
      ...monsters.docs.map((monster) => monster.get("artPath") as string | undefined),
      ...generations.docs.map((generation) => {
        const monsterId = generation.get("monsterId") as string | undefined;
        return monsterId ? `monsters/${monsterId}/art.png` : undefined;
      }),
    ]),
  ].filter((path): path is string => !!path && ART_PATH_PATTERN.test(path));
  try {
    await deleteAccountFiles(bucket, { uid, artPaths });
  } catch (error) {
    logger.error("アカウントのファイルを消せませんでした。再試行に回します", { uid, error });
    await dependencies.enqueueFileDeletion({ uid, artPaths });
  }

  await Promise.all(
    [
      firestore.collection("reports").where("reporterUid", "==", uid),
      firestore.collection("blocks").where("blockerUid", "==", uid),
    ].map(async (query) => {
      const snapshot = await query.get();
      await Promise.all(snapshot.docs.map((document) => document.ref.delete()));
    }),
  );
  for (const collection of await userDocument.listCollections()) {
    await firestore.recursiveDelete(collection);
  }
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    // 前の呼び出しで Auth まで消し終えていた
    if ((error as { code?: string }).code !== "auth/user-not-found") {
      throw error;
    }
  }
  try {
    await userDocument.delete();
  } catch (error) {
    // Auth を消した後は、クライアントはトークンを更新できず呼び直せないため、サーバーのタスクで消し切る
    logger.error("users/{uid} を消せませんでした。再試行に回します", { uid, error });
    await dependencies.enqueueFileDeletion({ uid, artPaths: [] });
  }
}

/**
 * [uid] の Auth のユーザーが消えていたら (削除の後も ID トークンは期限の 1 時間まで通るため、別の端末から呼ばれた)、
 * その uid が削除の後に Storage に置いたファイル (`users/{uid}/` の配下) を消し、`unauthenticated` の HttpsError を投げる。
 * 消えていなければ何もしない。生成のようにアカウントのデータを新しく書く callable の最初に呼ぶ。
 */
export async function rejectDeletedAccount({ auth, bucket, uid }: { auth: Auth; bucket: StorageBucket; uid: string }): Promise<void> {
  try {
    await auth.getUser(uid);
    return;
  } catch (error) {
    if ((error as { code?: string }).code !== "auth/user-not-found") {
      throw error;
    }
  }
  await deleteAccountFiles(bucket, { uid, artPaths: [] });
  throw new HttpsError("unauthenticated", "このアカウントは削除されています");
}

/** [uid] の `users/{uid}/` の配下のファイルと [artPaths] の絵を消す。無いファイルは無視する (何度呼んでもよい)。 */
export async function deleteAccountFiles(bucket: StorageBucket, { uid, artPaths }: AccountFileDeletionTask): Promise<void> {
  await bucket.deleteFiles({ prefix: `users/${uid}/` });
  await Promise.all(artPaths.filter((path) => ART_PATH_PATTERN.test(path)).map((path) => bucket.file(path).delete({ ignoreNotFound: true })));
}

/**
 * 本人のアカウントを消す callable (App Check 必須)。受け取る data は無い。返す値: `{ deleted: true }`。
 * 年齢の確認のクレームは求めない (確認を通らなかった人も、残ったデータを消せるようにするため)。
 * Admin SDK で消すため、クライアントの最近のログインは要らない。Sign in with Apple の連携の取り消し (Apple のトークンの revoke) は、
 * クライアントが呼ぶ前に行う (lib/firebase/account.dart)。
 */
export const deleteAccount = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "ログインの後に呼んでください");
  }
  try {
    await deleteAccountData(
      {
        firestore: getFirestore(),
        bucket: getStorage().bucket(STORAGE_BUCKET_NAME),
        auth: getAuth(),
        enqueueFileDeletion: (task) => getFunctions().taskQueue(FILE_DELETION_QUEUE_FUNCTION_NAME).enqueue(task),
        now: () => new Date(),
      },
      { uid: request.auth.uid },
    );
  } catch (error) {
    if (error instanceof AccountDeletionRequestError) {
      throw new HttpsError("failed-precondition", error.message);
    }
    throw error;
  }
  return { deleted: true };
});

/**
 * 削除の時に消し残したファイルと `users/{uid}` を消すタスク (Cloud Tasks のキュー) の本体。何度呼んでもよい。
 * 削除の途中に呼ばれて `users/{uid}` を先に消しても、生成とバトルの開始は `ageAccepted` が無いと受け付けないため、データは増えない。
 */
export async function deleteAccountLeftovers({ firestore, bucket }: { firestore: Firestore; bucket: StorageBucket }, task: AccountFileDeletionTask): Promise<void> {
  await deleteAccountFiles(bucket, task);
  await firestore.doc(`users/${task.uid}`).delete();
}

/**
 * [deleteAccountLeftovers] のタスク。失敗したら投げて、Cloud Tasks に再試行させる。
 * retryConfig: Storage・Firestore の障害が数時間続いても消し終えるよう、最大 1 時間の間隔で 24 回 (1 日分) にした。
 */
export const deleteAccountFilesTask = onTaskDispatched<AccountFileDeletionTask>(
  { retryConfig: { maxAttempts: 24, minBackoffSeconds: 60, maxBackoffSeconds: 3_600 } },
  async (request) => {
    await deleteAccountLeftovers({ firestore: getFirestore(), bucket: getStorage().bucket(STORAGE_BUCKET_NAME) }, request.data);
  },
);
