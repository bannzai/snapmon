import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously } from "firebase/auth";
import { afterAll, describe, expect, it } from "vitest";

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
