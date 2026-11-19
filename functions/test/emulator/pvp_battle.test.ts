import { initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { deleteApp, initializeApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInAnonymously, signOut } from "firebase/auth";
import { Timestamp, doc, getDoc, setDoc, updateDoc, type DocumentData } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import { DAILY_BATTLE_LIMIT } from "../../src/battle_rules";
import { MATCH_TICKET_FRESH_SECONDS, TURN_DEADLINE_GRACE_SECONDS, TURN_SECONDS } from "../../src/pvp_battle_rules";
import { REPORT_HIDE_THRESHOLD, defaultDisplayName } from "../../src/pvp_rules";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// 人との対戦の組み合わせ (joinPvpMatch・leavePvpMatch)・行動の受け渡し (submitPvpAction)・時間切れ (claimPvpTimeout)・
// 勝敗の確定 (reportPvpResult) と、対戦の後のレベルの記録 (recordBattle) を、Auth・Firestore・Functions の Emulator で 2 人以上の利用者を置いて確かめる。

const projectID = "demo-snapmon";
const functionsBaseURL = `http://127.0.0.1:5001/${projectID}/asia-northeast1`;

// Functions の Emulator は App Check のトークンを検証せずに中身だけを読む (auth_flow.test.ts と同じ署名の無い JWT)。
const fakeAppCheckToken = [
  Buffer.from(JSON.stringify({ alg: "none", typ: "JWT" })).toString("base64url"),
  Buffer.from(JSON.stringify({ sub: "1:000000000000:web:emulator", aud: [`projects/${projectID}`] })).toString("base64url"),
  "",
].join(".");

const app = initializeApp({ projectId: projectID, apiKey: "demo-api-key" }, "pvp-battle-test");
const auth = getAuth(app);
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });

let testEnvironment: RulesTestEnvironment;

/** ログインしたテストの利用者。 */
interface TestUser {
  /** Auth の Emulator が払い出した uid。 */
  uid: string;
  /** callable の呼び出しに付ける ID トークン。 */
  idToken: string;
}

beforeAll(async () => {
  testEnvironment = await initializeTestEnvironment({ projectId: projectID });
});

afterAll(async () => {
  await testEnvironment.cleanup();
  await deleteApp(app);
});

beforeEach(async () => {
  await signOut(auth);
  await testEnvironment.clearFirestore();
});

/** [user] で callable [name] を呼び、HTTP の応答を返す。 */
async function callFunction({ name, user, data }: { name: string; user: TestUser; data: unknown }): Promise<Response> {
  return fetch(`${functionsBaseURL}/${name}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${user.idToken}`,
      "X-Firebase-AppCheck": fakeAppCheckToken,
    },
    body: JSON.stringify({ data }),
  });
}

/** [user] で callable [name] を呼び、200 を確かめて result を返す。 */
async function callOk<Result>({ name, user, data }: { name: string; user: TestUser; data: unknown }): Promise<Result> {
  const response = await callFunction({ name, user, data });
  expect(response.status, `${name}: ${await response.clone().text()}`).toBe(200);
  return ((await response.json()) as { result: Result }).result;
}

/** [user] で callable [name] を呼び、失敗した応答のエラーの種類 (`FAILED_PRECONDITION` 等) を返す。 */
async function callErrorStatus({ name, user, data }: { name: string; user: TestUser; data: unknown }): Promise<string> {
  return ((await (await callFunction({ name, user, data })).json()) as { error: { status: string } }).error.status;
}

/** Rules を通さずに [path] のドキュメントを読む。無ければ undefined。 */
async function readDocument({ path }: { path: string }): Promise<DocumentData | undefined> {
  let data: DocumentData | undefined;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    data = (await getDoc(doc(context.firestore(), path))).data();
  });
  return data;
}

/** 他人に渡してはいけない元の写真の参照。対戦のドキュメントに含まれないことを確かめるため、monsterID から見分けられる値にする。 */
function secretPhotoPath({ uid, monsterID }: { uid: string; monsterID: string }): string {
  return `users/${uid}/photos/secret-photo-${monsterID}`;
}

/**
 * 匿名ログインし、モンスターを生成した後の利用者と同じく `users/{uid}` と、[levels] のレベルのモンスターの図鑑と手持ちを Rules を通さずに置いて返す。
 * 1 つの Auth で次々にログインし直すため、ログインした時点の ID トークンを持って返す (トークンの期限 1 時間はテストより長い)。
 */
