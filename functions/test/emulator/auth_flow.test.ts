import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously, signOut } from "firebase/auth";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// 匿名ログインだけ (カスタムクレーム無し) で Functions を呼べることを、Auth と Functions の Emulator で確かめる。

const projectId = "demo-snapmon";
const functionsBaseUrl = `http://127.0.0.1:5001/${projectId}/asia-northeast1`;

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

// signInAnonymously はログイン済みの匿名ユーザーを使い回すため、テストごとに新しいユーザーで始める。
beforeEach(async () => {
  await signOut(auth);
});

afterAll(async () => {
  await deleteApp(app);
});

/** callable [name] をプロトコル (POST の JSON `{ data }`) で呼び、HTTP の応答を返す。 */
async function callFunction({
  name,
  idToken,
  appCheckToken,
  data,
}: {
  name: string;
  idToken: string | null;
  appCheckToken: string | null;
  data: unknown;
}): Promise<Response> {
  return fetch(`${functionsBaseUrl}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}),
      ...(appCheckToken ? { "X-Firebase-AppCheck": appCheckToken } : {}),
    },
    body: JSON.stringify({ data }),
  });
}

describe("匿名ログイン", () => {
  it("匿名ログインだけで、まだ users/{uid} の無い新しいユーザーが表示名を変えて読める", async () => {
    const credential = await signInAnonymously(auth);
    expect(credential.user.uid).not.toBe("");
    expect((await credential.user.getIdTokenResult()).claims.ageVerified).toBeUndefined();
    const idToken = await credential.user.getIdToken();

    const updated = await callFunction({
      name: "setDisplayName",
      idToken,
      appCheckToken: fakeAppCheckToken,
      data: { displayName: "ばんざい" },
    });
    expect(updated.status).toBe(200);
    expect(await updated.json()).toEqual({ result: { displayName: "ばんざい" } });

    const fetched = await callFunction({ name: "getDisplayName", idToken, appCheckToken: fakeAppCheckToken, data: null });
    expect(fetched.status).toBe(200);
    expect(await fetched.json()).toEqual({ result: { displayName: "ばんざい" } });
  });

  it("ログインしていない呼び出しは弾く", async () => {
    const response = await callFunction({ name: "getDisplayName", idToken: null, appCheckToken: fakeAppCheckToken, data: null });
    expect(response.status).toBe(401);
    expect((await response.json()).error.status).toBe("UNAUTHENTICATED");
  });

  it("App Check のトークンが無い呼び出しは弾く", async () => {
    const credential = await signInAnonymously(auth);
    const response = await callFunction({
      name: "getDisplayName",
      idToken: await credential.user.getIdToken(),
      appCheckToken: null,
      data: null,
    });
    expect(response.status).toBe(401);
  });
});
