import { initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously, signOut, type User } from "firebase/auth";
import { doc, getDoc, setDoc, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { DAILY_BATTLE_LIMIT, MAXIMUM_LEVEL, battleDayKey } from "../../src/battle_rules";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// バトルの開始 (startBattle) と結果の記録 (recordBattle) を Auth・Firestore・Functions の Emulator で確かめる。

const projectId = "demo-snapmon";
const functionsBaseUrl = `http://127.0.0.1:5001/${projectId}/asia-northeast1`;

// Functions の Emulator は App Check のトークンを検証せずに中身だけを読む (auth_flow.test.ts と同じ署名の無い JWT)。
const fakeAppCheckToken = [
  Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ sub: "1:000000000000:web:emulator", aud: [`projects/${projectId}`] })).toString("base64url"),
  "",
].join(".");

const app = initializeApp({ projectId, apiKey: "demo-api-key" }, "battle-test");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });

let testEnvironment: RulesTestEnvironment;

beforeAll(async () => {
  testEnvironment = await initializeTestEnvironment({ projectId });
});

afterAll(async () => {
  await testEnvironment.cleanup();
  await deleteApp(app);
});

beforeEach(async () => {
  await signOut(auth);
  await testEnvironment.clearFirestore();
});

/** Functions の callable [name] をプロトコル (POST の JSON `{ data }`) で呼び、HTTP の応答を返す。 */
async function callFunction({
  name,
  idToken,
  appCheckToken,
  data,
}: {
  name: string;
  idToken: string;
  appCheckToken: string | null;
  data: unknown;
}): Promise<Response> {
  return fetch(`${functionsBaseUrl}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
      ...(appCheckToken ? { "X-Firebase-AppCheck": appCheckToken } : {}),
    },
    body: JSON.stringify({ data }),
  });
}

/** 匿名ログインし、[ageVerified] が true なら confirmAge でクレームを付けたユーザーを返す。 */
async function signInUser({ ageVerified }: { ageVerified: boolean }): Promise<User> {
  const credential = await signInAnonymously(auth);
  if (ageVerified) {
    const response = await callFunction({
      name: "confirmAge",
      idToken: await credential.user.getIdToken(),
      appCheckToken: fakeAppCheckToken,
      data: { birthYear: 2000, birthMonth: 1 },
    });
    expect(response.status).toBe(200);
    await credential.user.getIdToken(true);
  }
  return credential.user;
}

/** [uid] の図鑑に、[levels] のレベルのモンスターを Rules を通さずに置く。 */
async function seedMonsters({ uid, levels }: { uid: string; levels: Record<string, number> }): Promise<void> {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    for (const [monsterId, level] of Object.entries(levels)) {
      await setDoc(doc(context.firestore(), `users/${uid}/monsters/${monsterId}`), { name: monsterId, level, experience: 0 });
    }
  });
}

/** [uid] の図鑑のモンスター [monsterId] を Rules を通さずに読む。 */
async function readMonster({ uid, monsterId }: { uid: string; monsterId: string }) {
  let data: Record<string, unknown> | undefined;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    data = (await getDoc(doc(context.firestore(), `users/${uid}/monsters/${monsterId}`))).data();
  });
  return data;
}

/** startBattle を呼んで battleId を返す。 */
async function startBattle({ user, partyMonsterIds }: { user: User; partyMonsterIds: string[] }): Promise<string> {
  const response = await callFunction({
    name: "startBattle",
    idToken: await user.getIdToken(),
    appCheckToken: fakeAppCheckToken,
    data: { partyMonsterIds },
  });
  expect(response.status).toBe(200);
  return ((await response.json()) as { result: { battleId: string } }).result.battleId;
}

/** recordBattle を呼び、HTTP の応答を返す。 */
async function recordBattle({
  user,
  battleId,
  participantMonsterIds,
}: {
  user: User;
  battleId: string;
  participantMonsterIds: string[];
}): Promise<Response> {
  return callFunction({
    name: "recordBattle",
    idToken: await user.getIdToken(),
    appCheckToken: fakeAppCheckToken,
    data: { battleId, participantMonsterIds, winner: "player", turnCount: 4 },
  });
}

describe("startBattle と recordBattle", () => {
  it("戦闘に出た手持ちだけのレベルが 1 上がり、出なかった手持ちは変わらない", async () => {
    const user = await signInUser({ ageVerified: true });
    await seedMonsters({ uid: user.uid, levels: { m1: 5, m2: 7, m3: 1 } });
    const battleId = await startBattle({ user, partyMonsterIds: ["m1", "m2", "m3"] });

    const response = await recordBattle({ user, battleId, participantMonsterIds: ["m1", "m2"] });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ result: { levels: { m1: 6, m2: 8 } } });
    expect(await readMonster({ uid: user.uid, monsterId: "m1" })).toMatchObject({ level: 6, experience: 1 });
    expect(await readMonster({ uid: user.uid, monsterId: "m2" })).toMatchObject({ level: 8, experience: 1 });
    expect(await readMonster({ uid: user.uid, monsterId: "m3" })).toMatchObject({ level: 1, experience: 0 });
  });

  it("同じ battleId の再送ではレベルを上げず、記録済みのレベルを返す", async () => {
    const user = await signInUser({ ageVerified: true });
    await seedMonsters({ uid: user.uid, levels: { m1: 5 } });
    const battleId = await startBattle({ user, partyMonsterIds: ["m1"] });

    expect((await recordBattle({ user, battleId, participantMonsterIds: ["m1"] })).status).toBe(200);
    const resent = await recordBattle({ user, battleId, participantMonsterIds: ["m1"] });
    expect(resent.status).toBe(200);
    expect(await resent.json()).toEqual({ result: { levels: { m1: 6 } } });
    expect(await readMonster({ uid: user.uid, monsterId: "m1" })).toMatchObject({ level: 6, experience: 1 });
  });

  it("上限のレベルでは上がらない", async () => {
    const user = await signInUser({ ageVerified: true });
    await seedMonsters({ uid: user.uid, levels: { m1: MAXIMUM_LEVEL } });
    const battleId = await startBattle({ user, partyMonsterIds: ["m1"] });

    const response = await recordBattle({ user, battleId, participantMonsterIds: ["m1"] });
    expect(await response.json()).toEqual({ result: { levels: { m1: MAXIMUM_LEVEL } } });
  });

  it("開始時の手持ちに無いモンスターは上げられない", async () => {
    const user = await signInUser({ ageVerified: true });
    await seedMonsters({ uid: user.uid, levels: { m1: 5, m2: 5 } });
    const battleId = await startBattle({ user, partyMonsterIds: ["m1"] });

    const response = await recordBattle({ user, battleId, participantMonsterIds: ["m1", "m2"] });
    expect(response.status).toBe(400);
    expect(await readMonster({ uid: user.uid, monsterId: "m1" })).toMatchObject({ level: 5 });
    expect(await readMonster({ uid: user.uid, monsterId: "m2" })).toMatchObject({ level: 5 });
  });

  it("図鑑に無いモンスターではバトルを始められない", async () => {
    const user = await signInUser({ ageVerified: true });
    const response = await callFunction({
      name: "startBattle",
      idToken: await user.getIdToken(),
      appCheckToken: fakeAppCheckToken,
      data: { partyMonsterIds: ["missing"] },
    });
    expect(response.status).toBe(404);
  });

  it("始まっていない battleId は記録できない", async () => {
    const user = await signInUser({ ageVerified: true });
    await seedMonsters({ uid: user.uid, levels: { m1: 5 } });
    const response = await recordBattle({ user, battleId: "never-started", participantMonsterIds: ["m1"] });
    expect(response.status).toBe(404);
  });

  it(`1 日 ${DAILY_BATTLE_LIMIT} 戦を記録した後は記録できず、レベルも上がらない`, async () => {
    const user = await signInUser({ ageVerified: true });
    await seedMonsters({ uid: user.uid, levels: { m1: 5 } });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${user.uid}`), {
        dailyBattleDate: battleDayKey({ now: new Date() }),
        dailyBattleCount: DAILY_BATTLE_LIMIT,
      });
    });
    const battleId = await startBattle({ user, partyMonsterIds: ["m1"] });

    const response = await recordBattle({ user, battleId, participantMonsterIds: ["m1"] });
    expect(response.status).toBe(429);
    expect(await readMonster({ uid: user.uid, monsterId: "m1" })).toMatchObject({ level: 5 });
  });

  it("前の日の数は今日の上限に数えない", async () => {
    const user = await signInUser({ ageVerified: true });
    await seedMonsters({ uid: user.uid, levels: { m1: 5 } });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${user.uid}`), {
        dailyBattleDate: "2000-01-01",
        dailyBattleCount: DAILY_BATTLE_LIMIT,
      });
    });
    const battleId = await startBattle({ user, partyMonsterIds: ["m1"] });

    expect((await recordBattle({ user, battleId, participantMonsterIds: ["m1"] })).status).toBe(200);
  });

  it("年齢の確認を通っていないユーザーは呼べない", async () => {
    const user = await signInUser({ ageVerified: false });
    await seedMonsters({ uid: user.uid, levels: { m1: 5 } });
    const response = await callFunction({
      name: "startBattle",
      idToken: await user.getIdToken(),
      appCheckToken: fakeAppCheckToken,
      data: { partyMonsterIds: ["m1"] },
    });
    expect(response.status).toBe(403);
  });

  it("App Check のトークンが無い呼び出しは弾く", async () => {
    const user = await signInUser({ ageVerified: true });
    await seedMonsters({ uid: user.uid, levels: { m1: 5 } });
    for (const name of ["startBattle", "recordBattle"]) {
      const response = await callFunction({
        name,
        idToken: await user.getIdToken(),
        appCheckToken: null,
        data: { partyMonsterIds: ["m1"] },
      });
      expect(response.status, name).toBe(401);
    }
  });
});

describe("クライアントからのレベルの書き込み", () => {
  it("本人でも図鑑のモンスターの level を直接書くと Rules で拒否される", async () => {
    await seedMonsters({ uid: "alice", levels: { m1: 5 } });
    const firestore = testEnvironment.authenticatedContext("alice", { ageVerified: true }).firestore();
    await expect(updateDoc(doc(firestore, "users/alice/monsters/m1"), { level: 999 })).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(await readMonster({ uid: "alice", monsterId: "m1" })).toMatchObject({ level: 5 });
  });
});
