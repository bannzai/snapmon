import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously, signOut } from "firebase/auth";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// 年齢の確認の後の流れ (匿名ログイン → confirmAge → クレーム付きのトークン) を Auth と Functions の Emulator で確かめる。

const projectId = "demo-snapmon";
const confirmAgeUrl = `http://127.0.0.1:5001/${projectId}/asia-northeast1/confirmAge`;

// Functions の Emulator は App Check のトークンを検証せずに中身だけを読む (firebase-functions の skipTokenVerification)。
// 署名の無い JWT の形にして、App Check のトークンを付けた呼び出しを模す。
const fakeAppCheckToken = [
  Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ sub: "1:000000000000:web:emulator", aud: [`projects/${projectId}`] })).toString("base64url"),
  "",
].join(".");

const app = initializeApp({ projectId, apiKey: "demo-api-key" }, "auth-flow-test");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });

// signInAnonymously はログイン済みの匿名ユーザーを使い回すため、テストごとに未確認の新しいユーザーで始める。
beforeEach(async () => {
  await signOut(auth);
});

afterAll(async () => {
  await deleteApp(app);
});

/** confirmAge を callable のプロトコル (POST の JSON `{ data }`) で呼び、HTTP の応答を返す。 */
async function callConfirmAge({
  idToken,
  appCheckToken,
  data,
}: {
  idToken: string;
  appCheckToken: string | null;
  data: unknown;
}): Promise<Response> {
  return fetch(confirmAgeUrl, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
      ...(appCheckToken ? { "X-Firebase-AppCheck": appCheckToken } : {}),
    },
    body: JSON.stringify({ data }),
  });
}

describe("匿名ログインと年齢の確認", () => {
  it("匿名ログインで uid が取れ、confirmAge の後のトークンに ageVerified が付く", async () => {
    const credential = await signInAnonymously(auth);
    expect(credential.user.uid).not.toBe("");
    expect((await credential.user.getIdTokenResult()).claims.ageVerified).toBeUndefined();

    const response = await callConfirmAge({
      idToken: await credential.user.getIdToken(),
      appCheckToken: fakeAppCheckToken,
      data: { birthYear: 2000, birthMonth: 1 },
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ result: { ageVerified: true } });

    expect((await credential.user.getIdTokenResult(true)).claims.ageVerified).toBe(true);
  });

  it("13 歳未満にはクレームを付けない", async () => {
    const credential = await signInAnonymously(auth);
    const response = await callConfirmAge({
      idToken: await credential.user.getIdToken(),
      appCheckToken: fakeAppCheckToken,
      data: { birthYear: new Date().getUTCFullYear() - 5, birthMonth: 1 },
    });
    expect(response.status).toBe(400);
    expect((await response.json()).error.status).toBe("FAILED_PRECONDITION");
    expect((await credential.user.getIdTokenResult(true)).claims.ageVerified).toBeUndefined();
  });

  it("13 歳未満と判定された uid は、別の生年月で呼び直しても通さない", async () => {
    const credential = await signInAnonymously(auth);
    const idToken = await credential.user.getIdToken();
    const rejected = await callConfirmAge({
      idToken,
      appCheckToken: fakeAppCheckToken,
      data: { birthYear: new Date().getUTCFullYear() - 5, birthMonth: 1 },
    });
    expect(rejected.status).toBe(400);

    const retried = await callConfirmAge({
      idToken,
      appCheckToken: fakeAppCheckToken,
      data: { birthYear: 2000, birthMonth: 1 },
    });
    expect(retried.status).toBe(400);
    expect((await retried.json()).error.status).toBe("FAILED_PRECONDITION");
    expect((await credential.user.getIdTokenResult(true)).claims.ageVerified).toBeUndefined();
  });

  // 呼び出しが実際に重なるかは Emulator の処理順に依存し、1 回では原子性を確かめられない。
  // 重なる回数を増やすため別々の uid で繰り返す (重ならなかった回は修正前のコードでも通る)。
  it("同じ uid から 13 歳未満と 13 歳以上を同時に送っても、判定は 1 通りになる", async () => {
    // 10 回: 重なる機会を増やしつつ、テストの時間を下の上限に収めるため
    for (let attempt = 0; attempt < 10; attempt++) {
      await signOut(auth);
      const credential = await signInAnonymously(auth);
      const idToken = await credential.user.getIdToken();
      const responses = await Promise.all([
        callConfirmAge({
          idToken,
          appCheckToken: fakeAppCheckToken,
          data: { birthYear: new Date().getUTCFullYear() - 5, birthMonth: 1 },
        }),
        callConfirmAge({ idToken, appCheckToken: fakeAppCheckToken, data: { birthYear: 2000, birthMonth: 1 } }),
      ]);
      const claimed = (await credential.user.getIdTokenResult(true)).claims.ageVerified === true;
      const statuses = responses.map((response) => response.status);
      // 先に確定した判定だけが有効なため、クレームが付いた時は両方 200、付かない時は両方 400 になる
      expect(statuses).toEqual(claimed ? [200, 200] : [400, 400]);
    }
    // 60 秒: 呼び出しが重なると Firestore のトランザクションが競合して再試行で待つため、既定の 5 秒では足りない (手元の実測で超えた)
  }, 60_000);

  it("App Check のトークンが無い呼び出しは弾く", async () => {
    const credential = await signInAnonymously(auth);
    const response = await callConfirmAge({
      idToken: await credential.user.getIdToken(),
      appCheckToken: null,
      data: { birthYear: 2000, birthMonth: 1 },
    });
    expect(response.status).toBe(401);
  });
});
