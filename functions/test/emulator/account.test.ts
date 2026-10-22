import { createHash, randomUUID } from "node:crypto";

import { deleteApp as deleteAdminApp, getApps, initializeApp as initializeAdminApp } from "firebase-admin/app";
import { getAuth as getAdminAuth } from "firebase-admin/auth";
import { getFirestore as getAdminFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage as getAdminStorage } from "firebase-admin/storage";
import { deleteApp, initializeApp } from "firebase/app";
import {
  connectAuthEmulator,
  getAuth,
  GoogleAuthProvider,
  linkWithCredential,
  signInAnonymously,
  signInWithCredential,
  signOut,
  type User,
} from "firebase/auth";
import { connectFirestoreEmulator, doc, getDoc, getFirestore } from "firebase/firestore";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

import { type AccountDeletionDependencies, type AccountFileDeletionTask, deleteAccountData } from "../../src/account";
import { handleGenerateRequest } from "../../src/generation/generate";
import { type GenerationDependencies, resumeGeneration, type StorageBucket } from "../../src/generation/pipeline";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// 匿名アカウントへの Google の連携 (引き継ぎ) と、アカウントの削除 (deleteAccount) を Auth・Firestore・Storage・Functions の Emulator で確かめる。

const projectId = "demo-snapmon";
const functionsBaseUrl = `http://127.0.0.1:5001/${projectId}/asia-northeast1`;

// Functions の Emulator は App Check のトークンを検証せずに中身だけを読む (auth_flow.test.ts と同じ署名の無い JWT)。
const fakeAppCheckToken = [
  Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ sub: "1:000000000000:web:emulator", aud: [`projects/${projectId}`] })).toString("base64url"),
  "",
].join(".");

const app = initializeApp({ projectId, apiKey: "demo-api-key" }, "account-test");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
const clientFirestore = getFirestore(app);
connectFirestoreEmulator(clientFirestore, "127.0.0.1", 8080);

const adminApp = getApps().find((existing) => existing.name === "account-test") ?? initializeAdminApp({ projectId }, "account-test");
const adminFirestore = getAdminFirestore(adminApp);
const adminAuth = getAdminAuth(adminApp);
const bucket = getAdminStorage(adminApp).bucket("snapmon-prod-storage");

afterAll(async () => {
  await deleteApp(app);
  await deleteAdminApp(adminApp);
});

beforeEach(async () => {
  await signOut(auth);
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
  const [files] = await bucket.getFiles();
  await Promise.all(files.map((file) => file.delete({ ignoreNotFound: true })));
});

/** Functions の callable [name] をプロトコル (POST の JSON `{ data }`) で呼び、HTTP の応答を返す。 */
async function callFunction({ name, idToken, data }: { name: string; idToken: string; data: unknown }): Promise<Response> {
  return fetch(`${functionsBaseUrl}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}`, "X-Firebase-AppCheck": fakeAppCheckToken },
    body: JSON.stringify({ data }),
  });
}

/** 匿名ログインし、confirmAge でクレームを付けたユーザーを返す。 */
async function signInAgeVerifiedUser(): Promise<User> {
  const credential = await signInAnonymously(auth);
  const response = await callFunction({ name: "confirmAge", idToken: await credential.user.getIdToken(), data: { birthYear: 2000, birthMonth: 1 } });
  expect(response.status).toBe(200);
  await credential.user.getIdToken(true);
  return credential.user;
}

/**
 * Auth の Emulator が受け付ける、署名の無い Google の ID トークン (JSON) の credential。
 * 本物の Google の ID トークンは Emulator では検証できないため、Emulator の仕様の形で渡す。
 */
function fakeGoogleCredential({ googleUserId }: { googleUserId: string }) {
  return GoogleAuthProvider.credential(JSON.stringify({ sub: googleUserId, email: `${googleUserId}@example.com`, email_verified: true }));
}

