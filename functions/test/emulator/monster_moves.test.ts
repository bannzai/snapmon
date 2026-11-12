import { deleteApp as deleteAdminApp, getApps, initializeApp as initializeAdminApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously, signOut, type User } from "firebase/auth";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// 対戦の前に選ぶ技の callable (selectMonsterMoves) を Auth・Firestore・Functions の Emulator で確かめる。

const projectID = "demo-snapmon";
const functionsBaseURL = `http://127.0.0.1:5001/${projectID}/asia-northeast1`;

// Functions の Emulator は App Check のトークンを検証せずに中身だけを読む (battle.test.ts と同じ署名の無い JWT)。
const fakeAppCheckToken = [
  Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ sub: "1:000000000000:web:emulator", aud: [`projects/${projectID}`] })).toString("base64url"),
  "",
].join(".");

const app = initializeApp({ projectId: projectID, apiKey: "demo-api-key" }, "monster-moves-test");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
const adminApp = getApps().find((existing) => existing.name === "monster-moves-admin-test") ?? initializeAdminApp({ projectId: projectID }, "monster-moves-admin-test");
const firestore = getFirestore(adminApp);

afterAll(async () => {
  await deleteApp(app);
  await deleteAdminApp(adminApp);
});

beforeEach(async () => {
  await signOut(auth);
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${projectID}/databases/(default)/documents`, { method: "DELETE" });
});

/** 匿名ログインしたユーザーと、Lv.5 で a・b・c (Lv.1)・d (Lv.10) を覚え、Action Card の技 x を持つ図鑑のモンスター m1 を置く。 */
async function signInUser(): Promise<User> {
  const user = (await signInAnonymously(auth)).user;
  await firestore.doc(`users/${user.uid}`).set({ displayName: "tester" });
  await firestore.doc(`users/${user.uid}/monsters/m1`).set({
    level: 5,
    experience: 0,
    actionCardMoveIDs: ["x"],
    definition: {
      id: "m1",
      learnset: [
        { moveID: "a", unlockLevel: 1 },
        { moveID: "b", unlockLevel: 1 },
        { moveID: "c", unlockLevel: 1 },
        { moveID: "d", unlockLevel: 10 },
      ],
    },
  });
  return user;
}

/** selectMonsterMoves を [user] で呼び、HTTP の状態コードと本文を返す。 */
async function selectMonsterMoves({ user, data }: { user: User; data: unknown }): Promise<{ status: number; body: any }> {
  const response = await fetch(`${functionsBaseURL}/selectMonsterMoves`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${await user.getIdToken()}`,
      "X-Firebase-AppCheck": fakeAppCheckToken,
    },
    body: JSON.stringify({ data }),
  });
  return { status: response.status, body: await response.json() };
}

describe("selectMonsterMoves", () => {
  it("持っている技 (開放した技と Action Card の技) を選んだ順で保存し、同じ値で呼び直しても同じ", async () => {
    const user = await signInUser();
    for (let attempt = 0; attempt < 2; attempt++) {
      const { status, body } = await selectMonsterMoves({ user, data: { monsterID: "m1", moveIDs: ["x", "c", "a"] } });
      expect(status).toBe(200);
      expect(body.result).toEqual({ selectedMoveIDs: ["x", "c", "a"] });
      expect((await firestore.doc(`users/${user.uid}/monsters/m1`).get()).get("selectedMoveIDs")).toEqual(["x", "c", "a"]);
    }
  });

  it.each([
    ["まだ開放していない技", ["a", "d"]],
    ["空", []],
    ["重複", ["a", "a"]],
    ["5 つ", ["a", "b", "c", "x", "a"]],
  ])("%s は invalid-argument で断り、保存しない", async (_, moveIDs) => {
    const user = await signInUser();
    const { status, body } = await selectMonsterMoves({ user, data: { monsterID: "m1", moveIDs } });
    expect(status).toBe(400);
    expect(body.error.status).toBe("INVALID_ARGUMENT");
    expect((await firestore.doc(`users/${user.uid}/monsters/m1`).get()).get("selectedMoveIDs")).toBeUndefined();
  });

  it("図鑑にいないモンスターは not-found で断る", async () => {
    const user = await signInUser();
    const { status, body } = await selectMonsterMoves({ user, data: { monsterID: "other", moveIDs: ["a"] } });
    expect(status).toBe(404);
    expect(body.error.status).toBe("NOT_FOUND");
  });
});