async function signInTrainer({ levels }: { levels: number[] }): Promise<TestUser> {
  await signOut(auth);
  const credential = await signInAnonymously(auth);
  const { uid } = credential.user;
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, `users/${uid}`), { dailyGeneration: { date: "2000-01-01", count: 1 } });
    for (const [index, level] of levels.entries()) {
      const monsterID = `${uid}-monster-${index}`;
      await setDoc(doc(firestore, `users/${uid}/monsters/${monsterID}`), {
        definition: {
          id: monsterID,
          sourcePhotoReference: secretPhotoPath({ uid, monsterID }),
          name: `モンスター ${index}`,
          encyclopediaText: "まいにち あたたかい のみものを はこぶ",
          elementTypeIDs: ["fire"],
          learnset: [{ moveID: "warm-touch", unlockLevel: 1 }],
          baseStats: { hitPoints: 50, attack: 50, defense: 50, speed: 50 },
          individualValues: { hitPoints: 1, attack: 2, defense: 3, speed: 4 },
          statCalculationVersion: 1,
          masterVersion: 1,
        },
        level,
        experience: 0,
        artPath: `monsters/${monsterID}/art.png`,
        decoration: { eyes: "round" },
        decorationVersion: 1,
        subjectDescription: { what: `secret-subject-${monsterID}` },
        categoryIDs: [`secret-category-${monsterID}`],
        definitionIDs: [`definition-${monsterID}`],
        generationRequestID: `secret-request-${monsterID}`,
        createdAt: Timestamp.fromMillis(0),
      });
    }
    await setDoc(doc(firestore, `users/${uid}/party/current`), {
      monsterIDs: levels.map((_, index) => `${uid}-monster-${index}`),
      updatedAt: Timestamp.fromMillis(0),
    });
  });
  return { uid, idToken: await credential.user.getIdToken() };
}

/** [user] で joinPvpMatch を呼び、組み合わされた対戦の ID (まだなら null) を返す。 */
async function joinMatch({ user, searchID, rulesVersion }: { user: TestUser; searchID: string; rulesVersion: string }): Promise<string | null> {
  return (await callOk<{ battleID: string | null }>({ name: "joinPvpMatch", user, data: { rulesVersion, searchID } })).battleID;
}

/** 先に待つ [host] と後から来る [guest] を組み合わせ、対戦の ID を返す。 */
async function matchTrainers({ host, guest }: { host: TestUser; guest: TestUser }): Promise<string> {
  expect(await joinMatch({ user: host, searchID: `search-${host.uid}`, rulesVersion: "1" })).toBeNull();
  const battleID = await joinMatch({ user: guest, searchID: `search-${guest.uid}`, rulesVersion: "1" });
  expect(battleID).not.toBeNull();
  return battleID!;
}

/** [user] で対戦 [battleID] の [round] 番目のターンに技 [moveID] を出し、HTTP の応答を返す。 */
async function submitMove({ user, battleID, round, moveID }: { user: TestUser; battleID: string; round: number; moveID: string }): Promise<Response> {
  return callFunction({ name: "submitPvpAction", user, data: { battleID, round, action: { kind: "move", moveID } } });
}

/** 対戦 [battleID] の今のターンの行動の期限を、Rules を通さずに過去にする (時間切れを待たずに確かめるため)。 */
async function expireTurnDeadline({ battleID }: { battleID: string }): Promise<void> {
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), `pvpBattles/${battleID}`), { turnDeadline: Timestamp.fromMillis(Date.now() - 1000) });
  });
}

