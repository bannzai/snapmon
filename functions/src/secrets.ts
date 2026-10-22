import { defineSecret } from "firebase-functions/params";

// 値は Secret Manager にだけ置き、コード・設定・リポジトリに書かない。
// 使う関数は `onCall({ secrets: [typesafeApiKey] }, ...)` のように束ね、本体で `typesafeApiKey.value()` を読む。
// index.ts から import されるまでデプロイは Secret の存在を検査しないため、Secret の登録前でも healthCheck・confirmAge をデプロイできる。
// Claude API はキーを持たず WIF で認証する (anthropic.ts)。

/** 属性・技・ステータスの判定に使う Jev (TypeSafe) の API キー。 */
export const typesafeApiKey = defineSecret("TYPESAFE_API_KEY");

/** PvP の通報を #snapmon-notification に知らせる Slack の bot token (slack.ts)。 */
export const slackBotToken = defineSecret("SLACK_BOT_TOKEN");
