import { TokenCache } from "@anthropic-ai/sdk/lib/credentials/token-cache";
import { describe, expect, it, vi } from "vitest";

import { anthropicFederationProvider, anthropicTokenExchangeStatus, createAnthropicClient } from "../../src/anthropic";

const federationEnv = {
  ANTHROPIC_FEDERATION_RULE_ID: "fdrl_test",
  ANTHROPIC_ORGANIZATION_ID: "org-test",
  ANTHROPIC_SERVICE_ACCOUNT_ID: "svac_test",
  ANTHROPIC_WORKSPACE_ID: "wrkspc_test",
};

/** メタデータサーバーとトークン交換の応答を返す偽の fetch。呼ばれた URL と引数を記録する。 */
function fakeFetch({
  metadataStatus = 200,
  accessToken = "sk-ant-oat01-test",
}: {
  metadataStatus?: number;
  accessToken?: string;
} = {}) {
  return vi.fn(async (input: string | URL | Request, _init?: RequestInit) => {
    const url = String(input);
    if (url.startsWith("http://metadata.google.internal/")) {
      return new Response(metadataStatus === 200 ? "google-id-token" : "not found", { status: metadataStatus });
    }
    if (url === "https://api.anthropic.com/v1/oauth/token") {
      return new Response(JSON.stringify({ access_token: accessToken, expires_in: 600, token_type: "Bearer" }), {
        status: 200,
        headers: { "content-type": "application/json" },
      });
    }
    throw new Error(`想定していない URL: ${url}`);
  });
}

describe("createAnthropicClient", () => {
  it("WIF の環境変数 4 つがある時は WIF で認証し、API キーを使わない", async () => {
    const fetchFunction = fakeFetch();
    const client = createAnthropicClient({
      env: { ...federationEnv, ANTHROPIC_API_KEY: "sk-ant-api-test" },
      fetchFunction,
    });
    expect(client.apiKey).toBeNull();
    expect(client.credentials).not.toBeNull();
    await expect(client.credentials!()).resolves.toMatchObject({ token: "sk-ant-oat01-test" });
  });

  it("WIF の環境変数が無く ANTHROPIC_API_KEY がある時はキーで認証する", () => {
    const client = createAnthropicClient({ env: { ANTHROPIC_API_KEY: "sk-ant-api-test" }, fetchFunction: fakeFetch() });
    expect(client.apiKey).toBe("sk-ant-api-test");
    expect(client.credentials).toBeNull();
  });

  it("どちらも無い時は throw する", () => {
    expect(() => createAnthropicClient({ env: {}, fetchFunction: fakeFetch() })).toThrow("Claude API の認証情報がありません");
  });

  it("WIF の環境変数が一部だけの時は、API キーがあっても throw する", () => {
    expect(() =>
      createAnthropicClient({
        env: { ANTHROPIC_FEDERATION_RULE_ID: "fdrl_test", ANTHROPIC_API_KEY: "sk-ant-api-test" },
        fetchFunction: fakeFetch(),
      }),
    ).toThrow("ANTHROPIC_ORGANIZATION_ID, ANTHROPIC_SERVICE_ACCOUNT_ID, ANTHROPIC_WORKSPACE_ID");
  });
});

describe("anthropicFederationProvider", () => {
  it("メタデータサーバーの ID トークンを、環境変数の ID を付けてトークン交換に送る", async () => {
    const fetchFunction = fakeFetch();
    await anthropicFederationProvider({ env: federationEnv, fetchFunction })!();

    const [metadataURL, metadataInit] = fetchFunction.mock.calls[0]!;
    expect(String(metadataURL)).toBe(
      "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=https://api.anthropic.com&format=full",
    );
    expect(metadataInit?.headers).toEqual({ "Metadata-Flavor": "Google" });

    const [exchangeURL, exchangeInit] = fetchFunction.mock.calls[1]!;
    expect(String(exchangeURL)).toBe("https://api.anthropic.com/v1/oauth/token");
    expect(JSON.parse(String(exchangeInit?.body))).toEqual({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: "google-id-token",
      federation_rule_id: "fdrl_test",
      organization_id: "org-test",
      service_account_id: "svac_test",
      workspace_id: "wrkspc_test",
    });
  });

  it("メタデータサーバーが 2xx 以外を返したら、本文を交換に送らず throw する", async () => {
    const fetchFunction = fakeFetch({ metadataStatus: 404 });
    await expect(anthropicFederationProvider({ env: federationEnv, fetchFunction })!()).rejects.toThrow("status 404");
    expect(fetchFunction).toHaveBeenCalledTimes(1);
  });

  it("WIF の環境変数が 1 つも無ければ undefined を返す", () => {
    expect(anthropicFederationProvider({ env: {}, fetchFunction: fakeFetch() })).toBeUndefined();
  });

  it("GCLOUD_PROJECT が snapmon-prod なら、環境変数が無くても snapmon-prod の ID で交換する", async () => {
    const fetchFunction = fakeFetch();
    await anthropicFederationProvider({ env: { GCLOUD_PROJECT: "snapmon-prod" }, fetchFunction })!();
    expect(JSON.parse(String(fetchFunction.mock.calls[1]![1]?.body))).toMatchObject({
      federation_rule_id: "fdrl_01DXt4bSNmwgMLgexoMjsWYc",
      organization_id: "1f64bb71-74d6-4ffc-98d5-3ab3daaa5ceb",
      service_account_id: "svac_012vURDWhcnEHesFSEoUSVkW",
      workspace_id: "wrkspc_01Xs2a9LZXWcFit1HzMDVZME",
    });
  });

  it("GCLOUD_PROJECT が snapmon-prod 以外 (Emulator の demo-snapmon) なら snapmon-prod の ID を使わない", () => {
    expect(anthropicFederationProvider({ env: { GCLOUD_PROJECT: "demo-snapmon" }, fetchFunction: fakeFetch() })).toBeUndefined();
  });
});

describe("anthropicTokenExchangeStatus", () => {
  it("sk-ant-oat01- で始まるトークンを得たら ok", async () => {
    const provider = anthropicFederationProvider({ env: federationEnv, fetchFunction: fakeFetch() })!;
    await expect(anthropicTokenExchangeStatus(new TokenCache(provider))).resolves.toBe("ok");
  });

  it("想定と違う形式のトークンなら failed", async () => {
    const provider = anthropicFederationProvider({
      env: federationEnv,
      fetchFunction: fakeFetch({ accessToken: "unexpected" }),
    })!;
    await expect(anthropicTokenExchangeStatus(new TokenCache(provider))).resolves.toBe("failed");
  });

  it("交換に失敗したら throw せず failed", async () => {
    const provider = anthropicFederationProvider({
      env: federationEnv,
      fetchFunction: fakeFetch({ metadataStatus: 500 }),
    })!;
    await expect(anthropicTokenExchangeStatus(new TokenCache(provider))).resolves.toBe("failed");
  });

  it("WIF を設定していない環境では not_configured", async () => {
    await expect(anthropicTokenExchangeStatus(undefined)).resolves.toBe("not_configured");
  });

  it("2 回目以降は交換をやり直さず、期限までトークンを使い回す", async () => {
    const fetchFunction = fakeFetch();
    const tokenCache = new TokenCache(anthropicFederationProvider({ env: federationEnv, fetchFunction })!);
    await anthropicTokenExchangeStatus(tokenCache);
    await anthropicTokenExchangeStatus(tokenCache);
    expect(fetchFunction).toHaveBeenCalledTimes(2);
  });
});
