import { initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, deleteUser, getAuth, signInAnonymously, signOut } from "firebase/auth";
import { Timestamp, doc, getDoc, setDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { ENFORCE_APP_CHECK } from "../../src/app_check";
import { REPORT_HIDE_THRESHOLD, defaultDisplayName } from "../../src/pvp_rules";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// 非同期 PvP の相手の取得 (fetchOpponents)・通報 (reportMonster)・ブロック (blockUser)・表示名 (getDisplayName・setDisplayName) を
// Auth・Firestore・Functions の Emulator で、複数のユーザーの図鑑と手持ちを置いて確かめる。

const projectId = "demo-snapmon";
const functionsBaseUrl = `http://127.0.0.1:5001/${projectId}/asia-northeast1`;

// Functions の Emulator は App Check のトークンを検証せずに中身だけを読む (auth_flow.test.ts と同じ署名の無い JWT)。
const fakeAppCheckToken = [
  Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ sub: "1:000000000000:web:emulator", aud: [`projects/${projectId}`] })).toString("base64url"),
  "",
].join(".");

const app = initializeApp({ projectId, apiKey: "demo-api-key" }, "pvp-test");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });

let testEnvironment: RulesTestEnvironment;

/** ログインしたテストのユーザー。 */
interface TestUser {
  uid: string;
  idToken: string;
}

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
  user,
  appCheckToken,
  data,
}: {
  name: string;
  user: TestUser;
  appCheckToken: string | null;
  data: unknown;
}): Promise<Response> {
  return fetch(`${functionsBaseUrl}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${user.idToken}`,
      ...(appCheckToken ? { "X-Firebase-AppCheck": appCheckToken } : {}),
    },
    body: JSON.stringify({ data }),
  });
}

/** [user] で callable [name] を呼び、200 を確かめて result を返す。 */
async function callOk<Result>({ name, user, data }: { name: string; user: TestUser; data: unknown }): Promise<Result> {
  const response = await callFunction({ name, user, appCheckToken: fakeAppCheckToken, data });
  expect(response.status, `${name}: ${await response.clone().text()}`).toBe(200);
  return ((await response.json()) as { result: Result }).result;
}

/**
 * 匿名ログインし (カスタムクレーム無し)、モンスターを生成した後のユーザーと同じく `users/{uid}` を Rules を通さずに作って返す
 * (通報・ブロックは相手を探した後にしか呼ばれず、相手を探すには生成で生まれた手持ちが要るため)。
 * 1 つの Auth で次々にログインし直すため、ログインした時点の ID トークンを持って返す (トークンの期限 1 時間はテストより長い)。
 */
async function signInUser(): Promise<TestUser> {
  await signOut(auth);
  const credential = await signInAnonymously(auth);
  await markGenerated({ uid: credential.user.uid });
  return { uid: credential.user.uid, idToken: await credential.user.getIdToken() };
}

/** [uid] に、モンスターを生成した時と同じく `users/{uid}` を Rules を通さずに作る。 */
async function markGenerated({ uid }: { uid: string }): Promise<void> {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), `users/${uid}`), { dailyGeneration: { date: "2000-01-01", count: 1 } }, { merge: true });
  });
}

/** 他人に返してはいけない元の写真の参照。応答に含まれないことを確かめるため、uid と monsterId から見分けられる値にする。 */
function secretPhotoPath({ uid, monsterId }: { uid: string; monsterId: string }): string {
  return `users/${uid}/photos/secret-photo-${monsterId}`;
}

/**
 * [uid] の図鑑に [levels] のレベルのモンスター (MonsterDocument の形) を置き、その ID を手持ちにする。
 * [updatedAtMillis] は手持ちを変えた時刻 (候補を新しい順に読むため)。Rules を通さずに書く。
 */