describe("joinPvpMatch", () => {
  it("先に待っていた利用者と後から来た利用者を組み合わせ、2 人の手持ち・表示名・乱数の種・対戦日・期限を対戦に書く", async () => {
    const host = await signInTrainer({ levels: [5, 6] });
    const guest = await signInTrainer({ levels: [7] });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `users/${guest.uid}`), { displayName: "ゲスト", iconPath: `users/${guest.uid}/icons/icon.png` }, { merge: true });
    });
    const startedAtMillis = Date.now();

    const battle = (await readDocument({ path: `pvpBattles/${await matchTrainers({ host, guest })}` }))!;

    expect(battle).toMatchObject({
      participantUids: [host.uid, guest.uid],
      turns: [],
      turnSeconds: TURN_SECONDS,
      status: "active",
      winnerUid: null,
      finishReason: null,
      reportedWinnerUids: {},
    });
    expect(battle.host).toMatchObject({ uid: host.uid, displayName: defaultDisplayName(host.uid), iconPath: null });
    expect(battle.guest).toMatchObject({ uid: guest.uid, displayName: "ゲスト", iconPath: `users/${guest.uid}/icons/icon.png` });
    expect(battle.host.monsters.map((monster: DocumentData) => [monster.definition.id, monster.level])).toEqual([
      [`${host.uid}-monster-0`, 5],
      [`${host.uid}-monster-1`, 6],
    ]);
    expect(battle.guest.monsters.map((monster: DocumentData) => [monster.definition.id, monster.level])).toEqual([[`${guest.uid}-monster-0`, 7]]);
    expect(Number.isInteger(battle.randomSeed)).toBe(true);
    expect(battle.randomSeed).toBeGreaterThanOrEqual(1);
    expect(battle.randomSeed).toBeLessThan(2 ** 32);
    // 対戦日は日本時間の日付 (UTC+9)。テストの実行が日付をまたぐ場合に備え、前後どちらかの日付と一致すればよい
    expect([startedAtMillis, Date.now()].map((millis) => new Date(millis + 9 * 60 * 60 * 1000).toISOString().slice(0, 10))).toContain(battle.battleDate);
    const deadlineMillis = (battle.turnDeadline as Timestamp).toMillis();
    expect(deadlineMillis).toBeGreaterThanOrEqual(startedAtMillis + (TURN_SECONDS + TURN_DEADLINE_GRACE_SECONDS) * 1000);
    expect(deadlineMillis).toBeLessThanOrEqual(Date.now() + (TURN_SECONDS + TURN_DEADLINE_GRACE_SECONDS) * 1000);
  });

  it("元の写真の参照・被写体の説明・分類・生成の要求 ID を対戦に写さない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });

    const battleText = JSON.stringify(await readDocument({ path: `pvpBattles/${await matchTrainers({ host, guest })}` }));

    expect(battleText).toContain(`${host.uid}-monster-0`);
    for (const { uid } of [host, guest]) {
      const monsterID = `${uid}-monster-0`;
      for (const secret of [secretPhotoPath({ uid, monsterID }), `secret-subject-${monsterID}`, `secret-category-${monsterID}`, `secret-request-${monsterID}`]) {
        expect(battleText).not.toContain(secret);
      }
    }
    expect(battleText).not.toContain("sourcePhotoReference");
  });

  it("組み合わせた時に、2 人のバトルの開始の記録を人との対戦の印付きで作る", async () => {
    const host = await signInTrainer({ levels: [5, 6] });
    const guest = await signInTrainer({ levels: [7] });

    const battleID = await matchTrainers({ host, guest });

    expect(await readDocument({ path: `users/${host.uid}/battles/${battleID}` })).toMatchObject({
      status: "started",
      partyMonsterIDs: [`${host.uid}-monster-0`, `${host.uid}-monster-1`],
      opponentKind: "pvp",
    });
    expect(await readDocument({ path: `users/${guest.uid}/battles/${battleID}` })).toMatchObject({
      status: "started",
      partyMonsterIDs: [`${guest.uid}-monster-0`],
      opponentKind: "pvp",
    });
  });

  it("待っていた利用者が同じ searchID で呼び直すと、組み合わされた対戦の ID を受け取る", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });

    expect(await joinMatch({ user: host, searchID: `search-${host.uid}`, rulesVersion: "1" })).toBe(battleID);
    expect(await joinMatch({ user: guest, searchID: `search-${guest.uid}`, rulesVersion: "1" })).toBe(battleID);
  });

  it("新しい searchID で探し直すと、前の対戦を返さずに待ちに戻る", async () => {
    const host = await signInTrainer({ levels: [5] });
    await matchTrainers({ host, guest: await signInTrainer({ levels: [5] }) });

    expect(await joinMatch({ user: host, searchID: "next-search", rulesVersion: "1" })).toBeNull();
  });

  it("長く待っている利用者から組み合わせる", async () => {
    const first = await signInTrainer({ levels: [5] });
    const second = await signInTrainer({ levels: [5] });
    const third = await signInTrainer({ levels: [5] });
    // first と second を互いに組めなくして 2 人とも待たせる
    await callOk({ name: "blockUser", user: first, data: { blockedUid: second.uid } });
    expect(await joinMatch({ user: first, searchID: "search-first", rulesVersion: "1" })).toBeNull();
    expect(await joinMatch({ user: second, searchID: "search-second", rulesVersion: "1" })).toBeNull();

    expect(
      (await readDocument({ path: `pvpBattles/${await joinMatch({ user: third, searchID: "search-third", rulesVersion: "1" })}` }))!
        .participantUids,
    ).toEqual([first.uid, third.uid]);
  });

  it("対戦の計算の版が違う利用者とは組み合わせず、同じ版の利用者とは組み合わせる", async () => {
    const waiting = await signInTrainer({ levels: [5] });
    const otherVersion = await signInTrainer({ levels: [5] });
    const sameVersion = await signInTrainer({ levels: [5] });
    expect(await joinMatch({ user: waiting, searchID: "search-waiting", rulesVersion: "1" })).toBeNull();

    expect(await joinMatch({ user: otherVersion, searchID: "search-other", rulesVersion: "2" })).toBeNull();
    expect(
      (await readDocument({ path: `pvpBattles/${await joinMatch({ user: sameVersion, searchID: "search-same", rulesVersion: "1" })}` }))!
        .participantUids,
    ).toEqual([waiting.uid, sameVersion.uid]);
  });

  it("ブロックした相手とも、ブロックされた相手とも組み合わせない", async () => {
    const blocker = await signInTrainer({ levels: [5] });
    const blocked = await signInTrainer({ levels: [5] });
    await callOk({ name: "blockUser", user: blocker, data: { blockedUid: blocked.uid } });

    // ブロックした側が待ち、された側が後から来る
    expect(await joinMatch({ user: blocker, searchID: "search-1", rulesVersion: "1" })).toBeNull();
    expect(await joinMatch({ user: blocked, searchID: "search-2", rulesVersion: "1" })).toBeNull();
    // された側が待っている所に、ブロックした側が来る
    expect(await joinMatch({ user: blocker, searchID: "search-3", rulesVersion: "1" })).toBeNull();
  });

  it(`${REPORT_HIDE_THRESHOLD} 人から通報されたモンスターの持ち主とは、待つ側でも来る側でも組み合わせない`, async () => {
    const reported = await signInTrainer({ levels: [5] });
    const other = await signInTrainer({ levels: [5] });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `reportedMonsters/${reported.uid}-monster-0`), {
        monsterOwnerUid: reported.uid,
        reporterCount: REPORT_HIDE_THRESHOLD,
      });
    });

    expect(await joinMatch({ user: reported, searchID: "search-1", rulesVersion: "1" })).toBeNull();
    expect(await joinMatch({ user: other, searchID: "search-2", rulesVersion: "1" })).toBeNull();
    expect(await joinMatch({ user: reported, searchID: "search-3", rulesVersion: "1" })).toBeNull();
  });

  it(`通報が ${REPORT_HIDE_THRESHOLD - 1} 人までのモンスターの持ち主とは組み合わせる`, async () => {
    const reported = await signInTrainer({ levels: [5] });
    const other = await signInTrainer({ levels: [5] });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), `reportedMonsters/${reported.uid}-monster-0`), {
        monsterOwnerUid: reported.uid,
        reporterCount: REPORT_HIDE_THRESHOLD - 1,
      });
    });

    expect(await joinMatch({ user: reported, searchID: "search-1", rulesVersion: "1" })).toBeNull();
    expect(await joinMatch({ user: other, searchID: "search-2", rulesVersion: "1" })).not.toBeNull();
  });

  it("自分が通報したモンスターの持ち主とは組み合わせない", async () => {
    const reporter = await signInTrainer({ levels: [5] });
    const owner = await signInTrainer({ levels: [5] });
    await callOk({
      name: "reportMonster",
      user: reporter,
      data: { monsterOwnerUid: owner.uid, monsterID: `${owner.uid}-monster-0`, reason: "inappropriate_picture" },
    });

    expect(await joinMatch({ user: owner, searchID: "search-1", rulesVersion: "1" })).toBeNull();
    expect(await joinMatch({ user: reporter, searchID: "search-2", rulesVersion: "1" })).toBeNull();
  });

  it("アカウントの削除を始めた利用者は探せず、待っていた札とも組み合わせない", async () => {
    const deleting = await signInTrainer({ levels: [5] });
    const other = await signInTrainer({ levels: [5] });
    expect(await joinMatch({ user: deleting, searchID: "search-1", rulesVersion: "1" })).toBeNull();
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `users/${deleting.uid}`), { accountDeletionStartedAt: Timestamp.fromMillis(0) });
    });

    expect(await joinMatch({ user: other, searchID: "search-2", rulesVersion: "1" })).toBeNull();
    expect(await callErrorStatus({ name: "joinPvpMatch", user: deleting, data: { rulesVersion: "1", searchID: "search-3" } })).toBe("FAILED_PRECONDITION");
  });

  it(`最後に呼んでから ${MATCH_TICKET_FRESH_SECONDS} 秒より古い札 (アプリを閉じた利用者) とは組み合わせない`, async () => {
    const closed = await signInTrainer({ levels: [5] });
    const other = await signInTrainer({ levels: [5] });
    expect(await joinMatch({ user: closed, searchID: "search-1", rulesVersion: "1" })).toBeNull();
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `pvpMatchTickets/${closed.uid}`), {
        heartbeatAt: Timestamp.fromMillis(Date.now() - (MATCH_TICKET_FRESH_SECONDS + 1) * 1000),
      });
    });

    expect(await joinMatch({ user: other, searchID: "search-2", rulesVersion: "1" })).toBeNull();
  });

  it("手持ちが空の利用者は探せず、札も作らない", async () => {
    const empty = await signInTrainer({ levels: [] });

    expect(await callErrorStatus({ name: "joinPvpMatch", user: empty, data: { rulesVersion: "1", searchID: "search-1" } })).toBe("FAILED_PRECONDITION");
    expect(await readDocument({ path: `pvpMatchTickets/${empty.uid}` })).toBeUndefined();
  });

  it("待っている間に手持ちを空にした利用者とは組み合わせない", async () => {
    const emptied = await signInTrainer({ levels: [5] });
    const other = await signInTrainer({ levels: [5] });
    expect(await joinMatch({ user: emptied, searchID: "search-1", rulesVersion: "1" })).toBeNull();
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `users/${emptied.uid}/party/current`), { monsterIDs: [] });
    });

    expect(await joinMatch({ user: other, searchID: "search-2", rulesVersion: "1" })).toBeNull();
  });

  it("版と searchID の形が違う呼び出しは受け付けない", async () => {
    const user = await signInTrainer({ levels: [5] });

    expect(await callErrorStatus({ name: "joinPvpMatch", user, data: { rulesVersion: "", searchID: "search" } })).toBe("INVALID_ARGUMENT");
    expect(await callErrorStatus({ name: "joinPvpMatch", user, data: { rulesVersion: "1", searchID: "a/b" } })).toBe("INVALID_ARGUMENT");
    expect(await callErrorStatus({ name: "joinPvpMatch", user, data: { rulesVersion: "1" } })).toBe("INVALID_ARGUMENT");
  });
});

