// Slack の bot token で、サービスの通知チャンネルへ投稿する。
// token は Secret Manager の SLACK_BOT_TOKEN に置く (secrets.ts)。

/**
 * サービスの本番の通知チャンネル (ADR 0001 のクラッシュの行と同じ)。
 * 実行中のプロジェクト ID では送り先を切り替えない。テスト用の #test-notification に送るのは、投稿を起こす呼び出しに
 * テスト用の引数が付いている時だけで、Firestore のトリガーのように引数を渡せない関数はこのチャンネルに送る
 * (bannzai/castle の `home/.claude/documents/rules/slack-test-notification-channel.md`。https://github.com/bannzai/snapmon/issues/95 )。
 */
export const PRODUCTION_NOTIFICATION_CHANNEL = "#snapmon-notification";

/** Slack の [channel] に [text] を投稿する関数 (テストで差し替えるため、送る処理を引数で渡す)。 */
export type SendSlackMessage = (args: { channel: string; text: string }) => Promise<void>;

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
