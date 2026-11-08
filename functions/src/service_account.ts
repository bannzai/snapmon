/**
 * Functions の実行サービスアカウント。Claude API の WIF の federation rule が、このサービスアカウントの email と uniqueId の
 * ID トークンだけを受け付けるため (anthropic.ts)、全関数をこれで動かす (index.ts の setGlobalOptions)。
 * firebase-admin の taskQueue().enqueue は実行サービスアカウントをタスクの OIDC トークンに使うため、Cloud Tasks がタスクの関数を
 * 呼ぶ時の呼び出し元もこれになる (タスクの関数の `invoker`)。
 * ロールの付与とデプロイ用サービスアカウントの actAs は .claude/rules/firebase-config-files.md の「Claude API の認証」。
 */
export const FUNCTIONS_SERVICE_ACCOUNT = "snapmon-functions@snapmon-prod.iam.gserviceaccount.com";