describe("leavePvpMatch", () => {
  it("探すのをやめた利用者の札を消し、後から来た利用者と組み合わせない", async () => {
    const left = await signInTrainer({ levels: [5] });
    const other = await signInTrainer({ levels: [5] });
    expect(await joinMatch({ user: left, searchID: "search-1", rulesVersion: "1" })).toBeNull();

    expect(await callOk({ name: "leavePvpMatch", user: left, data: { searchID: "search-1" } })).toEqual({ battleID: null });

    expect(await readDocument({ path: `pvpMatchTickets/${left.uid}` })).toBeUndefined();
    expect(await joinMatch({ user: other, searchID: "search-2", rulesVersion: "1" })).toBeNull();
  });

  it("やめる前に組み合わされていたら、その対戦の ID を返して札を残す", async () => {
    const host = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest: await signInTrainer({ levels: [5] }) });

    expect(await callOk({ name: "leavePvpMatch", user: host, data: { searchID: `search-${host.uid}` } })).toEqual({ battleID });
    expect((await readDocument({ path: `pvpMatchTickets/${host.uid}` }))!.battleID).toBe(battleID);
  });

  it("別の探す操作の searchID では札を消さない", async () => {
    const user = await signInTrainer({ levels: [5] });
    expect(await joinMatch({ user, searchID: "search-1", rulesVersion: "1" })).toBeNull();

    expect(await callOk({ name: "leavePvpMatch", user, data: { searchID: "another-search" } })).toEqual({ battleID: null });

    expect((await readDocument({ path: `pvpMatchTickets/${user.uid}` }))!.searchID).toBe("search-1");
  });
});