async function seedParty({
  uid,
  levels,
  updatedAtMillis,
}: {
  uid: string;
  levels: number[];
  updatedAtMillis: number;
}): Promise<string[]> {
  const monsterIds = levels.map((_, index) => `${uid}-monster-${index}`);
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    for (const [index, monsterId] of monsterIds.entries()) {
      await setDoc(doc(firestore, `users/${uid}/monsters/${monsterId}`), {
        definition: {
          id: monsterId,
          sourcePhotoReference: secretPhotoPath({ uid, monsterId }),
          name: `${uid} のモンスター ${index}`,
          encyclopediaText: "まいにち あたたかい のみものを はこぶ",
          elementTypeIds: ["heat"],
          learnset: [{ moveId: "warm-touch", unlockLevel: 1 }],
          baseStats: { hitPoints: 50, attack: 50, defense: 50, speed: 50 },
          individualValues: { hitPoints: 1, attack: 2, defense: 3, speed: 4 },
          statCalculationVersion: 1,
          masterVersion: 1,
        },
        level: levels[index],
        experience: 0,
        artPath: `monsters/${monsterId}/art.png`,
        decoration: { eyes: "round" },
        decorationVersion: 1,
        subjectDescription: { what: `secret-subject-${monsterId}` },
        categoryIds: [`secret-category-${monsterId}`],
        definitionIds: [`definition-${monsterId}`],
        generationRequestId: `secret-request-${monsterId}`,
        createdAt: Timestamp.fromMillis(0),
      });
    }
    await setDoc(doc(firestore, `users/${uid}/party/current`), {
      monsterIds,
      updatedAt: Timestamp.fromMillis(updatedAtMillis),
    });
  });
  // fetchOpponents は users/{uid} の無い持ち主を、アカウントの削除を消し終えたものとして候補に出さない
  await markGenerated({ uid });
  return monsterIds;
}

/** fetchOpponents が返す相手 1 人。 */
interface Opponent {
  opponentUid: string;
  displayName: string;
  monsters: { definition: Record<string, unknown>; level: number; artPath: string; definitionIds: string[] }[];
}

/** [user] で fetchOpponents を呼び、返った相手を返す。 */
async function fetchOpponents({ user }: { user: TestUser }): Promise<Opponent[]> {
  return (await callOk<{ opponents: Opponent[] }>({ name: "fetchOpponents", user, data: null })).opponents;
}

