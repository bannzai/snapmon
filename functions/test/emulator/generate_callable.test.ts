import { randomUUID } from "node:crypto";

import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously, signOut } from "firebase/auth";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// generate が Functions の Emulator に読み込まれ、callable として呼べることを確かめる。外部の API に届く前の検査だけを通す
// (Vision・Claude・Jev を呼ぶ経路は generate.test.ts がモックで確かめる)。

const projectId = "demo-snapmon";
const functionsOrigin = `http://127.0.0.1:5001/${projectId}/asia-northeast1`;

// Functions の Emulator は App Check のトークンを検証せずに中身だけを読むため、署名の無い JWT で模す (auth_flow.test.ts と同じ)。
const fakeAppCheckToken = [
  Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ sub: "1:000000000000:web:emulator", aud: [`projects/${projectId}`] })).toString("base64url"),
  "",
].join(".");

const app = initializeApp({ projectId, apiKey: "demo-api-key" }, "generate-callable-test");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });

beforeEach(async () => {
  await signOut(auth);
});

afterAll(async () => {
  await deleteApp(app);
});

/** callable のプロトコル (POST の JSON `{ data }`) で関数を呼ぶ。 */
function callFunction({ name, idToken, data }: { name: string; idToken: string | null; data: unknown }): Promise<Response> {
  return fetch(`${functionsOrigin}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(idToken ? { Authorization: `Bearer ${idToken}` } : {}),
      "X-Firebase-AppCheck": fakeAppCheckToken,
    },
    body: JSON.stringify({ data }),
  });
}

describe("generate (Functions の Emulator)", () => {
  it("ログインしていない呼び出しは unauthenticated を返す", async () => {
    const requestId = randomUUID();
    const response = await callFunction({
      name: "generate",
      idToken: null,
      data: { requestId, photoPath: `users/someone/photos/${requestId}` },
    });
    expect(response.status).toBe(401);
    expect((await response.json()).error.status).toBe("UNAUTHENTICATED");
  });

  it("匿名ログインだけ (カスタムクレーム無し) で呼べ、他人の写真のパスは invalid-argument を返す", async () => {
    const credential = await signInAnonymously(auth);
    const requestId = randomUUID();
    const response = await callFunction({
      name: "generate",
      idToken: await credential.user.getIdToken(),
      data: { requestId, photoPath: `users/someone-else/photos/${requestId}` },
    });
    expect(response.status).toBe(400);
    expect((await response.json()).error.status).toBe("INVALID_ARGUMENT");
  });
});
