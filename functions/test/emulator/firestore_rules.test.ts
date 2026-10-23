import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, serverTimestamp, setDoc, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// Rules は Emulator が firebase.json の firebase/firestore.rules から読み込む (テストから別の Rules を渡さない)。

let testEnvironment: RulesTestEnvironment;

beforeAll(async () => {
  testEnvironment = await initializeTestEnvironment({ projectId: "demo-snapmon" });
});

afterAll(async () => {
  await testEnvironment.cleanup();
});

beforeEach(async () => {
  await testEnvironment.clearFirestore();
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const firestore = context.firestore();
    await setDoc(doc(firestore, "users/alice"), { createdAt: 0 });
    await setDoc(doc(firestore, "users/alice/monsters/m1"), { name: "a" });
    await setDoc(doc(firestore, "users/alice/monsters/m2"), { name: "b" });
    await setDoc(doc(firestore, "users/alice/monsters/m3"), { name: "c" });
    await setDoc(doc(firestore, "users/alice/monsters/m4"), { name: "d" });
    await setDoc(doc(firestore, "users/bob/monsters/b1"), { name: "e" });
    await setDoc(doc(firestore, "users/bob"), { createdAt: 0 });
    await setDoc(doc(firestore, "master/1"), { version: 1 });
    await setDoc(doc(firestore, "definitions/d1"), { name: "x" });
  });
});

/** 匿名ログインしたユーザー (カスタムクレーム無し) の Firestore。 */
function signedInFirestore(uid: string) {
  return testEnvironment.authenticatedContext(uid).firestore();
}

describe("users/{uid}", () => {
  it("本人は自分の users と monsters を読める", async () => {
    const firestore = signedInFirestore("alice");
    await assertSucceeds(getDoc(doc(firestore, "users/alice")));
    await assertSucceeds(getDoc(doc(firestore, "users/alice/monsters/m1")));
  });

  it("他人の users/{uid} とその配下は読めない", async () => {
    const firestore = signedInFirestore("alice");
    await assertFails(getDoc(doc(firestore, "users/bob")));
    await assertFails(getDoc(doc(firestore, "users/bob/monsters/b1")));
    await assertFails(getDoc(doc(firestore, "users/bob/party/current")));
    await assertFails(getDoc(doc(firestore, "users/bob/settings/current")));
  });

  it("未ログインは読めない", async () => {
    const firestore = testEnvironment.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(firestore, "users/alice")));
  });

  it("まだ生成していない (users/{uid} の無い) 新しいユーザーも、ログインだけで自分の図鑑と master・definitions を読める", async () => {
    const firestore = signedInFirestore("dave");
    await assertSucceeds(getDoc(doc(firestore, "users/dave")));
    await assertSucceeds(getDoc(doc(firestore, "users/dave/monsters/none")));
    await assertSucceeds(getDoc(doc(firestore, "master/1")));
    await assertSucceeds(getDoc(doc(firestore, "definitions/d1")));
  });

  it("monsters・generations・battles と users 自体はクライアントから書けない", async () => {
    const firestore = signedInFirestore("alice");
    await assertFails(setDoc(doc(firestore, "users/alice"), { createdAt: 1 }));
    await assertFails(setDoc(doc(firestore, "users/alice/monsters/new"), { name: "z" }));
    await assertFails(setDoc(doc(firestore, "users/alice/generations/subject"), { state: "saved" }));
    await assertFails(setDoc(doc(firestore, "users/alice/battles/battle"), { completed: true }));
  });

  it("本人も表示名を直接書けない (Functions の setDisplayName の禁止語の検査を通らない名前を他人に見せないため)", async () => {
    const firestore = signedInFirestore("alice");
    await assertFails(setDoc(doc(firestore, "users/alice"), { displayName: "なまえ" }, { merge: true }));
    await assertFails(updateDoc(doc(firestore, "users/alice"), { displayName: "なまえ" }));
  });
});