describe("fetchOpponents", () => {
  it("他のユーザーの手持ちを、平均レベルが近い 3 人まで返し、自分は入らない", async () => {
    const player = await signInUser();
    await seedParty({ uid: player.uid, levels: [10, 10], updatedAtMillis: 1 });
    await seedParty({ uid: "near", levels: [9, 11], updatedAtMillis: 2 });
    await seedParty({ uid: "middle", levels: [14], updatedAtMillis: 3 });
    await seedParty({ uid: "far", levels: [80, 90, 100], updatedAtMillis: 4 });
    await seedParty({ uid: "exact", levels: [10], updatedAtMillis: 5 });

    const opponents = await fetchOpponents({ user: player });
    expect(opponents.map((opponent) => opponent.opponentUid)).toEqual(["exact", "near", "middle"]);
    expect(opponents[1]).toMatchObject({
      opponentUid: "near",
      displayName: defaultDisplayName("near"),
      monsters: [
        { level: 9, artPath: "monsters/near-monster-0/art.png", definitionIds: ["definition-near-monster-0"] },
        { level: 11, artPath: "monsters/near-monster-1/art.png", definitionIds: ["definition-near-monster-1"] },
      ],
    });
    expect(opponents[1].monsters[0].definition).toMatchObject({ id: "near-monster-0", name: "near のモンスター 0" });
  });

  it("元の写真の参照・被写体の説明・分類・生成の要求 ID を他のユーザーに返さない", async () => {
    const player = await signInUser();
    await seedParty({ uid: player.uid, levels: [5], updatedAtMillis: 1 });
    const monsterIds = await seedParty({ uid: "other", levels: [5, 6], updatedAtMillis: 2 });

    const response = await callFunction({ name: "fetchOpponents", user: player, appCheckToken: fakeAppCheckToken, data: null });
    const responseText = await response.text();
    expect(responseText).toContain("other-monster-0");
    expect(responseText).not.toContain("photos/");
    expect(responseText).not.toContain("sourcePhotoReference");
    for (const monsterId of monsterIds) {
      for (const secret of [
        secretPhotoPath({ uid: "other", monsterId }),
        `secret-subject-${monsterId}`,
        `secret-category-${monsterId}`,
        `secret-request-${monsterId}`,
      ]) {
        expect(responseText).not.toContain(secret);
      }
    }
  });

  it("図鑑に無いモンスターは手持ちから落とし、全部無い相手は候補から外す", async () => {
    const player = await signInUser();
    await seedParty({ uid: player.uid, levels: [5], updatedAtMillis: 1 });
    await seedParty({ uid: "partial", levels: [5], updatedAtMillis: 2 });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      await setDoc(doc(firestore, "users/partial/party/current"), {
        monsterIds: ["partial-monster-0", "deleted-monster"],
        updatedAt: Timestamp.fromMillis(2),
      });
      await setDoc(doc(firestore, "users/ghost/party/current"), { monsterIds: ["deleted-monster"], updatedAt: Timestamp.fromMillis(3) });
      await setDoc(doc(firestore, "users/ghost"), { dailyGeneration: { date: "2000-01-01", count: 1 } });
    });

    const opponents = await fetchOpponents({ user: player });
    expect(opponents.map((opponent) => opponent.opponentUid)).toEqual(["partial"]);
    expect(opponents[0].monsters.map((monster) => monster.definition.id)).toEqual(["partial-monster-0"]);
  });

  it("自分の手持ちが空なら相手を探せない", async () => {
    const player = await signInUser();
    await seedParty({ uid: "other", levels: [5], updatedAtMillis: 2 });
    const response = await callFunction({ name: "fetchOpponents", user: player, appCheckToken: fakeAppCheckToken, data: null });
    expect(response.status).toBe(400);
    expect(await response.text()).toContain("FAILED_PRECONDITION");
  });

  it("ブロックした相手とブロックされた相手は、互いの候補から消える", async () => {
    const blocker = await signInUser();
    await seedParty({ uid: blocker.uid, levels: [5], updatedAtMillis: 1 });
    const blocked = await signInUser();
    await seedParty({ uid: blocked.uid, levels: [5], updatedAtMillis: 2 });
    await seedParty({ uid: "bystander", levels: [5], updatedAtMillis: 3 });

    expect((await fetchOpponents({ user: blocker })).map((opponent) => opponent.opponentUid)).toContain(blocked.uid);
    expect(await callOk({ name: "blockUser", user: blocker, data: { blockedUid: blocked.uid } })).toEqual({ blocked: true });
    // ブロックし直しても 1 件のまま
    expect(await callOk({ name: "blockUser", user: blocker, data: { blockedUid: blocked.uid } })).toEqual({ blocked: true });

    expect((await fetchOpponents({ user: blocker })).map((opponent) => opponent.opponentUid)).toEqual(["bystander"]);
    expect((await fetchOpponents({ user: blocked })).map((opponent) => opponent.opponentUid)).toEqual(["bystander"]);
  });

  it("自分が通報したモンスターの持ち主は、自分の候補から消える", async () => {
    const reporter = await signInUser();
    await seedParty({ uid: reporter.uid, levels: [5], updatedAtMillis: 1 });
    const [reportedMonsterId] = await seedParty({ uid: "reported", levels: [5], updatedAtMillis: 2 });
    await seedParty({ uid: "bystander", levels: [5], updatedAtMillis: 3 });

    expect(
      await callOk({
        name: "reportMonster",
        user: reporter,
        data: { monsterOwnerUid: "reported", monsterId: reportedMonsterId, reason: "inappropriate_picture" },
      }),
    ).toEqual({ reported: true });
    expect((await fetchOpponents({ user: reporter })).map((opponent) => opponent.opponentUid)).toEqual(["bystander"]);
  });

  it(`${REPORT_HIDE_THRESHOLD} 人から通報されたモンスターの持ち主は全員の候補から消え、それより少なければ残る`, async () => {
    const [reportedMonsterId] = await seedParty({ uid: "reported", levels: [5], updatedAtMillis: 1 });
    const viewer = await signInUser();
    await seedParty({ uid: viewer.uid, levels: [5], updatedAtMillis: 2 });
    for (let count = 0; count < REPORT_HIDE_THRESHOLD; count++) {
      expect((await fetchOpponents({ user: viewer })).map((opponent) => opponent.opponentUid)).toContain("reported");
      const reporter = await signInUser();
      await callOk({
        name: "reportMonster",
        user: reporter,
        data: { monsterOwnerUid: "reported", monsterId: reportedMonsterId, reason: "other" },
      });
    }
    expect((await fetchOpponents({ user: viewer })).map((opponent) => opponent.opponentUid)).not.toContain("reported");
  });

  it("App Check のトークンが無い呼び出しは、強制している時 (src/app_check.ts) だけ弾く", async () => {
    const user = await signInUser();
    for (const name of ["fetchOpponents", "reportMonster", "blockUser", "getDisplayName", "setDisplayName"]) {
      const response = await callFunction({ name, user, appCheckToken: null, data: {} });
      if (ENFORCE_APP_CHECK) {
        expect(response.status, name).toBe(401);
      } else {
        // 強制していない時は本体まで届く (getDisplayName は 200、fetchOpponents は手持ちが空のため 400、ほかは data が足りないため 400)
        expect(response.status, name).not.toBe(401);
      }
    }
  });
});

