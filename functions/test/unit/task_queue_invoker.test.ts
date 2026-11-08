import { describe, expect, it } from "vitest";

import { deleteAccountFilesTask } from "../../src/account";
import { generate, resumeGenerationTask } from "../../src/generation/generate";
import { FUNCTIONS_SERVICE_ACCOUNT } from "../../src/service_account";

// `__endpoint` は firebase-functions が関数に付ける deploy 用の定義 (ManifestEndpoint) で、firebase-tools のデプロイが読む。
// Cloud Tasks はタスクの OIDC トークン (実行サービスアカウント) で関数を呼ぶ。invoker が無いとデプロイが Cloud Run の
// run.invoker を誰にも付けず、呼び出しがすべて 403 になる (issue 255)。
describe("タスクキューの関数の invoker", () => {
  it.each([
    ["resumeGeneration", resumeGenerationTask],
    ["deleteAccountFiles", deleteAccountFilesTask],
  ])("%s は実行サービスアカウントに呼び出しを許す", (_name, cloudFunction) => {
    expect(cloudFunction.__endpoint.taskQueueTrigger?.invoker).toEqual([FUNCTIONS_SERVICE_ACCOUNT]);
  });

  // invoker を全関数の既定 (setGlobalOptions) に置くと、アプリが呼ぶ callable まで実行サービスアカウント限定になり壊れる。
  it("callable の generate には invoker を付けない", () => {
    const endpoint = generate.__endpoint;
    expect(endpoint.callableTrigger).toBeDefined();
    expect(endpoint.taskQueueTrigger).toBeUndefined();
    expect(endpoint.httpsTrigger?.invoker).toBeUndefined();
  });
});
