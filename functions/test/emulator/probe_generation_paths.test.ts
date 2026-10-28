import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import path from "node:path";

import { deleteApp, getApps, initializeApp } from "firebase-admin/app";
import type { Auth } from "firebase-admin/auth";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { afterAll, beforeEach, describe, expect, it } from "vitest";

import { listProbePhotos, probeGenerationPaths, readExpectations } from "../../scripts/probe-generation-paths.mjs";
import { handleGenerateRequest } from "../../src/generation/generate";
import type { JevQuestion, JevResponse } from "../../src/generation/jev";
import type { Master } from "../../src/generation/master";
import type { GenerationDependencies } from "../../src/generation/pipeline";
import type { DescribeSubjectOutput } from "../../src/generation/prompts/describe_subject";
import { canonicalDescriptionText, type GenerationRecord, type MonsterDocument } from "../../src/generation/records";
import type { VisionAnnotation } from "../../src/generation/vision";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// scripts/probe-generation-paths.mjs の probeGenerationPaths に、generate の本体 (handleGenerateRequest) を Firestore・Storage の Emulator に対して
// 呼ぶ generatePhoto を渡し、テスト写真のすべての経路が expectations.json のとおりになることを確かめる。
// 外部の API (Vision・Claude・Jev) は写真ごとに答えを決めたモックにする。同じ被写体かは、較正のラベル (fixtures/calibration/labels.json) で答える。

const projectId = "demo-snapmon";
const app = getApps().find((existing) => existing.name === "probe-generation-paths-test") ?? initializeApp({ projectId }, "probe-generation-paths-test");
const firestore = getFirestore(app);
const bucket = getStorage(app).bucket("snapmon-prod-storage");
const fixturesDirectory = path.join(__dirname, "..", "fixtures");
const master = JSON.parse(readFileSync(path.join(__dirname, "..", "..", "..", "assets", "master", "master.json"), "utf8")) as Master;
const calibrationDescriptions = JSON.parse(readFileSync(path.join(fixturesDirectory, "calibration", "descriptions.json"), "utf8")) as Record<string, DescribeSubjectOutput>;
const calibrationLabels = JSON.parse(readFileSync(path.join(fixturesDirectory, "calibration", "labels.json"), "utf8")) as { dedupe: { same: [string, string][] } };

/** テスト写真から、同じ写真の較正の見本の ID (LICENSES.md の「較正の NN.jpg」)。 */
const calibrationIdByPhotoName: Record<string, string> = {
  "ordinary/mug.jpg": "01",
  "ordinary/scissors.jpg": "15",
  "ordinary/cactus.jpg": "04",
  "ordinary/rubber_duck.jpg": "08",
  "ordinary/camera.jpg": "12",
  "same_subject/mug_another_shot.jpg": "01b",
  "same_subject/scissors_another_shot.jpg": "15b",
  "same_kind/another_mug.jpg": "02",
  "same_kind/another_rubber_duck.jpg": "09",
};

/** Vision が顔を検出する写真 (顔が写る人物の写真)。 */
const faceDetectedPhotoNames = new Set(["person/face_portrait.jpg", "person/portrait.jpg"]);

/** Claude が人が写っていると答える写真 (顔が写らず体と手が写る写真)。 */
const containsPersonPhotoNames = new Set(["person/holding_tulips.jpg"]);

/** 被写体が無い写真に Claude が返す説明 (較正の見本に無いため、マグカップの説明の何かと手がかりだけを替えた)。 */
function backgroundDescription(photoName: string): DescribeSubjectOutput {
  const base = calibrationDescriptions["01"];
  return { ...base, description: { ...base.description, what: `背景だけの写真 (${photoName})`, distinctiveMarks: [photoName] } };
}

/** 説明 (正規化した JSON 文字列) から、その説明を返した写真の較正の見本の ID。較正の見本に無い説明は undefined。 */
const calibrationIdByDescriptionText = new Map(Object.entries(calibrationDescriptions).map(([calibrationId, output]) => [canonicalDescriptionText(output.description), calibrationId]));

/** 較正のラベルで同じ個体とした組か。 */
function isSameSubject(leftId: string | undefined, rightId: string | undefined): boolean {
  return calibrationLabels.dedupe.same.some(([first, second]) => (first === leftId && second === rightId) || (first === rightId && second === leftId));
}

/** Auth のユーザーが残っている uid。 */
const authUserUids = new Set(["prober"]);

/** generate がアカウントの削除の確認に使う Auth のモック。`authUserUids` にある uid だけがいる。 */
const auth = {
  getUser: async (uid: string) => {
    if (!authUserUids.has(uid)) {
      throw Object.assign(new Error("ユーザーが見つかりません"), { code: "auth/user-not-found" });
    }
    return { uid };
  },
} as unknown as Auth;

/**
 * 写真ごとに答えを決めたモックの依存。`currentPhotoName` は生成中の写真で、generatePhoto が呼ぶ前に入れる。
 * `jevSaysDifferentForAll` は、Jev が同じ被写体の判定にいつも「別の物」と答える (同じ被写体の経路を壊した時に FAIL になるかを見るため)。
 */