describe("reportMonster", () => {
  /** reports と reportedMonsters を Rules を通さずに読む。 */
  async function readReportState({ reportId, monsterId }: { reportId: string; monsterId: string }) {
    let state: { report: Record<string, unknown> | undefined; counter: Record<string, unknown> | undefined } = {
      report: undefined,
      counter: undefined,
    };
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      state = {
        report: (await getDoc(doc(firestore, `reports/${reportId}`))).data(),
        counter: (await getDoc(doc(firestore, `reportedMonsters/${monsterId}`))).data(),
      };
    });
    return state;
  }

  it("通報を残し、同じユーザーが通報し直しても数を増やさない", async () => {
    const reporter = await signInUser();
    const [monsterId] = await seedParty({ uid: "owner", levels: [5], updatedAtMillis: 1 });
    for (const reason of ["inappropriate_text", "other"]) {
      await callOk({ name: "reportMonster", user: reporter, data: { monsterOwnerUid: "owner", monsterId, reason } });
    }
    const { report, counter } = await readReportState({ reportId: `${reporter.uid}_${monsterId}`, monsterId });
    expect(report).toMatchObject({
      reporterUid: reporter.uid,
      monsterOwnerUid: "owner",
      monsterId,
      monsterName: "owner のモンスター 0",
      monsterArtPath: `monsters/${monsterId}/art.png`,
      reason: "inappropriate_text",
    });
    expect(counter).toMatchObject({ monsterOwnerUid: "owner", reporterCount: 1 });
  });

  it("自分のモンスター・無いモンスター・決めていない理由は通報できない", async () => {
    const reporter = await signInUser();
    const [ownMonsterId] = await seedParty({ uid: reporter.uid, levels: [5], updatedAtMillis: 1 });
    const [otherMonsterId] = await seedParty({ uid: "owner", levels: [5], updatedAtMillis: 2 });
    const cases: { data: unknown; status: number }[] = [
      { data: { monsterOwnerUid: reporter.uid, monsterId: ownMonsterId, reason: "other" }, status: 400 },
      { data: { monsterOwnerUid: "owner", monsterId: "missing", reason: "other" }, status: 404 },
      { data: { monsterOwnerUid: "owner", monsterId: otherMonsterId, reason: "boring" }, status: 400 },
      { data: { monsterOwnerUid: "owner/x", monsterId: otherMonsterId, reason: "other" }, status: 400 },
    ];
    for (const { data, status } of cases) {
      const response = await callFunction({ name: "reportMonster", user: reporter, appCheckToken: fakeAppCheckToken, data });
      expect(response.status, JSON.stringify(data)).toBe(status);
    }
  });
});