/** [uid] の図鑑・生成・バトル・手持ち・Storage のファイルと、本人と他人の通報・ブロックを Rules を通さずに置く。 */
async function seedAccount({ uid }: { uid: string }): Promise<void> {
  await adminFirestore.doc(`users/${uid}`).set({ ageAccepted: true }, { merge: true });
  await adminFirestore.doc(`users/${uid}/monsters/monster-${uid}`).set({ artPath: `monsters/monster-${uid}/art.png`, level: 1 });
  await adminFirestore.doc(`users/${uid}/generations/request-saved`).set({ status: "saved", monsterId: `monster-${uid}` });
  // 保存の段階で絵を置いた後に failed になった生成 (図鑑にはモンスターが無い)
  await adminFirestore.doc(`users/${uid}/generations/request-failed`).set({ status: "failed", monsterId: `failed-${uid}` });
  await adminFirestore.doc(`users/${uid}/battles/battle1`).set({ status: "completed" });
  await adminFirestore.doc(`users/${uid}/party/current`).set({ monsterIds: [`monster-${uid}`] });
  await adminFirestore.doc(`reports/report-by-${uid}`).set({ reporterUid: uid });
  await adminFirestore.doc(`blocks/block-by-${uid}`).set({ blockerUid: uid });
  for (const path of [
    `users/${uid}/photos/request-saved`,
    `users/${uid}/masks/request-saved`,
    `users/${uid}/generations/request-saved/cutout.png`,
    `monsters/monster-${uid}/art.png`,
    `monsters/failed-${uid}/art.png`,
  ]) {
    await bucket.file(path).save(Buffer.from([0xff, 0xd8, 0xff, 0xe0]));
  }
}

/** [uid] のデータのうち、残っているものの Firestore・Storage のパスを返す。 */
async function remainingAccountData({ uid }: { uid: string }): Promise<string[]> {
  const documentPaths = [
    `users/${uid}`,
    `users/${uid}/monsters/monster-${uid}`,
    `users/${uid}/generations/request-saved`,
    `users/${uid}/generations/request-failed`,
    `users/${uid}/battles/battle1`,
    `users/${uid}/party/current`,
    `reports/report-by-${uid}`,
    `blocks/block-by-${uid}`,
  ];
  const remainingDocuments = (await Promise.all(documentPaths.map(async (path) => ((await adminFirestore.doc(path).get()).exists ? path : null)))).filter(
    (path): path is string => path !== null,
  );
  const [userFiles] = await bucket.getFiles({ prefix: `users/${uid}/` });
  const artFiles = (
    await Promise.all([`monsters/monster-${uid}/art.png`, `monsters/failed-${uid}/art.png`].map(async (path) => ((await bucket.file(path).exists())[0] ? path : null)))
  ).filter((path): path is string => path !== null);
  return [...remainingDocuments, ...userFiles.map((file) => file.name), ...artFiles];
}

/** 本番と同じ資源 (Emulator) で、タスクを積む代わりに積んだ中身を [enqueued] に残す削除の依存を作る。 */
function accountDeletionDependencies({ enqueued, bucketOverride }: { enqueued: AccountFileDeletionTask[]; bucketOverride?: StorageBucket }): AccountDeletionDependencies {
  return {
    firestore: adminFirestore,
    bucket: bucketOverride ?? bucket,
    auth: adminAuth,
    enqueueFileDeletion: async (task) => {
      enqueued.push(task);
    },
    now: () => new Date(),
  };
}

