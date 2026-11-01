import { deleteApp, getApps, initializeApp } from "firebase-admin/app";
import type { Auth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import sharp from "sharp";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

import type { AnnotateImage, VisionAnnotation } from "../../src/generation/vision";
import { tokyoDate } from "../../src/generation/pipeline";
import {
  DAILY_ICON_CHECK_LIMIT_PER_USER,
  DAILY_ICON_CHECK_LIMIT_TOTAL,
  PROFILE_ICON_SIDE,
  profileIconPath,
  profileIconUploadPath,
  setProfileIconData,
} from "../../src/profile";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// アイコンの登録の本体 (setProfileIconData) を Firestore・Storage の Emulator に対して、Cloud Vision をモックにして呼ぶ。

const projectId = "demo-snapmon";
const app = getApps().find((existing) => existing.name === "profile-test") ?? initializeApp({ projectId }, "profile-test");
const firestore = getFirestore(app);
const bucket = getStorage(app).bucket("snapmon-prod-storage");

afterAll(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
  const [files] = await bucket.getFiles();
  await Promise.all(files.map((file) => file.delete({ ignoreNotFound: true })));
});

/** Auth のユーザーが残っている uid (アカウントを消し終えた uid は含めない)。 */
const authUserUids = new Set(["alice"]);

/** [authUserUids] の uid だけを残っているユーザーとして返す Auth のモック (generate.test.ts と同じ)。 */
const auth = {
  getUser: async (uid: string) => {
    if (!authUserUids.has(uid)) {
      throw Object.assign(new Error("ユーザーが見つかりません"), { code: "auth/user-not-found" });
    }
    return { uid };
  },
} as unknown as Auth;

