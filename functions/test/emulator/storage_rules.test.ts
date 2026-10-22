import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { deleteObject, getBytes, listAll, ref, type StorageReference, uploadBytes } from "firebase/storage";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// Rules は Emulator が firebase.json の firebase/storage.rules から読み込む (テストから別の Rules を渡さない)。

const bucketUrl = "gs://snapmon-prod-storage";
const smallImage = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);

let testEnvironment: RulesTestEnvironment;

beforeAll(async () => {
  testEnvironment = await initializeTestEnvironment({ projectId: "demo-snapmon" });
});

afterAll(async () => {
  await testEnvironment.cleanup();
});

beforeEach(async () => {
  // clearStorage は既定のバケット gs://demo-snapmon を消すが、Rules を対応させているのは snapmon-prod-storage だけのため、
  // テストで使うバケットの中身を自分で消す。
  await testEnvironment.withSecurityRulesDisabled(async (context) => {
    const storage = context.storage(bucketUrl);
    await Promise.all((await listAllRecursively(ref(storage))).map((item) => deleteObject(item)));
    await uploadBytes(ref(storage, "users/bob/photos/request1"), smallImage, { contentType: "image/jpeg" });
    await uploadBytes(ref(storage, "monsters/monster1/art.png"), smallImage, { contentType: "image/png" });
    await uploadBytes(ref(storage, "users/alice/generations/request1/cutout.png"), smallImage, { contentType: "image/png" });
  });
});

/** [folder] の配下のファイルを、下の階層まですべて返す。 */
async function listAllRecursively(folder: StorageReference): Promise<StorageReference[]> {
  const { items, prefixes } = await listAll(folder);
  const nestedItems = await Promise.all(prefixes.map((prefix) => listAllRecursively(prefix)));
  return [...items, ...nestedItems.flat()];
}

/** 年齢の確認を通ったユーザー (カスタムクレーム ageVerified 付き) の Storage。 */
function ageVerifiedStorage(uid: string) {
  return testEnvironment.authenticatedContext(uid, { ageVerified: true }).storage(bucketUrl);
}

describe("users/{uid}/photos", () => {
  it("本人は 4 MB 以下の JPEG・PNG を置ける", async () => {
    const storage = ageVerifiedStorage("alice");
    await assertSucceeds(
      uploadBytes(ref(storage, "users/alice/photos/request1"), smallImage, { contentType: "image/jpeg" }),
    );
    await assertSucceeds(
      uploadBytes(ref(storage, "users/alice/photos/request2"), smallImage, { contentType: "image/png" }),
    );
  });

  it("4 MB を超える写真と JPEG・PNG 以外は置けない", async () => {
    const storage = ageVerifiedStorage("alice");
    await assertFails(
      uploadBytes(ref(storage, "users/alice/photos/large"), new Uint8Array(4 * 1024 * 1024 + 1), {
        contentType: "image/jpeg",
      }),
    );
    await assertFails(
      uploadBytes(ref(storage, "users/alice/photos/gif"), smallImage, { contentType: "image/gif" }),
    );
  });

  it("他人の写真は読めず、他人の場所には置けない", async () => {
    const storage = ageVerifiedStorage("alice");
    await assertFails(getBytes(ref(storage, "users/bob/photos/request1")));
    await assertFails(
      uploadBytes(ref(storage, "users/bob/photos/request2"), smallImage, { contentType: "image/jpeg" }),
    );
  });

  it("年齢の確認を通っていない本人は置けない", async () => {
    const storage = testEnvironment.authenticatedContext("alice").storage(bucketUrl);
    await assertFails(
      uploadBytes(ref(storage, "users/alice/photos/request1"), smallImage, { contentType: "image/jpeg" }),
    );
  });
});

describe("users/{uid}/masks", () => {
  it("本人は 1 MB 以下の PNG のマスクを置け、他人の場所と PNG 以外には置けない", async () => {
    const storage = ageVerifiedStorage("alice");
    await assertSucceeds(uploadBytes(ref(storage, "users/alice/masks/request1"), smallImage, { contentType: "image/png" }));
    await assertFails(uploadBytes(ref(storage, "users/alice/masks/request2"), smallImage, { contentType: "image/jpeg" }));
    await assertFails(
      uploadBytes(ref(storage, "users/alice/masks/request3"), new Uint8Array(1024 * 1024 + 1), { contentType: "image/png" }),
    );
    await assertFails(uploadBytes(ref(storage, "users/bob/masks/request1"), smallImage, { contentType: "image/png" }));
  });
});

describe("users/{uid}/generations/{requestId}/cutout.png", () => {
  it("本人だけが読め、本人も書けない", async () => {
    await assertSucceeds(getBytes(ref(ageVerifiedStorage("alice"), "users/alice/generations/request1/cutout.png")));
    await assertFails(getBytes(ref(ageVerifiedStorage("bob"), "users/alice/generations/request1/cutout.png")));
    await assertFails(
      uploadBytes(ref(ageVerifiedStorage("alice"), "users/alice/generations/request2/cutout.png"), smallImage, { contentType: "image/png" }),
    );
  });
});

describe("monsters/{monsterId}/art.png", () => {
  it("年齢の確認を通ったユーザーは他人のモンスターの絵も読めるが、書けない", async () => {
    const storage = ageVerifiedStorage("alice");
    await assertSucceeds(getBytes(ref(storage, "monsters/monster1/art.png")));
    await assertFails(
      uploadBytes(ref(storage, "monsters/monster2/art.png"), smallImage, { contentType: "image/png" }),
    );
  });

  it("未ログインは読めない", async () => {
    const storage = testEnvironment.unauthenticatedContext().storage(bucketUrl);
    await assertFails(getBytes(ref(storage, "monsters/monster1/art.png")));
  });
});