describe("匿名アカウントへの連携 (引き継ぎ)", () => {
  it("匿名ユーザーに Google の credential を連携した後も、同じ uid で図鑑が残る", async () => {
    const user = await signInAgeVerifiedUser();
    const anonymousUid = user.uid;
    await adminFirestore.doc(`users/${anonymousUid}/monsters/monster1`).set({ name: "マグカップン", level: 3 });

    const linked = await linkWithCredential(user, fakeGoogleCredential({ googleUserId: randomUUID() }));

    expect(linked.user.uid).toBe(anonymousUid);
    expect(linked.user.isAnonymous).toBe(false);
    expect(linked.user.providerData.map((provider) => provider.providerId)).toEqual(["google.com"]);
    // 連携の後も confirmAge のクレームが残り、Rules を通って本人の図鑑を読める
    expect((await linked.user.getIdTokenResult(true)).claims.ageVerified).toBe(true);
    expect((await getDoc(doc(clientFirestore, `users/${anonymousUid}/monsters/monster1`))).data()).toEqual({ name: "マグカップン", level: 3 });
  });

  it("別の端末で連携済みの Google で連携すると credential-already-in-use になり、その Google の credential で連携済みのアカウントに切り替えられる", async () => {
    const googleUserId = randomUUID();
    const firstDevice = await signInAgeVerifiedUser();
    await linkWithCredential(firstDevice, fakeGoogleCredential({ googleUserId }));
    await adminFirestore.doc(`users/${firstDevice.uid}/monsters/monster1`).set({ name: "サボテンダ", level: 5 });
    await signOut(auth);

    const secondDevice = await signInAgeVerifiedUser();
    const error = await linkWithCredential(secondDevice, fakeGoogleCredential({ googleUserId })).then(
      () => null,
      (linkError: unknown) => linkError,
    );
    expect((error as { code?: string }).code).toBe("auth/credential-already-in-use");

    // Auth の Emulator は credential-already-in-use のエラーに連携済みのアカウントの credential を載せない (CI の実測で
    // GoogleAuthProvider.credentialFromError が null だった)。そのため、Android の経路 (lib/firebase/account.dart が連携に使った
    // credential を持ち続ける) と同じく、連携に使った credential でサインインする
    const switched = await signInWithCredential(auth, fakeGoogleCredential({ googleUserId }));
    expect(switched.user.uid).toBe(firstDevice.uid);
    expect((await switched.user.getIdTokenResult(true)).claims.ageVerified).toBe(true);
    expect((await getDoc(doc(clientFirestore, `users/${firstDevice.uid}/monsters/monster1`))).data()).toEqual({ name: "サボテンダ", level: 5 });
  });
});

