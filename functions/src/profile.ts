// プロフィールのアイコン。端末が `users/{uid}/iconUploads/{uploadId}` に置いた写真を、生成と同じ Cloud Vision の検査
// (露骨な内容・人の顔。generation/vision.ts の visionRejectionReason) に通し、通った写真だけを正方形に縮めて
// `users/{uid}/icons/{uploadId}.png` (ログインした全員が読める) に置き、`users/{uid}.iconPath` に持つ。
// 置き場は .claude/rules/firestore.md。`users/{uid}/` の配下のため、アカウントの削除 (account.ts) が自動で消す。

import { type Auth, getAuth } from "firebase-admin/auth";
import { type DocumentSnapshot, type Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import sharp from "sharp";

import { authUserExists, rejectDeletedAccount } from "./account";
import { ENFORCE_APP_CHECK } from "./app_check";
import { requireSignedInUid } from "./battle";
import { downscalePhoto } from "./generation/cutout";
import { createProductionDependencies } from "./generation/dependencies";
import { downloadFile, type StorageBucket } from "./generation/pipeline";
import { type AnnotateImage, visionRejectionLogFields, visionRejectionReason } from "./generation/vision";
import { isDocumentId } from "./pvp_rules";

/**
 * アイコンの一辺 (px)。画面に出す大きさ (対戦タブ・対戦画面・プロフィールの 32〜96 論理 px) を 3 倍の画面でも粗く見せない大きさにし、
 * PNG が数十 KB に収まるため。
 */
export const PROFILE_ICON_SIDE = 256;

/** 端末がアイコンにする写真を置くパス (本人だけが置ける。firebase/storage.rules)。 */
export function profileIconUploadPath({ uid, uploadId }: { uid: string; uploadId: string }): string {
  return `users/${uid}/iconUploads/${uploadId}`;
}

/** 検査を通ったアイコンのパス (ログインした全員が読め、書くのは Functions だけ)。差し替えるたびに別のパスにし、古い絵を読み続けさせない。 */
export function profileIconPath({ uid, uploadId }: { uid: string; uploadId: string }): string {
  return `users/${uid}/icons/${uploadId}.png`;
}

/** アイコンの登録が使う外部の資源。callable は本番の実装を、テストは Emulator の資源とモックの Vision を渡す。 */
export interface ProfileIconDependencies {
  /** Firestore。 */
  firestore: Firestore;
  /** Firebase Authentication (まだ `users/{uid}` が無い新しいユーザーと、削除を消し終えたユーザーを見分ける)。 */
  auth: Auth;
  /** 写真とアイコンを置くバケット。 */
  bucket: StorageBucket;
  /** Cloud Vision。 */
  annotateImage: AnnotateImage;
}

/**
 * `users/{uid}` [userSnapshot] が、削除の途中でも削除済みでもないことを確かめる。満たさない時は failed-precondition を投げる。
 * 表示名 (pvp.ts の setDisplayName) と同じく、まだモンスターを生成していないユーザーには `users/{uid}` が無いため、Auth のユーザーで見分ける。
 */
async function requireActiveAccount({
  auth,
  uid,
  userSnapshot,
}: {
  auth: Auth;
  uid: string;
  userSnapshot: DocumentSnapshot;
}): Promise<void> {
  if (userSnapshot.get("accountDeletionStartedAt") !== undefined || (!userSnapshot.exists && !(await authUserExists({ auth, uid })))) {
    throw new HttpsError("failed-precondition", "アカウントの削除が進んでいるか、アカウントが見つかりません");
  }
}

/**
 * [uid] が置いた写真 [uploadId] を検査してアイコンにし、保存したアイコンのパスを返す (callable の本体。テストは依存を差し替えて直接呼ぶ)。
 *
 * 露骨な内容・人の顔が写る写真は、写真を消して invalid-argument (利用者に出す文言) を投げる (他のユーザーに見せる画像のため。
 * DIRECTION.md「必要な機能」の不適切な画像・人物の扱い)。写真は中央を正方形に切り取って [PROFILE_ICON_SIDE] px の PNG にする。
 * 前のアイコンと置いた写真は、新しいアイコンを `users/{uid}.iconPath` に書いた後に消す。
 * 同じ [uploadId] で呼び直した時は、保存済みならそのパスを返す (冪等。Vision を呼び直さない)。写真が無い時は not-found。
 */
export async function setProfileIconData(
  dependencies: ProfileIconDependencies,
  { uid, uploadId }: { uid: string; uploadId: string },
): Promise<{ iconPath: string }> {
  const { firestore, auth, bucket, annotateImage } = dependencies;
  const userDocument = firestore.doc(`users/${uid}`);
  const iconPath = profileIconPath({ uid, uploadId });
  const uploadFile = bucket.file(profileIconUploadPath({ uid, uploadId }));
  const userSnapshot = await userDocument.get();
  try {
    await requireActiveAccount({ auth, uid, userSnapshot });
  } catch (error) {
    // 削除の途中・削除の後に別の端末から置かれた写真を、アカウントのデータとして残さない
    await uploadFile.delete({ ignoreNotFound: true });
    throw error;
  }
  if (userSnapshot.get("iconPath") === iconPath) {
    return { iconPath };
  }
  if (!(await uploadFile.exists())[0]) {
    throw new HttpsError("not-found", "アイコンにする写真が見つかりません");
  }
  const photo = await downloadFile(bucket, uploadFile.name);
  // 生成と同じく縮めた写真を送る (顔・露骨な内容の判定は長辺 1024px で足りるため。pipeline.ts の runSafeSearchStage)
  const annotation = await annotateImage(await downscalePhoto(photo));
  const rejectionReason = visionRejectionReason(annotation);
  if (rejectionReason) {
    logger.info("Vision の判定でアイコンにしません", { uid, uploadId, rejectionReason, ...visionRejectionLogFields(annotation) });
    await uploadFile.delete({ ignoreNotFound: true });
    throw new HttpsError(
      "invalid-argument",
      rejectionReason === "face_detected" ? "人の顔が写っている写真はアイコンにできません" : "この写真はアイコンにできません",
    );
  }
  await bucket.file(iconPath).save(
    await sharp(photo).rotate().resize({ width: PROFILE_ICON_SIDE, height: PROFILE_ICON_SIDE, fit: "cover" }).png().toBuffer(),
    { contentType: "image/png", resumable: false },
  );
  const previousIconPath = await firestore.runTransaction(async (transaction) => {
    const currentUserSnapshot = await transaction.get(userDocument);
    // 検査の間に削除が始まった時に、消し終えた後へ iconPath だけが残らないよう、書く直前にもう一度確かめる
    await requireActiveAccount({ auth, uid, userSnapshot: currentUserSnapshot });
    transaction.set(userDocument, { iconPath }, { merge: true });
    return currentUserSnapshot.get("iconPath") as unknown;
  });
  await Promise.all([
    uploadFile.delete({ ignoreNotFound: true }),
    ...(typeof previousIconPath === "string" && previousIconPath !== iconPath && previousIconPath.startsWith(`users/${uid}/icons/`)
      ? [bucket.file(previousIconPath).delete({ ignoreNotFound: true })]
      : []),
  ]);
  return { iconPath };
}

/**
 * プロフィールのアイコンを登録する callable (App Check の強制は app_check.ts)。
 *
 * 受け取る data: `{ uploadId: string }` (先に `users/{uid}/iconUploads/{uploadId}` に写真を置く)。返す値: `{ iconPath: string }`。
 * 検査と保存は [setProfileIconData]。
 * memory 1GiB: 生成 (generate.ts) と同じく長辺 1024px の写真を sharp で展開するため、同じ値にした。
 */
export const setProfileIcon = onCall({ enforceAppCheck: ENFORCE_APP_CHECK, memory: "1GiB" }, async (request) => {
  const uid = requireSignedInUid({ request });
  const { uploadId } = (request.data ?? {}) as { uploadId?: unknown };
  if (!isDocumentId(uploadId)) {
    throw new HttpsError("invalid-argument", "uploadId を渡してください");
  }
  const { firestore, bucket, annotateImage } = createProductionDependencies();
  // 生成 (generate.ts) と同じく、削除を消し終えた uid が置いたファイル (users/{uid}/ の配下) を消して断る
  await rejectDeletedAccount({ auth: getAuth(), bucket, uid });
  return setProfileIconData({ firestore, auth: getAuth(), bucket, annotateImage }, { uid, uploadId });
});
