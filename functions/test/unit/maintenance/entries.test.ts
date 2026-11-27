import { beforeEach, describe, expect, it, vi } from "vitest";

import type { MaintenanceState } from "../../../src/maintenance/maintenance-state";
import { IN_MAINTENANCE_WITH_BUTTON_JSON, NOT_IN_MAINTENANCE_JSON } from "./support/fixtures";

// 費用のかかる関数 (generate・resumeGeneration・setProfileIcon) の本物の入口を `.run()` で呼び、メンテナンス中は外部の API
// (Vision・Claude・Jev) を 1 回も呼ばずに断ることを確かめる。外部の API のクライアントは createProductionDependencies だけが作るため、
// それを差し替えて呼ばれた回数を数える。

/** 差し替えた readMaintenanceState が返す状態。各 describe の beforeEach が決める */
const maintenanceState = vi.hoisted(() => ({ current: null as MaintenanceState | null }));

vi.mock("../../../src/maintenance/reader", () => ({
  readMaintenanceState: async () => maintenanceState.current,
}));

/** 差し替えた createProductionDependencies を作った回数と、それが返す依存の外部の API の呼び出し回数・積んだタスクの記録 */
const externalCalls = vi.hoisted(() => ({ annotateImage: 0, describeSubject: 0, proposeElement: 0, askJev: 0, enqueuedTasks: [] as unknown[], dependencyCreations: 0 }));

/** 通常どおり進んだ時に、入口の検査の先へ進んだことを見分けるためにテストの依存が投げるエラー */
class ReachedProductionDependenciesError extends Error {}

/** 差し替えた createProductionDependencies の振る舞い。throwOnCreate が true の時は依存を作る時点で ReachedProductionDependenciesError を投げる */
const productionDependenciesBehavior = vi.hoisted(() => ({ throwOnCreate: false }));

vi.mock("../../../src/generation/dependencies", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../../src/generation/dependencies")>()),
  createProductionDependencies: () => {
    externalCalls.dependencyCreations += 1;
    if (productionDependenciesBehavior.throwOnCreate) throw new ReachedProductionDependenciesError();
    return {
      annotateImage: async () => {
        externalCalls.annotateImage += 1;
        throw new Error("Vision を呼んだ");
      },
      describeSubject: async () => {
        externalCalls.describeSubject += 1;
        throw new Error("Claude を呼んだ");
      },
      proposeElement: async () => {
        externalCalls.proposeElement += 1;
        throw new Error("Claude を呼んだ");
      },
      askJev: async () => {
        externalCalls.askJev += 1;
        throw new Error("Jev を呼んだ");
      },
      enqueueResume: async (task: unknown) => {
        externalCalls.enqueuedTasks.push(task);
      },
    };
  },
}));

/** resumeGeneration (pipeline.ts) を呼んだ回数。resumeGenerationTask が生成を進めたかを見分ける */
const resumeGenerationCalls = vi.hoisted(() => ({ count: 0 }));

vi.mock("../../../src/generation/pipeline", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../../../src/generation/pipeline")>()),
  resumeGeneration: async () => {
    resumeGenerationCalls.count += 1;
  },
}));

const { generate, MAINTENANCE_RESUME_DELAY_SECONDS, resumeGenerationTask } = await import("../../../src/generation/generate");
const { setProfileIcon } = await import("../../../src/profile");

/** 外部の API の呼び出しの合計 */
function externalAPICallCount(): number {
  return externalCalls.annotateImage + externalCalls.describeSubject + externalCalls.proposeElement + externalCalls.askJev;
}

/** callable の `.run()` に渡す、ログインした利用者の要求 */
function signedInRequest(data: unknown) {
  return { data, auth: { uid: "alice", token: {} }, rawRequest: {}, acceptsStreaming: false } as never;
}

/** resumeGeneration のタスクに渡す入力。判定の再試行の途中 (judgeAttempt 3) のタスク */
const resumeTask = { uid: "alice", requestID: "00000000-0000-4000-8000-000000000000", purpose: "judge" as const, judgeAttempt: 3 };

beforeEach(() => {
  Object.assign(externalCalls, { annotateImage: 0, describeSubject: 0, proposeElement: 0, askJev: 0, enqueuedTasks: [], dependencyCreations: 0 });
  productionDependenciesBehavior.throwOnCreate = false;
  resumeGenerationCalls.count = 0;
});

describe("メンテナンス中", () => {
  beforeEach(() => {
    maintenanceState.current = IN_MAINTENANCE_WITH_BUTTON_JSON as MaintenanceState;
  });

  it.each([
    ["generate", () => generate.run(signedInRequest({ requestID: resumeTask.requestID, photoPath: `users/alice/photos/${resumeTask.requestID}` }))],
    ["setProfileIcon", () => setProfileIcon.run(signedInRequest({ uploadID: resumeTask.requestID }))],
  ])("%s は外部の API を呼ばずに unavailable で断る", async (_name, call) => {
    await expect(call()).rejects.toMatchObject({ code: "unavailable", details: { maintenance: IN_MAINTENANCE_WITH_BUTTON_JSON } });
    expect(externalCalls.dependencyCreations).toBe(0);
    expect(externalAPICallCount()).toBe(0);
  });

  it("resumeGeneration は外部の API を呼ばず、同じタスクを後に積み直して成功で終える", async () => {
    await resumeGenerationTask.run({ data: resumeTask } as never);
    expect(externalAPICallCount()).toBe(0);
    expect(externalCalls.enqueuedTasks).toEqual([{ ...resumeTask, delaySeconds: MAINTENANCE_RESUME_DELAY_SECONDS }]);
    expect(resumeGenerationCalls.count).toBe(0);
  });
});

describe("メンテナンス中でない時", () => {
  beforeEach(() => {
    maintenanceState.current = NOT_IN_MAINTENANCE_JSON as MaintenanceState;
    productionDependenciesBehavior.throwOnCreate = true;
  });

  it.each([
    ["generate", () => generate.run(signedInRequest({ requestID: resumeTask.requestID, photoPath: `users/alice/photos/${resumeTask.requestID}` }))],
    ["setProfileIcon", () => setProfileIcon.run(signedInRequest({ uploadID: resumeTask.requestID }))],
  ])("%s は入口を通って生成・検査の依存を作る", async (_name, call) => {
    await expect(call()).rejects.toBeInstanceOf(ReachedProductionDependenciesError);
    expect(externalCalls.dependencyCreations).toBe(1);
    expect(externalCalls.enqueuedTasks).toEqual([]);
  });

  it("resumeGeneration は積み直さずに生成を進める", async () => {
    productionDependenciesBehavior.throwOnCreate = false;
    await resumeGenerationTask.run({ data: resumeTask } as never);
    expect(resumeGenerationCalls.count).toBe(1);
    expect(externalCalls.enqueuedTasks).toEqual([]);
  });
});
