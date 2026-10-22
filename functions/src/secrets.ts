import { defineSecret } from "firebase-functions/params";

// 値は Secret Manager にだけ置き、コード・設定・リポジトリに書かない。
// 使う関数は `onCall({ secrets: [anthropicApiKey] }, ...)` のように束ね、本体で `anthropicApiKey.value()` を読む。
// index.ts から import されるまでデプロイは Secret の存在を検査しないため、Secret の登録前でも healthCheck・confirmAge をデプロイできる。

/** 写真の理解と名前・図鑑の文章の生成に使う Claude API のキー。 */
export const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");

/** 属性・技・ステータスの判定に使う Jev (TypeSafe) の API キー。 */
export const typesafeApiKey = defineSecret("TYPESAFE_API_KEY");