describe("submitPvpAction", () => {
  it("片方が出しただけでは公開せず、2 人がそろうと出した順に関係なく host・guest の行動として公開する", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });

    expect((await submitMove({ user: host, battleID, round: 0, moveID: "host-move-0" })).status).toBe(200);
    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.turns).toEqual([]);
    expect(await readDocument({ path: `pvpBattles/${battleID}/pendingActions/${host.uid}` })).toEqual({ action: { kind: "move", moveID: "host-move-0" } });

    expect((await submitMove({ user: guest, battleID, round: 0, moveID: "guest-move-0" })).status).toBe(200);
    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.turns).toEqual([
      { hostAction: { kind: "move", moveID: "host-move-0" }, guestAction: { kind: "move", moveID: "guest-move-0" } },
    ]);
    expect(await readDocument({ path: `pvpBattles/${battleID}/pendingActions/${host.uid}` })).toBeUndefined();

    // 次のターンは guest が先に出す
    expect(
      (await callFunction({ name: "submitPvpAction", user: guest, data: { battleID, round: 1, action: { kind: "switch", memberIndex: 1 } } })).status,
    ).toBe(200);
    expect((await callFunction({ name: "submitPvpAction", user: host, data: { battleID, round: 1, action: { kind: "struggle" } } })).status).toBe(200);
    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.turns).toEqual([
      { hostAction: { kind: "move", moveID: "host-move-0" }, guestAction: { kind: "move", moveID: "guest-move-0" } },
      { hostAction: { kind: "struggle" }, guestAction: { kind: "switch", memberIndex: 1 } },
    ]);
  });

  it("同じ行動のターンが続いても、ターンごとに足す", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });

    for (const round of [0, 1]) {
      await submitMove({ user: host, battleID, round, moveID: "same-move" });
      await submitMove({ user: guest, battleID, round, moveID: "same-move" });
    }

    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.turns).toHaveLength(2);
  });

  it("出した行動は、同じターンに出し直しても変わらない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });

    await submitMove({ user: host, battleID, round: 0, moveID: "first-choice" });
    expect((await submitMove({ user: host, battleID, round: 0, moveID: "second-choice" })).status).toBe(200);
    await submitMove({ user: guest, battleID, round: 0, moveID: "guest-move" });

    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.turns[0].hostAction).toEqual({ kind: "move", moveID: "first-choice" });
  });

  it("公開済みのターンの再送は何も変えず、まだ始まっていないターンの番号は受け付けない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await submitMove({ user: host, battleID, round: 0, moveID: "host-move" });
    await submitMove({ user: guest, battleID, round: 0, moveID: "guest-move" });

    expect((await submitMove({ user: host, battleID, round: 0, moveID: "resent" })).status).toBe(200);
    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.turns).toHaveLength(1);
    expect(await readDocument({ path: `pvpBattles/${battleID}/pendingActions/${host.uid}` })).toBeUndefined();
    expect(
      await callErrorStatus({ name: "submitPvpAction", user: host, data: { battleID, round: 2, action: { kind: "struggle" } } }),
    ).toBe("INVALID_ARGUMENT");
  });

  it("ターンを公開するたびに、次のターンの期限を延ばす", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `pvpBattles/${battleID}`), { turnDeadline: Timestamp.fromMillis(Date.now() + 5000) });
    });
    const revealedAtMillis = Date.now();

    await submitMove({ user: host, battleID, round: 0, moveID: "host-move" });
    await submitMove({ user: guest, battleID, round: 0, moveID: "guest-move" });

    expect(((await readDocument({ path: `pvpBattles/${battleID}` }))!.turnDeadline as Timestamp).toMillis()).toBeGreaterThanOrEqual(
      revealedAtMillis + (TURN_SECONDS + TURN_DEADLINE_GRACE_SECONDS) * 1000,
    );
  });

  it("期限を過ぎたターンには行動を出せない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest: await signInTrainer({ levels: [5] }) });
    await expireTurnDeadline({ battleID });

    expect(
      await callErrorStatus({ name: "submitPvpAction", user: host, data: { battleID, round: 0, action: { kind: "struggle" } } }),
    ).toBe("DEADLINE_EXCEEDED");
    expect(await readDocument({ path: `pvpBattles/${battleID}/pendingActions/${host.uid}` })).toBeUndefined();
  });

  it("対戦に出ていない利用者は、行動を出すことも時間切れ・勝者の報告もできない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const outsider = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });

    expect(
      await callErrorStatus({ name: "submitPvpAction", user: outsider, data: { battleID, round: 0, action: { kind: "struggle" } } }),
    ).toBe("PERMISSION_DENIED");
    expect(await callErrorStatus({ name: "claimPvpTimeout", user: outsider, data: { battleID } })).toBe("PERMISSION_DENIED");
    expect(await callErrorStatus({ name: "reportPvpResult", user: outsider, data: { battleID, winnerUid: host.uid } })).toBe("PERMISSION_DENIED");
    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.status).toBe("active");
  });

  it("形の違う行動と、無い対戦は受け付けない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest: await signInTrainer({ levels: [5] }) });

    expect(
      await callErrorStatus({ name: "submitPvpAction", user: host, data: { battleID, round: 0, action: { kind: "forfeit" } } }),
    ).toBe("INVALID_ARGUMENT");
    expect(
      await callErrorStatus({ name: "submitPvpAction", user: host, data: { battleID, round: -1, action: { kind: "struggle" } } }),
    ).toBe("INVALID_ARGUMENT");
    expect(
      await callErrorStatus({ name: "submitPvpAction", user: host, data: { battleID: "no-such-battle", round: 0, action: { kind: "struggle" } } }),
    ).toBe("NOT_FOUND");
  });
});