describe("アカウントの削除の途中", () => {
  it("通報・ブロック・表示名の変更を断り、本人のデータを書かない", async () => {
    const user = await signInUser();
    const [monsterId] = await seedParty({ uid: "owner", levels: [5], updatedAtMillis: 1 });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${user.uid}`), { accountDeletionStartedAt: Timestamp.fromMillis(0) }, { merge: true });
    });
    for (const [name, data] of [
      ["reportMonster", { monsterOwnerUid: "owner", monsterId, reason: "other" }],
      ["blockUser", { blockedUid: "owner" }],
      ["setDisplayName", { displayName: "ばんざい" }],
    ] as const) {
      const response = await callFunction({ name, user, appCheckToken: fakeAppCheckToken, data });
      expect(response.status, name).toBe(400);
      expect(await response.text(), name).toContain("FAILED_PRECONDITION");
    }
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      expect((await getDoc(doc(firestore, `reports/${user.uid}_${monsterId}`))).exists()).toBe(false);
      expect((await getDoc(doc(firestore, `blocks/${user.uid}_owner`))).exists()).toBe(false);
      expect((await getDoc(doc(firestore, `users/${user.uid}`))).get("displayName")).toBeUndefined();
    });
  });
});

describe("アカウントの削除を消し終えた後 (別の端末の ID トークンは期限まで通る)", () => {
  it("通報・ブロック・表示名の変更を断り、本人のデータを作り直さない", async () => {
    await signOut(auth);
    const credential = await signInAnonymously(auth);
    const user = { uid: credential.user.uid, idToken: await credential.user.getIdToken() };
    const [monsterId] = await seedParty({ uid: "owner", levels: [5], updatedAtMillis: 1 });
    // 削除は Auth のユーザーを users/{uid} より先に消す (account.ts の deleteAccountData)。users/{uid} はまだ無い
    await deleteUser(credential.user);
    for (const [name, data] of [
      ["reportMonster", { monsterOwnerUid: "owner", monsterId, reason: "other" }],
      ["blockUser", { blockedUid: "owner" }],
      ["setDisplayName", { displayName: "ばんざい" }],
    ] as const) {
      const response = await callFunction({ name, user, appCheckToken: fakeAppCheckToken, data });
      expect(response.status, name).toBe(400);
      expect(await response.text(), name).toContain("FAILED_PRECONDITION");
    }
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      const firestore = context.firestore();
      expect((await getDoc(doc(firestore, `users/${user.uid}`))).exists()).toBe(false);
      expect((await getDoc(doc(firestore, `reports/${user.uid}_${monsterId}`))).exists()).toBe(false);
      expect((await getDoc(doc(firestore, `blocks/${user.uid}_owner`))).exists()).toBe(false);
    });
  });
});

describe("持ち主のアカウントの削除の途中", () => {
  it("その持ち主は候補に出さない (絵は消え、通報もできないため)", async () => {
    const viewer = await signInUser();
    await seedParty({ uid: viewer.uid, levels: [5], updatedAtMillis: 1 });
    await seedParty({ uid: "deleting", levels: [5], updatedAtMillis: 2 });
    await seedParty({ uid: "bystander", levels: [5], updatedAtMillis: 3 });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/deleting"), { accountDeletionStartedAt: Timestamp.fromMillis(0) }, { merge: true });
    });
    expect((await fetchOpponents({ user: viewer })).map((opponent) => opponent.opponentUid)).toEqual(["bystander"]);
  });

  it("そのモンスターへの通報は無いものとして断り、通報の数を作らない", async () => {
    const reporter = await signInUser();
    const [monsterId] = await seedParty({ uid: "owner", levels: [5], updatedAtMillis: 1 });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/owner"), { accountDeletionStartedAt: Timestamp.fromMillis(0) }, { merge: true });
    });
    const response = await callFunction({
      name: "reportMonster",
      user: reporter,
      appCheckToken: fakeAppCheckToken,
      data: { monsterOwnerUid: "owner", monsterId, reason: "other" },
    });
    expect(response.status).toBe(404);
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      expect((await getDoc(doc(context.firestore(), `reportedMonsters/${monsterId}`))).exists()).toBe(false);
    });
  });
});

describe("blockUser", () => {
  it("自分・空・パスを含む uid はブロックできない", async () => {
    const user = await signInUser();
    for (const blockedUid of [user.uid, "", "a/b", undefined]) {
      const response = await callFunction({ name: "blockUser", user, appCheckToken: fakeAppCheckToken, data: { blockedUid } });
      expect(response.status, String(blockedUid)).toBe(400);
    }
  });
});

describe("表示名", () => {
  it("設定していなければ既定の名前を返し、変えると本人と相手の候補の両方に出る", async () => {
    const owner = await signInUser();
    await seedParty({ uid: owner.uid, levels: [5], updatedAtMillis: 1 });
    expect(await callOk({ name: "getDisplayName", user: owner, data: null })).toEqual({
      displayName: defaultDisplayName(owner.uid),
    });
    expect(await callOk({ name: "setDisplayName", user: owner, data: { displayName: "  ばんざい " } })).toEqual({
      displayName: "ばんざい",
    });
    expect(await callOk({ name: "getDisplayName", user: owner, data: null })).toEqual({ displayName: "ばんざい" });

    const viewer = await signInUser();
    await seedParty({ uid: viewer.uid, levels: [5], updatedAtMillis: 2 });
    expect(await fetchOpponents({ user: viewer })).toMatchObject([{ opponentUid: owner.uid, displayName: "ばんざい" }]);
  });

  it("禁止語・長すぎる名前は受け付けず、理由を返して保存しない", async () => {
    const user = await signInUser();
    for (const displayName of ["ピカチュウ", "あ".repeat(13), ""]) {
      const response = await callFunction({
        name: "setDisplayName",
        user,
        appCheckToken: fakeAppCheckToken,
        data: { displayName },
      });
      expect(response.status, displayName).toBe(400);
    }
    expect(await callOk({ name: "getDisplayName", user, data: null })).toEqual({ displayName: defaultDisplayName(user.uid) });
  });
});