describe("users/{uid}/party/current", () => {
  it("自分の monsters にある ID を 3 件まで書ける", async () => {
    const firestore = signedInFirestore("alice");
    await assertSucceeds(
      setDoc(doc(firestore, "users/alice/party/current"), {
        monsterIds: ["m1", "m2", "m3"],
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("4 件以上は書けない", async () => {
    const firestore = signedInFirestore("alice");
    await assertFails(
      setDoc(doc(firestore, "users/alice/party/current"), {
        monsterIds: ["m1", "m2", "m3", "m4"],
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("自分の monsters に無い ID・重複は書けない", async () => {
    const firestore = signedInFirestore("alice");
    await assertFails(
      setDoc(doc(firestore, "users/alice/party/current"), { monsterIds: ["b1"], updatedAt: serverTimestamp() }),
    );
    await assertFails(
      setDoc(doc(firestore, "users/alice/party/current"), { monsterIds: ["m1", "m1"], updatedAt: serverTimestamp() }),
    );
  });

  it("他人の手持ちは書けない", async () => {
    const firestore = signedInFirestore("alice");
    await assertFails(
      setDoc(doc(firestore, "users/bob/party/current"), { monsterIds: [], updatedAt: serverTimestamp() }),
    );
  });

  it("決めたフィールド以外は書けない", async () => {
    const firestore = signedInFirestore("alice");
    await assertFails(
      setDoc(doc(firestore, "users/alice/party/current"), {
        monsterIds: ["m1"],
        updatedAt: serverTimestamp(),
        level: 999,
      }),
    );
  });
});

describe("users/{uid}/settings/current", () => {
  it("本人は書ける", async () => {
    const firestore = signedInFirestore("alice");
    await assertSucceeds(setDoc(doc(firestore, "users/alice/settings/current"), { soundEnabled: true }));
  });
});

describe("アカウントの削除の途中と削除の後", () => {
  it("削除の印のある本人は、手持ちと設定を書けない", async () => {
    await testEnvironment.withSecurityRulesDisabled(async (context) => {
      await setDoc(doc(context.firestore(), "users/alice"), { createdAt: 0, accountDeletionStartedAt: 0 });
    });
    const firestore = signedInFirestore("alice");
    await assertFails(setDoc(doc(firestore, "users/alice/party/current"), { monsterIds: [], updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(firestore, "users/alice/settings/current"), { soundEnabled: true }));
  });

  it("users/{uid} が消えた本人 (ID トークンが期限まで残る別の端末) は、手持ちと設定を書けない", async () => {
    const firestore = signedInFirestore("carol");
    await assertFails(setDoc(doc(firestore, "users/carol/party/current"), { monsterIds: [], updatedAt: serverTimestamp() }));
    await assertFails(setDoc(doc(firestore, "users/carol/settings/current"), { soundEnabled: true }));
  });
});

describe("master と definitions", () => {
  it("ログインしたユーザーは読めるが書けない", async () => {
    const firestore = signedInFirestore("alice");
    await assertSucceeds(getDoc(doc(firestore, "master/1")));
    await assertSucceeds(getDoc(doc(firestore, "definitions/d1")));
    await assertFails(setDoc(doc(firestore, "master/2"), { version: 2 }));
    await assertFails(setDoc(doc(firestore, "definitions/d2"), { name: "y" }));
  });

  it("未ログインは読めない", async () => {
    const firestore = testEnvironment.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(firestore, "master/1")));
    await assertFails(getDoc(doc(firestore, "definitions/d1")));
  });
});

describe("reports と blocks と reportedMonsters", () => {
  it("クライアントから読み書きできない", async () => {
    const firestore = signedInFirestore("alice");
    await assertFails(setDoc(doc(firestore, "reports/r1"), { monsterId: "b1" }));
    await assertFails(setDoc(doc(firestore, "blocks/k1"), { blockedUid: "bob" }));
    await assertFails(getDoc(doc(firestore, "reports/r1")));
    await assertFails(getDoc(doc(firestore, "blocks/k1")));
    await assertFails(getDoc(doc(firestore, "reportedMonsters/b1")));
    await assertFails(setDoc(doc(firestore, "reportedMonsters/b1"), { reporterCount: 0 }));
  });
});

describe("生成のカウンタと使い回しの記録", () => {
  it("本人も含めてクライアントから読み書きできない", async () => {
    const firestore = signedInFirestore("alice");
    await assertFails(getDoc(doc(firestore, "users/alice/generationAliases/request1")));
    await assertFails(setDoc(doc(firestore, "users/alice/generationAliases/request1"), { reusedRequestId: "request0" }));
    await assertFails(getDoc(doc(firestore, "generationDailyCounts/2026-10-22")));
    await assertFails(setDoc(doc(firestore, "generationDailyCounts/2026-10-22"), { count: 0 }));
    await assertFails(getDoc(doc(firestore, "definitionCounters/global")));
    await assertFails(setDoc(doc(firestore, "definitionCounters/global"), { elementCount: 0 }));
  });
});