/** 問題の無い写真の Vision の判定。 */
const safeAnnotation: VisionAnnotation = { safeSearchAnnotation: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY" } };

/** [annotation] を返す Vision のモックと、呼ばれた回数。 */
function createVision(annotation: VisionAnnotation): { annotateImage: AnnotateImage; calls: { count: number } } {
  const calls = { count: 0 };
  return {
    calls,
    annotateImage: async () => {
      calls.count++;
      return annotation;
    },
  };
}

/** [uid] が [uploadId] に、横長 (400×300) の JPEG を置く (端末が置く写真と同じ形)。 */
async function uploadIconPhoto({ uid, uploadId }: { uid: string; uploadId: string }): Promise<void> {
  const photo = await sharp({ create: { width: 400, height: 300, channels: 3, background: { r: 200, g: 120, b: 40 } } }).jpeg().toBuffer();
  await bucket.file(profileIconUploadPath({ uid, uploadId })).save(photo, { contentType: "image/jpeg", resumable: false });
}

/** バケットに [path] のファイルがあるか。 */
async function exists(path: string): Promise<boolean> {
  return (await bucket.file(path).exists())[0];
}

describe("setProfileIconData", () => {
  it("検査を通った写真を正方形の PNG にして users/{uid}/icons に置き、iconPath に書き、置いた写真を消す", async () => {
    const vision = createVision(safeAnnotation);
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });

    const result = await setProfileIconData({ firestore, auth, bucket, annotateImage: vision.annotateImage }, { uid: "alice", uploadId: "upload1" });

    expect(result).toEqual({ iconPath: profileIconPath({ uid: "alice", uploadId: "upload1" }) });
    expect((await firestore.doc("users/alice").get()).get("iconPath")).toBe(result.iconPath);
    const [icon] = await bucket.file(result.iconPath).download();
    expect(await sharp(icon).metadata()).toMatchObject({ format: "png", width: PROFILE_ICON_SIDE, height: PROFILE_ICON_SIDE });
    expect(await exists(profileIconUploadPath({ uid: "alice", uploadId: "upload1" }))).toBe(false);
    expect(vision.calls.count).toBe(1);
  });

  it("同じ uploadId で呼び直しても Vision を呼び直さず同じパスを返す", async () => {
    const vision = createVision(safeAnnotation);
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });
    const dependencies = { firestore, auth, bucket, annotateImage: vision.annotateImage };
    const first = await setProfileIconData(dependencies, { uid: "alice", uploadId: "upload1" });

    expect(await setProfileIconData(dependencies, { uid: "alice", uploadId: "upload1" })).toEqual(first);
    expect(vision.calls.count).toBe(1);
  });

  it("差し替えた時は前のアイコンを消す", async () => {
    const dependencies = { firestore, auth, bucket, annotateImage: createVision(safeAnnotation).annotateImage };
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });
    const first = await setProfileIconData(dependencies, { uid: "alice", uploadId: "upload1" });
    await uploadIconPhoto({ uid: "alice", uploadId: "upload2" });

    const second = await setProfileIconData(dependencies, { uid: "alice", uploadId: "upload2" });

    expect((await firestore.doc("users/alice").get()).get("iconPath")).toBe(second.iconPath);
    expect(await exists(second.iconPath)).toBe(true);
    expect(await exists(first.iconPath)).toBe(false);
  });

  it("人の顔が写る写真はアイコンにせず、置いた写真を消して理由を返す", async () => {
    const vision = createVision({ ...safeAnnotation, faceAnnotations: [{ detectionConfidence: 0.9 }] });
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });

    await expect(
      setProfileIconData({ firestore, auth, bucket, annotateImage: vision.annotateImage }, { uid: "alice", uploadId: "upload1" }),
    ).rejects.toMatchObject({ code: "invalid-argument", message: "人の顔が写っている写真はアイコンにできません" });
    expect((await firestore.doc("users/alice").get()).get("iconPath")).toBeUndefined();
    expect(await exists(profileIconUploadPath({ uid: "alice", uploadId: "upload1" }))).toBe(false);
    expect(await exists(profileIconPath({ uid: "alice", uploadId: "upload1" }))).toBe(false);
  });

  it("露骨な内容の写真はアイコンにしない", async () => {
    const vision = createVision({ safeSearchAnnotation: { adult: "VERY_LIKELY" } });
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });

    await expect(
      setProfileIconData({ firestore, auth, bucket, annotateImage: vision.annotateImage }, { uid: "alice", uploadId: "upload1" }),
    ).rejects.toMatchObject({ code: "invalid-argument", message: "この写真はアイコンにできません" });
    expect((await firestore.doc("users/alice").get()).get("iconPath")).toBeUndefined();
  });

  it("uid ごとの 1 日の検査の上限に達すると、Vision を呼ばずに resource-exhausted を返す", async () => {
    const vision = createVision(safeAnnotation);
    await firestore
      .doc("users/alice")
      .set({ dailyIconCheck: { date: tokyoDate(new Date()), count: DAILY_ICON_CHECK_LIMIT_PER_USER } });
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });

    await expect(
      setProfileIconData({ firestore, auth, bucket, annotateImage: vision.annotateImage }, { uid: "alice", uploadId: "upload1" }),
    ).rejects.toMatchObject({ code: "resource-exhausted" });
    expect(vision.calls.count).toBe(0);
    expect(await exists(profileIconUploadPath({ uid: "alice", uploadId: "upload1" }))).toBe(false);
  });

  it("Vision の呼び出しが失敗した時も、置かれた写真を残さない", async () => {
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });

    await expect(
      setProfileIconData(
        {
          firestore,
          auth,
          bucket,
          annotateImage: async () => {
            throw new Error("Vision の一時的な失敗");
          },
        },
        { uid: "alice", uploadId: "upload1" },
      ),
    ).rejects.toThrow("Vision の一時的な失敗");
    expect(await exists(profileIconUploadPath({ uid: "alice", uploadId: "upload1" }))).toBe(false);
    expect((await firestore.doc("users/alice").get()).get("iconPath")).toBeUndefined();
  });

  it("全体の 1 日の検査の上限に達すると、Vision を呼ばずに resource-exhausted を返す", async () => {
    const vision = createVision(safeAnnotation);
    await firestore.doc(`iconCheckDailyCounts/${tokyoDate(new Date())}`).set({ count: DAILY_ICON_CHECK_LIMIT_TOTAL });
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });

    await expect(
      setProfileIconData({ firestore, auth, bucket, annotateImage: vision.annotateImage }, { uid: "alice", uploadId: "upload1" }),
    ).rejects.toMatchObject({ code: "resource-exhausted" });
    expect(vision.calls.count).toBe(0);
  });

  it("検査のたびに uid ごとと全体の今日の数を 1 つ増やす", async () => {
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });
    await setProfileIconData({ firestore, auth, bucket, annotateImage: createVision(safeAnnotation).annotateImage }, { uid: "alice", uploadId: "upload1" });

    const today = tokyoDate(new Date());
    expect((await firestore.doc("users/alice").get()).get("dailyIconCheck")).toEqual({ date: today, count: 1 });
    expect((await firestore.doc(`iconCheckDailyCounts/${today}`).get()).get("count")).toBe(1);
  });

  it("写真が置かれていない時は not-found", async () => {
    await expect(
      setProfileIconData({ firestore, auth, bucket, annotateImage: createVision(safeAnnotation).annotateImage }, { uid: "alice", uploadId: "missing" }),
    ).rejects.toMatchObject({ code: "not-found" });
  });

  it("アカウントの削除の途中と、削除を消し終えたユーザーは受け付けない", async () => {
    const vision = createVision(safeAnnotation);
    await firestore.doc("users/alice").set({ accountDeletionStartedAt: Timestamp.now() });
    await uploadIconPhoto({ uid: "alice", uploadId: "upload1" });
    await uploadIconPhoto({ uid: "deleted", uploadId: "upload1" });

    for (const uid of ["alice", "deleted"]) {
      await expect(
        setProfileIconData({ firestore, auth, bucket, annotateImage: vision.annotateImage }, { uid, uploadId: "upload1" }),
      ).rejects.toMatchObject({ code: "failed-precondition" });
    }
    expect(vision.calls.count).toBe(0);
    // 断った時は置かれた写真を残さない
    for (const uid of ["alice", "deleted"]) {
      expect(await exists(profileIconUploadPath({ uid, uploadId: "upload1" })), uid).toBe(false);
    }
  });

  it("最初の確認の後に削除を消し終えた時は、users/{uid} を作り直さずに断る", async () => {
    // users/{uid} がまだ無いユーザーで、最初の確認で Auth のユーザーを見た直後に削除が Auth のユーザーを消し終えた状態を作る
    let racerAuthUserExists = true;
    const racingAuth = {
      getUser: async (uid: string) => {
        if (!racerAuthUserExists) {
          throw Object.assign(new Error("ユーザーが見つかりません"), { code: "auth/user-not-found" });
        }
        racerAuthUserExists = false;
        return { uid };
      },
    } as unknown as Auth;
    const vision = createVision(safeAnnotation);
    await uploadIconPhoto({ uid: "racer", uploadId: "upload1" });

    await expect(
      setProfileIconData({ firestore, auth: racingAuth, bucket, annotateImage: vision.annotateImage }, { uid: "racer", uploadId: "upload1" }),
    ).rejects.toMatchObject({ code: "failed-precondition" });
    expect((await firestore.doc("users/racer").get()).exists).toBe(false);
    expect(vision.calls.count).toBe(0);
    expect(await exists(profileIconUploadPath({ uid: "racer", uploadId: "upload1" }))).toBe(false);
    expect(await exists(profileIconPath({ uid: "racer", uploadId: "upload1" }))).toBe(false);
  });
});
