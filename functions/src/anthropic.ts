import Anthropic from "@anthropic-ai/sdk";
import { oidcFederationProvider } from "@anthropic-ai/sdk/lib/credentials/oidc-federation";
import type { TokenCache } from "@anthropic-ai/sdk/lib/credentials/token-cache";
import type { AccessTokenProvider } from "@anthropic-ai/sdk/lib/credentials/types";
import { logger } from "firebase-functions";

// 認証は Workload Identity Federation (WIF) で行い、静的な API キーを持たない (#24)。
// Functions の実行サービスアカウント (index.ts の setGlobalOptions) の ID トークンを、Anthropic の短命トークンに交換する。
// 公式: https://platform.claude.com/docs/en/manage-claude/wif-providers/gcp

const ANTHROPIC_BASE_URL = "https://api.anthropic.com";

// audience は Console の federation rule の audience と一致させる。format=full は rule が照合する email のクレームを含めるため。
const GOOGLE_IDENTITY_TOKEN_URL =
  "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/identity?audience=https://api.anthropic.com&format=full";

/** WIF のトークン交換に使う環境変数の名前。 */
const FEDERATION_ENV_NAMES = [
  "ANTHROPIC_FEDERATION_RULE_ID",
  "ANTHROPIC_ORGANIZATION_ID",
  "ANTHROPIC_SERVICE_ACCOUNT_ID",
  "ANTHROPIC_WORKSPACE_ID",
] as const;

/**
 * snapmon-prod で使う WIF の ID (Claude Console の Workload identity で作った rule・organization・service account・workspace)。
 * 秘密ではないためコードに置く (`.env` は agent の permissions で読み書きを禁じているため、2026-10-22 に bannzai が選んだ)。
 */
const SNAPMON_PROD_FEDERATION_ENV: Record<(typeof FEDERATION_ENV_NAMES)[number], string> = {
  ANTHROPIC_FEDERATION_RULE_ID: "fdrl_01DXt4bSNmwgMLgexoMjsWYc",
  ANTHROPIC_ORGANIZATION_ID: "1f64bb71-74d6-4ffc-98d5-3ab3daaa5ceb",
  ANTHROPIC_SERVICE_ACCOUNT_ID: "svac_012vURDWhcnEHesFSEoUSVkW",
  ANTHROPIC_WORKSPACE_ID: "wrkspc_01Xs2a9LZXWcFit1HzMDVZME",
};

/** healthCheck が返すトークン交換の結果。`not_configured` は WIF の環境変数が無い環境 (Emulator・ローカル)。 */
export type AnthropicTokenExchangeStatus = "ok" | "failed" | "not_configured";

/**
 * メタデータサーバーから、実行サービスアカウントの Google 署名の ID トークン (JWT) を取得する。
 * 応答が 2xx でなければ throw する (エラーの本文を JWT として交換に送らないため)。
 */
async function fetchGoogleIdentityToken(fetchFunction: typeof fetch): Promise<string> {
  const response = await fetchFunction(GOOGLE_IDENTITY_TOKEN_URL, { headers: { "Metadata-Flavor": "Google" } });
  if (!response.ok) {
    throw new Error(`メタデータサーバーから ID トークンを取得できませんでした (status ${response.status})`);
  }
  return response.text();
}

/**
 * WIF の環境変数 4 つが揃っていれば、ID トークンを Anthropic のアクセストークンに交換する provider を返す。
 * `GCLOUD_PROJECT` (Firebase が Functions に設定する) が snapmon-prod の時は、環境変数に無い ID を snapmon-prod の ID で補う。
 * 1 つも無ければ undefined を返す。一部だけある時は設定の誤りとして throw する
 * (本番で API キーの経路へ黙って切り替わらないため)。provider を作るだけで、交換は呼ばれた時に行う。
 */
export function anthropicFederationProvider({
  env: functionsEnv,
  fetchFunction,
}: {
  env: NodeJS.ProcessEnv;
  fetchFunction: typeof fetch;
}): AccessTokenProvider | undefined {
  const env = functionsEnv.GCLOUD_PROJECT === "snapmon-prod" ? { ...SNAPMON_PROD_FEDERATION_ENV, ...functionsEnv } : functionsEnv;
  const missingNames = FEDERATION_ENV_NAMES.filter((name) => !env[name]);
  if (missingNames.length === FEDERATION_ENV_NAMES.length) {
    return undefined;
  }
  if (missingNames.length > 0) {
    throw new Error(`WIF の環境変数が足りません: ${missingNames.join(", ")}`);
  }
  return oidcFederationProvider({
    identityTokenProvider: () => fetchGoogleIdentityToken(fetchFunction),
    federationRuleId: env.ANTHROPIC_FEDERATION_RULE_ID!,
    organizationId: env.ANTHROPIC_ORGANIZATION_ID!,
    serviceAccountId: env.ANTHROPIC_SERVICE_ACCOUNT_ID,
    workspaceId: env.ANTHROPIC_WORKSPACE_ID,
    baseURL: ANTHROPIC_BASE_URL,
    fetch: fetchFunction,
  });
}

/**
 * Claude API のクライアントを作る。WIF の環境変数 4 つがあれば (snapmon-prod では常に) WIF で、無ければ `ANTHROPIC_API_KEY` (ローカル・Emulator 用) で認証する。
 * どちらも無い時と、WIF の環境変数が一部だけの時は throw する。
 * モジュールの読み込み時には呼ばない: Emulator のテストとデプロイ時の関数の検出は、どちらの値も無い環境でモジュールを読むため。
 */
export function createAnthropicClient({
  env,
  fetchFunction,
}: {
  env: NodeJS.ProcessEnv;
  fetchFunction: typeof fetch;
}): Anthropic {
  const credentials = anthropicFederationProvider({ env, fetchFunction });
  if (credentials) {
    return new Anthropic({ credentials, fetch: fetchFunction });
  }
  if (env.ANTHROPIC_API_KEY) {
    return new Anthropic({ apiKey: env.ANTHROPIC_API_KEY, fetch: fetchFunction });
  }
  throw new Error(`Claude API の認証情報がありません: ${FEDERATION_ENV_NAMES.join(", ")} か ANTHROPIC_API_KEY を設定してください`);
}

/**
 * トークン交換が成功するかを返す。`sk-ant-oat01-` で始まるアクセストークンを得た時だけ `ok` にする。
 * トークンの値は返さず、失敗の詳細 (request-id 等) はログにだけ書く。
 */
export async function anthropicTokenExchangeStatus(tokenCache: TokenCache | undefined): Promise<AnthropicTokenExchangeStatus> {
  if (!tokenCache) {
    return "not_configured";
  }
  try {
    if ((await tokenCache.getToken()).startsWith("sk-ant-oat01-")) {
      return "ok";
    }
    logger.error("Anthropic のトークン交換が想定と違う形式のトークンを返しました");
    return "failed";
  } catch (error) {
    logger.error("Anthropic のトークン交換に失敗しました", error);
    return "failed";
  }
}