function createDependencies({ jevSaysDifferentForAll = false }: { jevSaysDifferentForAll?: boolean } = {}): {
  state: { currentPhotoName: string };
  dependencies: GenerationDependencies;
} {
  const state = { currentPhotoName: "" };
  return {
    state,
    dependencies: {
      firestore,
      auth,
      bucket,
      annotateImage: async (): Promise<VisionAnnotation> => ({
        safeSearchAnnotation: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY" },
        faceAnnotations: faceDetectedPhotoNames.has(state.currentPhotoName) ? [{ detectionConfidence: 0.95 }] : [],
        labelAnnotations: [{ description: "Object", score: 0.9 }],
      }),
      describeSubject: async () => {
        const calibrationId = calibrationIdByPhotoName[state.currentPhotoName];
        const output = calibrationId ? calibrationDescriptions[calibrationId] : backgroundDescription(state.currentPhotoName);
        return { output: { ...output, containsPerson: containsPersonPhotoNames.has(state.currentPhotoName) }, usage: { inputTokens: 1500, outputTokens: 700 } };
      },
      proposeElement: async () => {
        throw new Error("属性はモックの Jev が metal と答えるため、新しい属性の提案は呼ばれない");
      },
      // 物の分類は tableware、ステータスはふつう、属性は metal と答え、同じ被写体かは較正のラベルで答える
      askJev: async (request) => {
        const subjectId = calibrationIdByDescriptionText.get(canonicalDescriptionText((request.state as { subject: DescribeSubjectOutput["description"] }).subject));
        const answers: JevResponse["answers"] = {};
        for (const [name, question] of Object.entries(request.questions) as [string, JevQuestion][]) {
          if (question.type === "choice") {
            const choices = Object.keys(question.criteria);
            answers[name] = { type: "choice", choice: choices[0], confidence: 0.9, probabilities: Object.fromEntries(choices.map((choice) => [choice, choice === "tableware" ? 0.8 : 0.01])) };
          } else if (question.type === "score") {
            answers[name] = { type: "score", score: 2, confidence: 0.8, probabilities: Object.fromEntries(question.criteria.map((level) => [level, level === "ふつう" ? 0.8 : 0.05])) };
          } else if (name.startsWith("same__") || name.startsWith("different__")) {
            const same =
              !jevSaysDifferentForAll &&
              isSameSubject(subjectId, calibrationIdByDescriptionText.get(canonicalDescriptionText((question.instructions as { candidate: DescribeSubjectOutput["description"] }).candidate)));
            answers[name] = { type: "noul", noul: name.startsWith("same__") === same ? 0.95 : 0.05 };
          } else if (name.startsWith("element__")) {
            answers[name] = { type: "noul", noul: name === "element__metal" ? 0.9 : 0.05 };
          } else {
            answers[name] = { type: "noul", noul: 0.05 };
          }
        }
        return { model: "jev-1.13.0", answers, usage: { input_tokens: 1000, output_tokens: 10 } };
      },
      enqueueResume: async () => {},
      now: () => new Date(),
    },
  };
}

/** probeGenerationPaths に渡す、uid `prober` で 1 枚を生成して結果を読む関数。 */
function createGeneratePhoto({ state, dependencies }: ReturnType<typeof createDependencies>) {
  return async ({ photoName, photo }: { photoName: string; photo: Buffer }) => {
    state.currentPhotoName = photoName;
    const requestId = randomUUID();
    const photoPath = `users/prober/photos/${requestId}`;
    await bucket.file(photoPath).save(photo, { contentType: "image/jpeg", resumable: false });
    await handleGenerateRequest(dependencies, { auth: { uid: "prober", token: {} } as never, data: { requestId, photoPath } });
    const record = (await firestore.doc(`users/prober/generations/${requestId}`).get()).data() as GenerationRecord;
    const monster = record.monsterId ? ((await firestore.doc(`users/prober/monsters/${record.monsterId}`).get()).data() as MonsterDocument | undefined) : undefined;
    return {
      status: record.status,
      rejectionReason: record.rejectionReason,
      monsterId: record.monsterId,
      monsterName: monster?.definition.name,
      elementTypeIds: monster?.definition.elementTypeIds,
      claudeUsages: record.claudeUsages,
      jevInputTokens: record.jevInputTokens,
      failureMessage: record.failureMessage,
    };
  };
}

beforeEach(async () => {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
  await firestore.doc(`master/${master.version}`).set(master);
  const [files] = await bucket.getFiles();
  await Promise.all(files.map((file) => file.delete({ ignoreNotFound: true })));
});

afterAll(async () => {
  await deleteApp(app);
});

describe("probe-generation-paths (Emulator・外部の API はモック)", () => {
  it("テスト写真のすべての経路が expectations.json のとおりになる", async () => {
    const expectations = readExpectations();
    const rows = await probeGenerationPaths({ expectations, generatePhoto: createGeneratePhoto(createDependencies()) });
    expect(rows.map((row: { photoName: string }) => row.photoName)).toEqual(listProbePhotos({ expectations }).map((photo: { photoName: string }) => photo.photoName));
    expect(rows.filter((row: { verdict: string }) => row.verdict === "FAIL")).toEqual([]);
    expect(rows.find((row: { photoName: string }) => row.photoName === "same_subject/mug_another_shot.jpg")).toMatchObject({ status: "duplicate", duplicateOfPhotoName: "ordinary/mug.jpg" });
  });

  it("同じ被写体を別の物と判定すると、同じ被写体の経路が FAIL になる", async () => {
    const rows = await probeGenerationPaths({
      expectations: readExpectations(),
      pathNames: ["same_subject"],
      generatePhoto: createGeneratePhoto(createDependencies({ jevSaysDifferentForAll: true })),
    });
    expect(rows.filter((row: { verdict: string }) => row.verdict === "FAIL").map((row: { photoName: string }) => row.photoName)).toEqual([
      "same_subject/mug_another_shot.jpg",
      "same_subject/scissors_another_shot.jpg",
    ]);
  });
});