describe("claimPvpTimeout", () => {
  it("片方が操作をやめた対戦は、期限の後に、行動を出した側の勝ちで終わり、2 人の記録に勝敗が残る", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await submitMove({ user: guest, battleID, round: 0, moveID: "guest-move" });
    await expireTurnDeadline({ battleID });

    expect(await callOk({ name: "claimPvpTimeout", user: guest, data: { battleID } })).toEqual({ status: "finished" });

    expect(await readDocument({ path: `pvpBattles/${battleID}` })).toMatchObject({
      status: "finished",
      winnerUid: guest.uid,
      finishReason: "timeout",
      turnDeadline: null,
    });
    expect(await readDocument({ path: `pvpBattles/${battleID}/pendingActions/${guest.uid}` })).toBeUndefined();
    expect((await readDocument({ path: `users/${guest.uid}/battles/${battleID}` }))!.winner).toBe("player");
    // 操作をやめた側は記録を完了しないまま、負けだけが残る
    expect(await readDocument({ path: `users/${host.uid}/battles/${battleID}` })).toMatchObject({ status: "started", winner: "opponent" });
  });

  it("期限の前に呼んでも終わらせない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await submitMove({ user: guest, battleID, round: 0, moveID: "guest-move" });

    expect(await callOk({ name: "claimPvpTimeout", user: guest, data: { battleID } })).toEqual({ status: "active" });

    expect(await readDocument({ path: `pvpBattles/${battleID}` })).toMatchObject({ status: "active", winnerUid: null });
    expect(await readDocument({ path: `pvpBattles/${battleID}/pendingActions/${guest.uid}` })).toEqual({ action: { kind: "move", moveID: "guest-move" } });
  });

  it("どちらも行動を出していない対戦は、期限の後に勝敗を付けずに終わる", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await expireTurnDeadline({ battleID });

    expect(await callOk({ name: "claimPvpTimeout", user: host, data: { battleID } })).toEqual({ status: "void" });

    expect(await readDocument({ path: `pvpBattles/${battleID}` })).toMatchObject({ status: "void", winnerUid: null, finishReason: "timeout" });
    expect((await readDocument({ path: `users/${host.uid}/battles/${battleID}` }))!.winner).toBeUndefined();
    expect((await readDocument({ path: `users/${guest.uid}/battles/${battleID}` }))!.winner).toBeUndefined();
  });

  it("終わった対戦には行動を出せず、もう一度呼んでも結果は変わらない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await submitMove({ user: host, battleID, round: 0, moveID: "host-move" });
    await expireTurnDeadline({ battleID });
    await callOk({ name: "claimPvpTimeout", user: host, data: { battleID } });

    expect(await callOk({ name: "claimPvpTimeout", user: guest, data: { battleID } })).toEqual({ status: "finished" });
    expect(
      await callErrorStatus({ name: "submitPvpAction", user: guest, data: { battleID, round: 0, action: { kind: "struggle" } } }),
    ).toBe("FAILED_PRECONDITION");
    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.winnerUid).toBe(host.uid);
  });
});

