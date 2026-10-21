import { onRequest } from "firebase-functions/v2/https";

/**
 * デプロイ後の疎通確認に使う HTTP 関数。`{"status":"ok"}` を返すだけで、データの読み書きはしない。
 *
 * App Check を必須にしない: デプロイ後に `curl` で応答を確かめるため (アプリ以外から呼べる必要がある)。
 * データにも有料の API にも触れないため、App Check の対象から外しても弾くべき呼び出しが無い。
 */
export const healthCheck = onRequest((_request, response) => {
  response.json({ status: "ok" });
});
