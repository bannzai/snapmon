import { randomUUID } from "node:crypto";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

import { deleteApp, getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import sharp from "sharp";
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";

import type { DescribeSubject, ProposeElement } from "../../src/generation/claude";
import { createSegmentSubject, SEGMENTATION_MODEL_PATH, type SegmentSubject } from "../../src/generation/cutout";
import { handleGenerateRequest } from "../../src/generation/generate";
import { type AskJev, type JevQuestion, type JevResponse, JevUnavailableError } from "../../src/generation/jev";
import type { Master } from "../../src/generation/master";
import { DAILY_GENERATION_LIMIT_PER_USER, DAILY_GENERATION_LIMIT_TOTAL, type GenerationDependencies, JUDGE_RETRY_INTERVAL_SECONDS, resumeGeneration, type ResumeTask } from "../../src/generation/pipeline";
import type { DescribeSubjectOutput } from "../../src/generation/prompts/describe_subject";
import type { GenerationRecord, MonsterDocument } from "../../src/generation/records";
import type { AnnotateImage, VisionAnnotation } from "../../src/generation/vision";

// firebase emulators:exec (package.json の test:emulator) の中で実行する。
// generate の本体 (handleGenerateRequest) を Firestore・Storage の Emulator に対して、外部の API (Vision・Claude・Jev) をモックにして呼ぶ。
// モックの呼び出し回数で、同じ要求の 2 回目や再試行が有料の API を呼び直さないことを確かめる。

const projectId = "demo-snapmon";
const app = getApps().find((existing) => existing.name === "generate-test") ?? initializeApp({ projectId }, "generate-test");
const firestore = getFirestore(app);
const bucket = getStorage(app).bucket("snapmon-prod-storage");
const master = JSON.parse(readFileSync(path.join(__dirname, "..", "..", "..", "assets", "master", "master.json"), "utf8")) as Master;
const descriptions = JSON.parse(readFileSync(path.join(__dirname, "..", "fixtures", "calibration", "descriptions.json"), "utf8")) as Record<string, DescribeSubjectOutput>;

beforeAll(async () => {
  await firestore.doc("master/1").set(master);
});

afterAll(async () => {
  await deleteApp(app);
});

beforeEach(async () => {
  await fetch(`http://127.0.0.1:8080/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
  await firestore.doc("master/1").set(master);
  const [files] = await bucket.getFiles();
  await Promise.all(files.map((file) => file.delete({ ignoreNotFound: true })));
});

/** 外部の API のモックと呼び出し回数。 */
interface Mocks {
  calls: { vision: number; segment: number; describe: number; propose: number; jev: Record<string, number> };
  dependencies: GenerationDependencies;
  enqueued: (ResumeTask & { delaySeconds: number })[];
}

/** Jev のモックの答え方。 */
interface JevBehavior {
  /** 同じ被写体の判定の肯定・否定の確率。 */
  dedupe: { same: number; different: number };
  /** 属性の当てはまりの確率 (無い属性は 0.05)。 */
  elementProbabilities: Record<string, number>;
  /** この種類の問いを含むリクエストで Jev が答えない (JevUnavailableError) か。 */
  unavailableFor: Set<"classify" | "dedupe" | "judge">;
}

function createMocks({
  vision = { safeSearchAnnotation: { adult: "VERY_UNLIKELY", violence: "VERY_UNLIKELY", racy: "VERY_UNLIKELY" }, labelAnnotations: [{ description: "Mug", score: 0.9 }] },
  description = descriptions["01"],
  jev = {},
  segmentSubject,
  describeFailureCount = 0,
}: {
  vision?: VisionAnnotation;
  description?: DescribeSubjectOutput;
  jev?: Partial<JevBehavior>;
  segmentSubject?: SegmentSubject;
  /** Claude のモックが最初の何回を一時的なエラーで落とすか。 */
  describeFailureCount?: number;
} = {}): Mocks & { jevBehavior: JevBehavior } {
  const jevBehavior: JevBehavior = {
    dedupe: { same: 0.05, different: 0.95 },
    elementProbabilities: { metal: 0.9 },
    unavailableFor: new Set(),
    ...jev,
  };
  const calls: Mocks["calls"] = { vision: 0, segment: 0, describe: 0, propose: 0, jev: {} };
  const enqueued: Mocks["enqueued"] = [];
  const annotateImage: AnnotateImage = async () => {
    calls.vision++;
    return vision;
  };
  const segment: SegmentSubject =
    segmentSubject ??
    (async (photo) => {
      calls.segment++;
      const { width, height } = await sharp(photo).metadata();
      return sharp({ create: { width: width!, height: height!, channels: 3, background: "#000000" } })
        .composite([{ input: { create: { width: Math.round(width! / 2), height: Math.round(height! / 2), channels: 3, background: "#ffffff" } }, left: Math.round(width! / 4), top: Math.round(height! / 4) }])
        .png()
        .toBuffer();
    });
  const describeSubject: DescribeSubject = async () => {
    calls.describe++;
    if (calls.describe <= describeFailureCount) {
      throw new Error("モックの Claude の一時的なエラー");
    }
    return { output: description, usage: { inputTokens: 1500, outputTokens: 700 } };
  };
  const proposeElement: ProposeElement = async () => {
    calls.propose++;
    return {
      output: {
        element: { displayName: "ろう", description: "ろうでできた物", colorHex: "#FFEEDD" },
        moves: [
          { displayName: "ろうアタック", power: 40, powerPoints: 30 },
          { displayName: "ろうプレス", power: 70, powerPoints: 15 },
          { displayName: "ろうバースト", power: 110, powerPoints: 5 },
        ],
      },
      usage: { inputTokens: 800, outputTokens: 200 },
    };
  };
  const askJev: AskJev = async (request) => {
    const names = Object.keys(request.questions);
    const kind = names.includes("category") ? "classify" : names.some((name) => name.startsWith("same__")) ? "dedupe" : names.some((name) => name.startsWith("element__")) ? "judge" : "same_definition";
    calls.jev[kind] = (calls.jev[kind] ?? 0) + 1;
    if (kind !== "same_definition" && jevBehavior.unavailableFor.has(kind)) {
      throw new JevUnavailableError("モックの Jev は答えない");
    }
    const answers: JevResponse["answers"] = {};
    for (const [name, question] of Object.entries(request.questions) as [string, JevQuestion][]) {
      if (question.type === "choice") {
        const choices = Object.keys(question.criteria);
        answers[name] = { type: "choice", choice: choices[0], confidence: 0.9, probabilities: Object.fromEntries(choices.map((choice) => [choice, choice === "tableware" ? 0.8 : 0.01])) };
      } else if (question.type === "score") {
        answers[name] = { type: "score", score: 2, confidence: 0.8, probabilities: Object.fromEntries(question.criteria.map((level) => [level, level === "ふつう" ? 0.8 : 0.05])) };
      } else if (name.startsWith("same__")) {
        answers[name] = { type: "noul", noul: jevBehavior.dedupe.same };
      } else if (name.startsWith("different__")) {
        answers[name] = { type: "noul", noul: jevBehavior.dedupe.different };
      } else if (name.startsWith("element__")) {
        answers[name] = { type: "noul", noul: jevBehavior.elementProbabilities[name.slice("element__".length)] ?? 0.05 };
      } else {
        answers[name] = { type: "noul", noul: 0.05 };
      }
    }
    return { model: "jev-1.13.0", answers, usage: { input_tokens: 1000, output_tokens: 10 } };
  };
  return {
    calls,
    enqueued,
    jevBehavior,
    dependencies: {
      firestore,
      bucket,
      annotateImage,
      segmentSubject: async (photo) => {
        if (segmentSubject) {
          calls.segment++;
        }
        return segment(photo);
      },
      describeSubject,
      proposeElement,
      askJev,
      enqueueResume: async (task) => {
        enqueued.push(task);
      },
      now: () => new Date(),
    },
  };
}

/** 本人の写真を Storage に置き、generate の data を返す。 */
async function uploadPhoto({ uid, photo }: { uid: string; photo: Buffer }) {
  const requestId = randomUUID();
  const photoPath = `users/${uid}/photos/${requestId}`;
  await bucket.file(photoPath).save(photo, { contentType: "image/jpeg", resumable: false });
  return { requestId, photoPath };
}

function photoFixture(sampleId: string): Buffer {
  return readFileSync(path.join(__dirname, "..", "fixtures", "calibration", "photos", `${sampleId}.jpg`));
}

function ageVerifiedRequest({ uid, data }: { uid: string; data: unknown }) {
  return { auth: { uid, token: { ageVerified: true } } as never, data };
}

async function generationRecord({ uid, requestId }: { uid: string; requestId: string }): Promise<GenerationRecord> {
  return (await firestore.doc(`users/${uid}/generations/${requestId}`).get()).data() as GenerationRecord;
}

describe("generate", () => {
  it("写真から 1 体を保存し、同じ requestId の 2 回目は API を呼ばずに保存済みの結果を返す", async () => {
    const mocks = createMocks();
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    const first = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }));
    expect(first.status).toBe("saved");
    const second = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }));
    expect(second).toEqual(first);
    expect(mocks.calls).toEqual({ vision: 1, segment: 1, describe: 1, propose: 0, jev: { classify: 1, judge: 1 } });

    const monster = (await firestore.doc(`users/alice/monsters/${first.monsterId}`).get()).data() as MonsterDocument;
    expect(monster.definition.name).toBe(descriptions["01"].name);
    expect(monster.definition.elementTypeIds).toEqual(["metal"]);
    expect(monster.definition.baseStats).toEqual({ hitPoints: 80, attack: 80, defense: 80, speed: 80 });
    expect(monster.categoryIds[0]).toBe("tableware");
    const [artExists] = await bucket.file(`monsters/${first.monsterId}/art.png`).exists();
    expect(artExists).toBe(true);
    // 中間の切り出し画像は saved で消し、元の写真は本人の図鑑のために残す
    expect((await bucket.file(`users/alice/generations/${data.requestId}/cutout.png`).exists())[0]).toBe(false);
    expect((await bucket.file(data.photoPath).exists())[0]).toBe(true);
    // ロックは外れている
    expect((await firestore.doc("users/alice").get()).get("generationLock")).toBeUndefined();
  });

  it("同じ写真を別の requestId で送ると、新しいレコードを作らず先の結果を返す", async () => {
    const mocks = createMocks();
    const firstData = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    const first = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: firstData }));
    const secondData = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    const second = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: secondData }));
    expect(second).toEqual(first);
    expect(mocks.calls.describe).toBe(1);
    // 使い回した時は、今回置かれた写真 (レコードが無い) を消し、先の生成の写真は残す
    expect((await bucket.file(secondData.photoPath).exists())[0]).toBe(false);
    expect((await bucket.file(firstData.photoPath).exists())[0]).toBe(true);
  });

  it("同じ被写体の別の写真は、Jev のモックが同じ物と答えると既存のモンスターを返し、属性の判定を呼ばない", async () => {
    const firstMocks = createMocks();
    const first = await handleGenerateRequest(firstMocks.dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("01") }) }));

    const secondMocks = createMocks({ description: descriptions["01b"], jev: { dedupe: { same: 0.9, different: 0.05 } } });
    const secondData = await uploadPhoto({ uid: "alice", photo: photoFixture("01b") });
    const second = await handleGenerateRequest(secondMocks.dependencies, ageVerifiedRequest({ uid: "alice", data: secondData }));
    expect(second).toMatchObject({ status: "duplicate", monsterId: first.monsterId });
    expect(secondMocks.calls.jev).toEqual({ classify: 1, dedupe: 1 });
    // 重複の写真は消す
    expect((await bucket.file(secondData.photoPath).exists())[0]).toBe(false);
  });

  it("同じ種類の別の物 (Jev のモックが別の物と答える) は別のモンスターとして保存する", async () => {
    await handleGenerateRequest(createMocks().dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("01") }) }));
    const mocks = createMocks({ description: descriptions["28"] });
    const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("28") }) }));
    expect(result.status).toBe("saved");
    expect(mocks.calls.jev).toEqual({ classify: 1, dedupe: 1, judge: 1 });
  });

  it("別のユーザーの同じ被写体は重複にしない (二重登録の防止はユーザー単位)", async () => {
    await handleGenerateRequest(createMocks().dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("01") }) }));
    const mocks = createMocks({ jev: { dedupe: { same: 0.9, different: 0.05 } } });
    const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "bob", data: await uploadPhoto({ uid: "bob", photo: photoFixture("01") }) }));
    expect(result.status).toBe("saved");
    expect(mocks.calls.jev.dedupe).toBeUndefined();
  });

  it("SafeSearch で拒否される画像は生成せず理由を返し、写真を消す", async () => {
    const mocks = createMocks({ vision: { safeSearchAnnotation: { adult: "VERY_LIKELY" } } });
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }));
    expect(result).toMatchObject({ status: "rejected", rejectionReason: "explicit_content" });
    expect(mocks.calls).toMatchObject({ segment: 0, describe: 0, jev: {} });
    expect((await bucket.file(data.photoPath).exists())[0]).toBe(false);
  });

  it("顔が写る画像は生成せず理由を返す", async () => {
    const mocks = createMocks({ vision: { safeSearchAnnotation: { adult: "VERY_UNLIKELY" }, faceAnnotations: [{ detectionConfidence: 0.95 }] } });
    const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("01") }) }));
    expect(result).toMatchObject({ status: "rejected", rejectionReason: "face_detected" });
    expect(mocks.calls.describe).toBe(0);
  });

  it("Claude が人が写っていると答えた画像は生成しない", async () => {
    const mocks = createMocks({ description: { ...descriptions["01"], containsPerson: true } });
    const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("01") }) }));
    expect(result).toMatchObject({ status: "rejected", rejectionReason: "person_detected" });
  });

  // 単色の写真を実際のモデルで切り出す。CI は firebase-ci.yml で `npm run fetch-model` してから実行し、手元でモデルが無い時だけ飛ばす。
  it.skipIf(!existsSync(SEGMENTATION_MODEL_PATH) && !process.env.CI)(
    "被写体を切り出せない画像 (単色の画像) は rejected になり理由を返し、Claude を呼ばない",
    async () => {
      const mocks = createMocks({ segmentSubject: createSegmentSubject({ modelPath: SEGMENTATION_MODEL_PATH }) });
      const uniform = await sharp({ create: { width: 640, height: 480, channels: 3, background: { r: 200, g: 180, b: 150 } } }).jpeg().toBuffer();
      const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: uniform }) }));
      expect(result).toMatchObject({ status: "rejected", rejectionReason: "no_subject" });
      expect(mocks.calls.describe).toBe(0);
    },
    60_000,
  );

  it("手で決めた範囲のマスクを送ると、自動のマスクを作らずにそのマスクで切り出す", async () => {
    const mocks = createMocks();
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    const maskPath = `users/alice/masks/${data.requestId}`;
    const emptyMask = await sharp({ create: { width: 64, height: 48, channels: 3, background: "#000000" } }).png().toBuffer();
    await bucket.file(maskPath).save(emptyMask, { contentType: "image/png", resumable: false });
    const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: { ...data, maskPath } }));
    expect(result).toMatchObject({ status: "rejected", rejectionReason: "no_subject" });
    expect(mocks.calls.segment).toBe(0);
  });

  it("Jev が答えない時は pending_judge で保存し、再試行で続きから完了する (Claude を呼び直さない)", async () => {
    const mocks = createMocks({ jev: { unavailableFor: new Set(["judge"]) } });
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    const pending = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }));
    expect(pending.status).toBe("pending_judge");
    expect(await generationRecord({ uid: "alice", requestId: data.requestId })).toMatchObject({ status: "pending_judge", completedStage: "dedupe" });
    expect(mocks.enqueued).toContainEqual({
      uid: "alice",
      requestId: data.requestId,
      purpose: "judge",
      delaySeconds: JUDGE_RETRY_INTERVAL_SECONDS,
      taskId: `alice-${data.requestId}-judge-0`,
    });
    // 判定待ちの間はロックを外し、同じ uid の別の生成を止めない
    expect((await firestore.doc("users/alice").get()).get("generationLock")).toBeUndefined();

    mocks.jevBehavior.unavailableFor.clear();
    // 予約切れの引き継ぎのタスクは判定待ちを進めない (1 時間おきの系列を 1 つにするため)
    expect((await resumeGeneration(mocks.dependencies, { uid: "alice", requestId: data.requestId, purpose: "lease" })).status).toBe("pending_judge");
    const resumed = await resumeGeneration(mocks.dependencies, { uid: "alice", requestId: data.requestId, purpose: "judge" });
    expect(resumed.status).toBe("saved");
    expect(mocks.calls).toMatchObject({ vision: 1, segment: 1, describe: 1, jev: { classify: 1, judge: 2 } });
    expect((await generationRecord({ uid: "alice", requestId: data.requestId })).judgeRetryCount).toBe(1);
  });

  it("Claude の一時的なエラーで落ちた生成は、再試行のタスクが済んだ段階を飛ばして続きから完了する", async () => {
    const mocks = createMocks({ describeFailureCount: 1 });
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    await expect(handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }))).rejects.toThrow("一時的なエラー");
    expect(await generationRecord({ uid: "alice", requestId: data.requestId })).toMatchObject({ status: "processing", completedStage: "cutout" });
    expect(mocks.enqueued.at(-1)).toEqual({ uid: "alice", requestId: data.requestId, purpose: "lease", delaySeconds: 60 });

    const resumed = await resumeGeneration(mocks.dependencies, { uid: "alice", requestId: data.requestId, purpose: "lease" });
    expect(resumed.status).toBe("saved");
    expect(mocks.calls).toMatchObject({ vision: 1, segment: 1, describe: 2 });
    // 引き継いだ実行にも、予約切れを引き継ぐタスクを積む
    expect(mocks.enqueued.filter((task) => task.purpose === "lease" && task.delaySeconds > 600)).toHaveLength(2);
  });

  it("再試行を待つ処理中の生成と同じ被写体なら、その結果を待ち、保存された後にそのモンスターを返す", async () => {
    const stalledMocks = createMocks();
    const stalledData = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    await handleGenerateRequest(stalledMocks.dependencies, ageVerifiedRequest({ uid: "alice", data: stalledData }));
    // 保存の手前で止まった状態 (judge まで済んだ処理中・予約切れ・ロックなし) を作る
    await firestore.doc(`users/alice/generations/${stalledData.requestId}`).update({ status: "processing", completedStage: "judge", leaseExpiresAt: Timestamp.fromMillis(0) });
    const savedMonsterId = (await generationRecord({ uid: "alice", requestId: stalledData.requestId })).monsterId!;
    await firestore.doc(`users/alice/monsters/${savedMonsterId}`).delete();

    const mocks = createMocks({ description: descriptions["01b"], jev: { dedupe: { same: 0.9, different: 0.05 } } });
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01b") });
    expect((await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }))).status).toBe("pending_judge");
    expect(mocks.calls.jev.judge).toBeUndefined();

    expect((await resumeGeneration(stalledMocks.dependencies, { uid: "alice", requestId: stalledData.requestId, purpose: "lease" })).status).toBe("saved");
    const resumed = await resumeGeneration(mocks.dependencies, { uid: "alice", requestId: data.requestId, purpose: "judge" });
    expect(resumed).toMatchObject({ status: "duplicate", monsterId: savedMonsterId });
  });

  it("同じ被写体の相手の生成が失敗したら、待っていた生成は保存に進む", async () => {
    const otherData = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    await handleGenerateRequest(createMocks().dependencies, ageVerifiedRequest({ uid: "alice", data: otherData }));
    await firestore.doc(`users/alice/generations/${otherData.requestId}`).update({ status: "pending_judge" });
    const savedMonsterId = (await generationRecord({ uid: "alice", requestId: otherData.requestId })).monsterId!;
    await firestore.doc(`users/alice/monsters/${savedMonsterId}`).delete();

    const mocks = createMocks({ description: descriptions["01b"], jev: { dedupe: { same: 0.9, different: 0.05 } } });
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01b") });
    expect((await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }))).status).toBe("pending_judge");
    await firestore.doc(`users/alice/generations/${otherData.requestId}`).update({ status: "failed" });
    expect((await resumeGeneration(mocks.dependencies, { uid: "alice", requestId: data.requestId, purpose: "judge" })).status).toBe("saved");
  });

  it("受け付けた後に写真が差し替えられたら、差し替えた写真を検査せずに使わず failed にする", async () => {
    const mocks = createMocks();
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    mocks.dependencies.annotateImage = async () => {
      mocks.calls.vision++;
      await bucket.file(data.photoPath).save(photoFixture("28"), { contentType: "image/jpeg", resumable: false });
      return { safeSearchAnnotation: { adult: "VERY_UNLIKELY" } };
    };
    const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }));
    expect(result.status).toBe("failed");
    expect(mocks.calls).toMatchObject({ segment: 0, describe: 0 });
  });

  it("拒否した写真を消し損ねても、再試行のタスクが消して記録する", async () => {
    const mocks = createMocks({ vision: { safeSearchAnnotation: { adult: "VERY_LIKELY" } } });
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    const realBucket = mocks.dependencies.bucket;
    // 削除だけが失敗するバケット
    mocks.dependencies.bucket = Object.create(realBucket, {
      file: {
        value: (path: string) =>
          Object.assign(Object.create(realBucket.file(path)), {
            delete: async () => {
              throw new Error("一時的な削除の失敗");
            },
          }),
      },
    });
    const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }));
    expect(result).toMatchObject({ status: "rejected" });
    expect((await bucket.file(data.photoPath).exists())[0]).toBe(true);
    expect(mocks.enqueued.at(-1)).toMatchObject({ purpose: "lease" });

    mocks.dependencies.bucket = realBucket;
    await resumeGeneration(mocks.dependencies, { uid: "alice", requestId: data.requestId, purpose: "lease" });
    expect((await bucket.file(data.photoPath).exists())[0]).toBe(false);
    expect((await generationRecord({ uid: "alice", requestId: data.requestId })).filesDeleted).toBe(true);
  });

  it("判定待ちの再試行が上限を超えたら failed にする", async () => {
    const mocks = createMocks({ jev: { unavailableFor: new Set(["classify"]) } });
    const data = await uploadPhoto({ uid: "alice", photo: photoFixture("01") });
    await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }));
    await firestore.doc(`users/alice/generations/${data.requestId}`).update({ judgeRetryCount: 24 });
    expect((await resumeGeneration(mocks.dependencies, { uid: "alice", requestId: data.requestId, purpose: "judge" })).status).toBe("failed");
  });

  it("どの属性にも当てはまらない時は、Claude の提案から新しい属性を版付きで definitions に保存して使う", async () => {
    const mocks = createMocks({ jev: { elementProbabilities: {} } });
    const result = await handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("18") }) }));
    expect(result.status).toBe("saved");
    expect(mocks.calls.propose).toBe(1);
    const monster = (await firestore.doc(`users/alice/monsters/${result.monsterId}`).get()).data() as MonsterDocument;
    const [elementTypeId] = monster.definition.elementTypeIds;
    expect(monster.definitionIds).toEqual([elementTypeId]);
    const definition = (await firestore.doc(`definitions/${elementTypeId}`).get()).data()!;
    expect(definition).toMatchObject({ version: 1, elementTypes: [{ id: elementTypeId, displayName: "ろう" }] });
    expect(monster.definition.learnset.map((entry) => entry.moveId)).toEqual([`${elementTypeId}_1`, `${elementTypeId}_2`, `${elementTypeId}_3`]);
    expect((await firestore.doc("definitionCounters/global").get()).data()).toEqual({ elementCount: 1, moveCount: 3 });
  });
});

describe("generate の上限と検査", () => {
  const today = new Intl.DateTimeFormat("sv-SE", { timeZone: "Asia/Tokyo" }).format(new Date());

  it("uid ごとの 1 日の上限を超えると生成しない", async () => {
    await firestore.doc("users/alice").set({ dailyGeneration: { date: today, count: DAILY_GENERATION_LIMIT_PER_USER } });
    const mocks = createMocks();
    await expect(
      handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("01") }) })),
    ).rejects.toMatchObject({ code: "resource-exhausted" });
    expect(mocks.calls.vision).toBe(0);
  });

  it("前日の回数は数えない", async () => {
    await firestore.doc("users/alice").set({ dailyGeneration: { date: "2000-01-01", count: DAILY_GENERATION_LIMIT_PER_USER } });
    const result = await handleGenerateRequest(createMocks().dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("01") }) }));
    expect(result.status).toBe("saved");
    expect((await firestore.doc("users/alice").get()).get("dailyGeneration")).toEqual({ date: today, count: 1 });
  });

  it("プロジェクト全体の 1 日の上限を超えると生成しない", async () => {
    await firestore.doc(`generationDailyCounts/${today}`).set({ count: DAILY_GENERATION_LIMIT_TOTAL });
    const mocks = createMocks();
    await expect(
      handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("01") }) })),
    ).rejects.toMatchObject({ code: "resource-exhausted" });
  });

  it("同じ uid の別の生成が進んでいる間は受け付けない", async () => {
    await firestore.doc("users/alice").set({ generationLock: { requestId: randomUUID(), expiresAt: Timestamp.fromMillis(Date.now() + 60_000) } });
    await expect(
      handleGenerateRequest(createMocks().dependencies, ageVerifiedRequest({ uid: "alice", data: await uploadPhoto({ uid: "alice", photo: photoFixture("01") }) })),
    ).rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("年齢の確認のクレームが無い呼び出しと、他人の写真のパスを弾く", async () => {
    const mocks = createMocks();
    const data = await uploadPhoto({ uid: "bob", photo: photoFixture("01") });
    await expect(handleGenerateRequest(mocks.dependencies, { auth: { uid: "bob", token: {} } as never, data })).rejects.toMatchObject({ code: "permission-denied" });
    await expect(handleGenerateRequest(mocks.dependencies, ageVerifiedRequest({ uid: "alice", data }))).rejects.toMatchObject({ code: "invalid-argument" });
    expect(mocks.calls.vision).toBe(0);
  });
});
