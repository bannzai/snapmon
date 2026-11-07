import { defineSecret } from "firebase-functions/params";

// 値は Secret Manager にだけ置き、コード・設定・リポジトリに書かない。
// 使う関数は `onCall({ secrets: [typesafeApiKey] }, ...)` のように束ね、本体で `typesafeApiKey.value()` を読む。
// index.ts から import されるまでデプロイは Secret の存在を検査しないため、Secret の登録前でも healthCheck をデプロイできる。
// Claude API はキーを持たず WIF で認証する (anthropic.ts)。

/** 属性・技・ステータスの判定に使う Jev (TypeSafe) の API キー。 */
export const typesafeApiKey = defineSecret("TYPESAFE_API_KEY");

/** PvP の通報と生成チケットの購入を #snapmon-notification に知らせる Slack の bot token (slack.ts)。 */
export const slackBotToken = defineSecret("SLACK_BOT_TOKEN");

/**
 * RevenueCat の webhook が `Authorization` ヘッダーに付ける値 (generation_tickets.ts)。値は RevenueCat のダッシュボードで webhook を
 * 設定する時に owner が決め、同じ値を `firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTHORIZATION` で登録する。
 * このファイルは index.ts から読まれるため、登録されるまで Functions のデプロイ全体が失敗する (firebase-tools の
 * lib/deploy/functions/params.js の ensureSecret は、非対話のデプロイで Secret が無いと throw する)。
 */
export const revenueCatWebhookAuthorization = defineSecret("REVENUECAT_WEBHOOK_AUTHORIZATION");