describe("reportPvpResult と recordBattle", () => {
  it("2 人が同じ勝者を報告すると、両方の記録に勝敗が残り、両方の場に出たモンスターのレベルが上がる", async () => {
    const host = await signInTrainer({ levels: [5, 9] });
    const guest = await signInTrainer({ levels: [7] });
    const battleID = await matchTrainers({ host, guest });
    await submitMove({ user: host, battleID, round: 0, moveID: "host-move" });
    await submitMove({ user: guest, battleID, round: 0, moveID: "guest-move" });

    expect(await callOk({ name: "reportPvpResult", user: host, data: { battleID, winnerUid: host.uid } })).toEqual({ status: "finished" });
    expect(await callOk({ name: "reportPvpResult", user: guest, data: { battleID, winnerUid: host.uid } })).toEqual({ status: "finished" });
    expect(
      await callOk({
        name: "recordBattle",
        user: host,
        data: { battleID, participantMonsterIDs: [`${host.uid}-monster-0`], winner: "player", turnCount: 3 },
      }),
    ).toEqual({ levels: { [`${host.uid}-monster-0`]: 6 } });
    // 負けた側の端末が勝ちと送っても、サーバーが決めた勝敗を上書きしない
    expect(
      await callOk({
        name: "recordBattle",
        user: guest,
        data: { battleID, participantMonsterIDs: [`${guest.uid}-monster-0`], winner: "player", turnCount: 3 },
      }),
    ).toEqual({ levels: { [`${guest.uid}-monster-0`]: 8 } });

    expect(await readDocument({ path: `pvpBattles/${battleID}` })).toMatchObject({
      status: "finished",
      winnerUid: host.uid,
      finishReason: "result",
      reportedWinnerUids: { [host.uid]: host.uid, [guest.uid]: host.uid },
    });
    expect(await readDocument({ path: `users/${host.uid}/battles/${battleID}` })).toMatchObject({ status: "completed", winner: "player", turnCount: 3 });
    expect(await readDocument({ path: `users/${guest.uid}/battles/${battleID}` })).toMatchObject({ status: "completed", winner: "opponent", turnCount: 3 });
    expect((await readDocument({ path: `users/${host.uid}/monsters/${host.uid}-monster-0` }))!.level).toBe(6);
    // 場に出なかった手持ちは上がらない
    expect((await readDocument({ path: `users/${host.uid}/monsters/${host.uid}-monster-1` }))!.level).toBe(9);
    expect((await readDocument({ path: `users/${guest.uid}/monsters/${guest.uid}-monster-0` }))!.level).toBe(8);
    expect((await readDocument({ path: `users/${host.uid}` }))!.dailyBattleCount).toBe(1);
    expect((await readDocument({ path: `users/${guest.uid}` }))!.dailyBattleCount).toBe(1);
  });

  it("相手が報告しなくても、最初の報告で両方の記録に勝敗が残る (負けた側がアプリを閉じた時)", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });

    await callOk({ name: "reportPvpResult", user: guest, data: { battleID, winnerUid: guest.uid } });

    expect((await readDocument({ path: `users/${guest.uid}/battles/${battleID}` }))!.winner).toBe("player");
    expect(await readDocument({ path: `users/${host.uid}/battles/${battleID}` })).toMatchObject({ status: "started", winner: "opponent" });
  });

  it("2 人の報告した勝者が食い違うと、勝敗を付けずに終わり、書いた勝敗を消す", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await callOk({ name: "reportPvpResult", user: host, data: { battleID, winnerUid: host.uid } });

    expect(await callOk({ name: "reportPvpResult", user: guest, data: { battleID, winnerUid: guest.uid } })).toEqual({ status: "void" });

    expect(await readDocument({ path: `pvpBattles/${battleID}` })).toMatchObject({ status: "void", winnerUid: null, finishReason: "mismatch" });
    expect((await readDocument({ path: `users/${host.uid}/battles/${battleID}` }))!.winner).toBeUndefined();
    expect((await readDocument({ path: `users/${guest.uid}/battles/${battleID}` }))!.winner).toBeUndefined();
  });

  it("決着していないターンで勝ちを報告された相手が「決着していない」と報告すると、勝敗を付けずに終わる", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await callOk({ name: "reportPvpResult", user: host, data: { battleID, winnerUid: host.uid } });

    expect(await callOk({ name: "reportPvpResult", user: guest, data: { battleID, winnerUid: null } })).toEqual({ status: "void" });

    expect((await readDocument({ path: `users/${guest.uid}/battles/${battleID}` }))!.winner).toBeUndefined();
  });

  it("報告は 1 人 1 回で、出し直しても勝者は変わらない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await callOk({ name: "reportPvpResult", user: host, data: { battleID, winnerUid: host.uid } });

    expect(await callOk({ name: "reportPvpResult", user: host, data: { battleID, winnerUid: guest.uid } })).toEqual({ status: "finished" });

    expect(await readDocument({ path: `pvpBattles/${battleID}` })).toMatchObject({ status: "finished", winnerUid: host.uid });
  });

  it("進行中の対戦への「決着していない」は何も変えず、後から本当の勝者を報告できる", async () => {
    const host = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest: await signInTrainer({ levels: [5] }) });

    expect(await callOk({ name: "reportPvpResult", user: host, data: { battleID, winnerUid: null } })).toEqual({ status: "active" });
    expect(await callOk({ name: "reportPvpResult", user: host, data: { battleID, winnerUid: host.uid } })).toEqual({ status: "finished" });
  });

  it("期限切れで終わった対戦の勝者は、負けた側の食い違う報告で変わらない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await submitMove({ user: host, battleID, round: 0, moveID: "host-move" });
    await expireTurnDeadline({ battleID });
    await callOk({ name: "claimPvpTimeout", user: host, data: { battleID } });

    expect(await callOk({ name: "reportPvpResult", user: guest, data: { battleID, winnerUid: guest.uid } })).toEqual({ status: "finished" });

    expect(await readDocument({ path: `pvpBattles/${battleID}` })).toMatchObject({ status: "finished", winnerUid: host.uid, finishReason: "timeout" });
    expect((await readDocument({ path: `users/${host.uid}/battles/${battleID}` }))!.winner).toBe("player");
  });

  it("対戦に出ていない uid は勝者として報告できない", async () => {
    const host = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest: await signInTrainer({ levels: [5] }) });

    expect(await callErrorStatus({ name: "reportPvpResult", user: host, data: { battleID, winnerUid: "someone-else" } })).toBe("INVALID_ARGUMENT");
    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.status).toBe("active");
  });

  it(`人との対戦にも 1 日 ${DAILY_BATTLE_LIMIT} 戦の上限が効き、上限の後はレベルが上がらない`, async () => {
    const host = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest: await signInTrainer({ levels: [5] }) });
    await callOk({ name: "reportPvpResult", user: host, data: { battleID, winnerUid: host.uid } });
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await updateDoc(doc(context.firestore(), `users/${host.uid}`), {
        dailyBattleDate: new Date(Date.now() + 9 * 60 * 60 * 1000).toISOString().slice(0, 10),
        dailyBattleCount: DAILY_BATTLE_LIMIT,
      });
    });

    expect(
      await callErrorStatus({
        name: "recordBattle",
        user: host,
        data: { battleID, participantMonsterIDs: [`${host.uid}-monster-0`], winner: "player", turnCount: 3 },
      }),
    ).toBe("RESOURCE_EXHAUSTED");
    expect((await readDocument({ path: `users/${host.uid}/monsters/${host.uid}-monster-0` }))!.level).toBe(5);
  });
});

