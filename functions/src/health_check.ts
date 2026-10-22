import { TokenCache } from "@anthropic-ai/sdk/lib/credentials/token-cache";
import { onRequest } from "firebase-functions/v2/https";

import { anthropicFederationProvider, anthropicTokenExchangeStatus } from "./anthropic";

// 公開の HTTP 関数のため、呼ばれるたびにトークンを交換しないよう、インスタンス内で交換したトークンを期限まで使い回す。
let anthropicTokenCache: TokenCache | undefined;

/**
 * デプロイ後の疎通確認に使う HTTP 関数。`{"status":"ok","anthropicTokenExchange":"ok"|"failed"|"not_configured"}` を返し、データの読み書きはしない。
 * `anthropicTokenExchange` は Claude API の WIF のトークン交換が成功するか (anthropic.ts)。トークンの値は返さない。
 *
 * App Check を必須にしない: デプロイ後に `curl` で応答を確かめるため (アプリ以外から呼べる必要がある)。
 * データにも有料の API にも触れない (トークン交換は課金されない) ため、App Check の対象から外しても弾くべき呼び出しが無い。
 */
export const healthCheck = onRequest(async (_request, response) => {
  const provider = anthropicFederationProvider({ env: process.env, fetchFunction: fetch });
  if (provider) {
    anthropicTokenCache ??= new TokenCache(provider);
  }
  response.json({ status: "ok", anthropicTokenExchange: await anthropicTokenExchangeStatus(anthropicTokenCache) });
});