describe("アカウントの削除 (deleteAccount)", () => {
  it("users/{uid} 配下・Storage の写真と絵・本人の通報とブロック・Auth のユーザーを消し、他人のデータは残す", async () => {
    const otherUser = await signInAgeVerifiedUser();
    await seedAccount({ uid: otherUser.uid });
    await signOut(auth);
    const user = await signInAgeVerifiedUser();
    await seedAccount({ uid: user.uid });
    expect(await remainingAccountData({ uid: user.uid })).toHaveLength(13);

    const response = await callFunction({ name: "deleteAccount", idToken: await user.getIdToken(), data: null });

    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ result: { deleted: true } });
    expect(await remainingAccountData({ uid: user.uid })).toEqual([]);
    await expect(adminAuth.getUser(user.uid)).rejects.toMatchObject({ code: "auth/user-not-found" });
    expect(await remainingAccountData({ uid: otherUser.uid })).toHaveLength(13);
    expect((await adminAuth.getUser(otherUser.uid)).uid).toBe(otherUser.uid);
  });

  it("生成の途中 (生成中ロックが期限内) は断り、何も消さない", async () => {
    const user = await signInAgeVerifiedUser();
    await seedAccount({ uid: user.uid });
    await adminFirestore.doc(`users/${user.uid}`).set(
      { generationLock: { requestId: "request-processing", expiresAt: Timestamp.fromMillis(Date.now() + 60_000) } },
      { merge: true },
    );

    const response = await callFunction({ name: "deleteAccount", idToken: await user.getIdToken(), data: null });

    expect(response.status).toBe(400);
    expect((await response.json()).error.status).toBe("FAILED_PRECONDITION");
    expect(await remainingAccountData({ uid: user.uid })).toHaveLength(13);
    expect((await adminAuth.getUser(user.uid)).uid).toBe(user.uid);
  });

  it("Storage を消すのに失敗したら、消すタスクを積んでから Firestore と Auth を消す", async () => {
    const user = await signInAgeVerifiedUser();
    await seedAccount({ uid: user.uid });
    const enqueued: AccountFileDeletionTask[] = [];
    const failingBucket = new Proxy(bucket, {
      get(target, property) {
        if (property === "deleteFiles") {
          return async () => {
            throw new Error("Storage の一時的なエラー");
          };
        }
        const value = Reflect.get(target, property) as unknown;
        return typeof value === "function" ? value.bind(target) : value;
      },
    });

    await deleteAccountData(accountDeletionDependencies({ enqueued, bucketOverride: failingBucket }), { uid: user.uid });

    expect(enqueued).toHaveLength(1);
    expect(enqueued[0].uid).toBe(user.uid);
    expect([...enqueued[0].artPaths].sort()).toEqual([`monsters/failed-${user.uid}/art.png`, `monsters/monster-${user.uid}/art.png`]);
    await expect(adminAuth.getUser(user.uid)).rejects.toMatchObject({ code: "auth/user-not-found" });
    expect((await adminFirestore.doc(`users/${user.uid}`).get()).exists).toBe(false);
  });

  it("消し終えたアカウントにもう一度呼んでも成功する (冪等)", async () => {
    const user = await signInAgeVerifiedUser();
    await seedAccount({ uid: user.uid });
    const enqueued: AccountFileDeletionTask[] = [];

    await deleteAccountData(accountDeletionDependencies({ enqueued }), { uid: user.uid });
    await deleteAccountData(accountDeletionDependencies({ enqueued }), { uid: user.uid });

    expect(enqueued).toEqual([]);
    expect(await remainingAccountData({ uid: user.uid })).toEqual([]);
  });

  it("削除の後に、別の端末に残った ID トークンで写真を置いて generate を呼んでも断り、置いた写真を消す", async () => {
    const user = await signInAgeVerifiedUser();
    const staleIdToken = await user.getIdToken();
    const deleted = await callFunction({ name: "deleteAccount", idToken: staleIdToken, data: null });
    expect(deleted.status).toBe(200);
    const requestId = randomUUID();
    await bucket.file(`users/${user.uid}/photos/${requestId}`).save(Buffer.from([0xff, 0xd8, 0xff, 0xe0]));

    const response = await callFunction({ name: "generate", idToken: staleIdToken, data: { requestId, photoPath: `users/${user.uid}/photos/${requestId}` } });

    expect(response.status).toBe(401);
    expect((await response.json()).error.status).toBe("UNAUTHENTICATED");
    expect((await bucket.file(`users/${user.uid}/photos/${requestId}`).exists())[0]).toBe(false);
    expect((await adminFirestore.collection(`users/${user.uid}/generations`).get()).empty).toBe(true);
  });

  it("削除が始まった後は、予約の切れた生成を再試行のタスクで再開しない", async () => {
    const uid = randomUUID();
    const requestId = randomUUID();
    await adminFirestore.doc(`users/${uid}`).set({ accountDeletionStartedAt: Timestamp.now() });
    await adminFirestore.doc(`users/${uid}/generations/${requestId}`).set({
      status: "processing",
      completedStage: "accepted",
      photoPath: `users/${uid}/photos/${requestId}`,
      maskPath: null,
      inputKey: "input-key",
      leaseExpiresAt: Timestamp.fromMillis(Date.now() - 60_000),
      leaseToken: "expired-lease",
      attemptCount: 1,
      judgeRetryCount: 0,
    });
    const unused = async () => {
      throw new Error("再開しないので外部の API を呼ばない");
    };

    const result = await resumeGeneration(
      {
        firestore: adminFirestore,
        bucket,
        annotateImage: unused,
        segmentSubject: unused,
        describeSubject: unused,
        proposeElement: unused,
        askJev: unused,
        enqueueResume: async () => {},
        now: () => new Date(),
      },
      { uid, requestId, purpose: "lease" },
    );

    expect(result).toEqual({ requestId, status: "failed" });
    const record = (await adminFirestore.doc(`users/${uid}/generations/${requestId}`).get()).data();
    expect(record?.leaseToken).toBe("expired-lease");
    expect(record?.attemptCount).toBe(1);
    expect((await adminFirestore.doc(`users/${uid}`).get()).get("generationLock")).toBeUndefined();
  });

  it("削除が始まった後は、バトルを始められない", async () => {
    const user = await signInAgeVerifiedUser();
    await adminFirestore.doc(`users/${user.uid}/monsters/m1`).set({ name: "m1", level: 1 });
    await adminFirestore.doc(`users/${user.uid}`).set({ accountDeletionStartedAt: Timestamp.now() }, { merge: true });

    const response = await callFunction({ name: "startBattle", idToken: await user.getIdToken(), data: { partyMonsterIds: ["m1"] } });

    expect(response.status).toBe(400);
    expect((await response.json()).error.status).toBe("FAILED_PRECONDITION");
    expect((await adminFirestore.collection(`users/${user.uid}/battles`).get()).empty).toBe(true);
  });

  it("消し終えた後 (users/{uid} が無い) は、同じ写真の使い回しの記録も書かずに生成を断る", async () => {
    const uid = randomUUID();
    const requestId = randomUUID();
    const photo = Buffer.from([0xff, 0xd8, 0xff, 0xe0]);
    await bucket.file(`users/${uid}/photos/${requestId}`).save(photo);
    // 削除の途中に消し残った、同じ写真の生成のレコード (使い回しの対象になる)
    await adminFirestore.doc(`users/${uid}/generations/previous`).set({ status: "saved", inputKey: `${createHash("sha256").update(photo).digest("hex")}:auto` });
    const unused = async () => {
      throw new Error("受け付ける前に外部の API を呼ばない");
    };

    await expect(
      handleGenerateRequest(
        {
          firestore: adminFirestore,
          bucket,
          annotateImage: unused,
          segmentSubject: unused,
          describeSubject: unused,
          proposeElement: unused,
          askJev: unused,
          enqueueResume: async () => {},
          now: () => new Date(),
        },
        { auth: { uid, token: { ageVerified: true } } as never, data: { requestId, photoPath: `users/${uid}/photos/${requestId}` } },
      ),
    ).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "account_not_found" } });
    expect((await adminFirestore.doc(`users/${uid}/generationAliases/${requestId}`).get()).exists).toBe(false);
    expect((await adminFirestore.doc(`users/${uid}`).get()).exists).toBe(false);
  });

  it("削除が始まった後は、生成を受け付けない", async () => {
    const uid = randomUUID();
    const requestId = randomUUID();
    await bucket.file(`users/${uid}/photos/${requestId}`).save(Buffer.from([0xff, 0xd8, 0xff, 0xe0]));
    await adminFirestore.doc(`users/${uid}`).set({ accountDeletionStartedAt: Timestamp.now() });
    const unused = async () => {
      throw new Error("受け付ける前に外部の API を呼ばない");
    };
    const dependencies: GenerationDependencies = {
      firestore: adminFirestore,
      bucket,
      annotateImage: unused,
      segmentSubject: unused,
      describeSubject: unused,
      proposeElement: unused,
      askJev: unused,
      enqueueResume: async () => {},
      now: () => new Date(),
    };

    await expect(
      handleGenerateRequest(dependencies, { auth: { uid, token: { ageVerified: true } } as never, data: { requestId, photoPath: `users/${uid}/photos/${requestId}` } }),
    ).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "account_deletion_in_progress" } });
    expect((await adminFirestore.collection(`users/${uid}/generations`).get()).empty).toBe(true);
  });
});