describe("blockUser と進行中の人との対戦", () => {
  it("対戦の相手をブロックすると、進行中の対戦が勝敗を付けずに終わり、出したままの行動も消える", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await submitMove({ user: guest, battleID, round: 0, moveID: "guest-move" });

    await callOk({ name: "blockUser", user: host, data: { blockedUid: guest.uid } });

    expect(await readDocument({ path: `pvpBattles/${battleID}` })).toMatchObject({ status: "void", winnerUid: null, finishReason: "blocked", turnDeadline: null });
    expect(await readDocument({ path: `pvpBattles/${battleID}/pendingActions/${guest.uid}` })).toBeUndefined();
    expect((await readDocument({ path: `users/${host.uid}/battles/${battleID}` }))!.winner).toBeUndefined();
  });

  it("対戦の相手ではない利用者をブロックしても、進行中の対戦は続く", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const outsider = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });

    await callOk({ name: "blockUser", user: host, data: { blockedUid: outsider.uid } });

    expect((await readDocument({ path: `pvpBattles/${battleID}` }))!.status).toBe("active");
  });

  it("勝者が決まって終わった対戦は、その後に相手をブロックしても勝敗が残る", async () => {
    const host = await signInTrainer({ levels: [5] });
    const guest = await signInTrainer({ levels: [5] });
    const battleID = await matchTrainers({ host, guest });
    await callOk({ name: "reportPvpResult", user: guest, data: { battleID, winnerUid: guest.uid } });

    await callOk({ name: "blockUser", user: host, data: { blockedUid: guest.uid } });

    expect(await readDocument({ path: `pvpBattles/${battleID}` })).toMatchObject({ status: "finished", winnerUid: guest.uid });
    expect((await readDocument({ path: `users/${guest.uid}/battles/${battleID}` }))!.winner).toBe("player");
  });
});
