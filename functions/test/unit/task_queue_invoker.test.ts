import { describe, expect, it } from "vitest";

import { deleteAccountFilesTask } from "../../src/account";
import { generate, resumeGenerationTask } from "../../src/generation/generate";
import { FUNCTIONS_SERVICE_ACCOUNT } from "../../src/service_account";

/** デプロイが読む関数の定義 (firebase-functions が関数に付ける manifest の 1 件)。テストで見る項目だけを書く。 */
type DeployedEndpoint = {
  taskQueueTrigger?: { invoker?: unknown };
  httpsTrigger?: { invoker?: unknown };
  callableTrigger?: unknown;
};

/** 関数の deploy 用の定義を取り出す。`__endpoint` は firebase-functions が付け、firebase-tools のデプロイが読む。 */
function deployedEndpoint(cloudFunction: unknown): DeployedEndpoint {
  return (cloudFunction as { __endpoint: DeployedEndpoint }).__endpoint;
}

// Cloud Tasks はタスクの OIDC トークン (実行サービスアカウント) で関数を呼ぶ。invoker が無いとデプロイが Cloud Run の
// run.invoker を誰にも付けず、呼び出しがすべて 403 になる (issue 255)。
describe("タスクキューの関数の invoker", () => {
  it.each([
    ["resumeGeneration", resumeGenerationTask],
    ["deleteAccountFiles", deleteAccountFilesTask],
  ])("%s は実行サービスアカウントに呼び出しを許す", (_name, cloudFunction) => {
    expect(deployedEndpoint(cloudFunction).taskQueueTrigger?.invoker).toEqual([FUNCTIONS_SERVICE_ACCOUNT]);
  });

  // invoker を全関数の既定 (setGlobalOptions) に置くと、アプリが呼ぶ callable まで実行サービスアカウント限定になり壊れる。
  it("callable の generate には invoker を付けない", () => {
    const endpoint = deployedEndpoint(generate);
    expect(endpoint.callableTrigger).toBeDefined();
    expect(endpoint.taskQueueTrigger).toBeUndefined();
    expect(endpoint.httpsTrigger?.invoker).toBeUndefined();
  });
});
