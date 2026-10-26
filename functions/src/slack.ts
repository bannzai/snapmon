// Slack の bot token で、サービスの通知チャンネルへ投稿する。
// token は Secret Manager の SLACK_BOT_TOKEN に置き (secrets.ts)、送り先は notificationChannel が実行中のプロジェクトから決める。

/**
 * 実行中のプロジェクト [projectId] から、通知を送る Slack のチャンネルを返す。
 * 本番 (snapmon-prod) と判定できた時だけ ADR 0001 のクラッシュの行と同じ #snapmon-notification にし、
 * それ以外 (dev・QA・ローカル・空文字) は #snapmon-notification-qa にする。
 * 判定できない時を -qa に倒すのは、QA の投稿で本番のお問い合わせ・アラートを埋もれさせないため
 * (bannzai/castle の `home/.claude/documents/rules/qa-notifications-to-separate-channel.md`。https://github.com/bannzai/snapmon/issues/56 )。
 */
export function notificationChannel(projectId: string): string {
  return projectId === "snapmon-prod" ? "#snapmon-notification" : "#snapmon-notification-qa";
}

/**
 * Functions の環境変数 [env] から実行中のプロジェクト ID を返す。
 * `GCLOUD_PROJECT` が無ければ `FIREBASE_CONFIG` の JSON の `projectId` を使う (どちらも Functions のランタイムが入れる。
 * https://firebase.google.com/docs/functions/config-env の「Automatically populated environment variables」)。
 * どちらからも読めない時は空文字を返す (notificationChannel が -qa に倒す。通知の処理を例外で止めて通知そのものを失わないため)。
 */
export function functionsProjectId(env: NodeJS.ProcessEnv): string {
  if (env.GCLOUD_PROJECT) {
    return env.GCLOUD_PROJECT;
  }
  try {
    const projectId = (JSON.parse(env.FIREBASE_CONFIG ?? "") as { projectId?: unknown }).projectId;
    return typeof projectId === "string" ? projectId : "";
  } catch {
    return "";
  }
}

/** Slack に [text] を投稿する関数 (テストで差し替えるため、送る処理を引数で渡す)。 */
export type SendSlackMessage = (args: { text: string }) => Promise<void>;

/**
 * bot token [token] で [channel] に [text] を chat.postMessage で投稿する。
 * token が空の時は送らずに例外を投げる (Secret の登録漏れを通信のエラーより先に分かるようにするため)。
 * Slack が `ok: false` を返した時も例外を投げる (chat.postMessage は失敗でも HTTP 200 を返すため。
 * https://docs.slack.dev/reference/methods/chat.postMessage の「Errors」は `ok: false` と `error` で返る)。
 */
export async function postSlackMessage({
  token,
  channel,
  text,
  fetchFunction,
}: {
  token: string;
  channel: string;
  text: string;
  fetchFunction: typeof fetch;
}): Promise<void> {
  if (token === "") {
    throw new Error("SLACK_BOT_TOKEN が設定されていないため Slack に送れません");
  }
  const response = await fetchFunction("https://slack.com/api/chat.postMessage", {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({ channel, text }),
  });
  const body = (await response.json()) as { ok?: boolean; error?: string };
  if (!response.ok || body.ok !== true) {
    throw new Error(`Slack への投稿に失敗しました: HTTP ${response.status} ${body.error ?? ""}`);
  }
}
