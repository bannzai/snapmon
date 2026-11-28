import { createMaintenanceReader } from "../../../../src/maintenance/maintenance-state";

/** テストで状態を読む先として渡す URL */
export const STATE_URL = "https://service-maintenance.example.workers.dev/snapmon";

/** message と button を持つメンテナンス中の応答 (状態を返す Worker が返す JSON) */
export const IN_MAINTENANCE_WITH_BUTTON_JSON = {
  maintenance: true,
  message: "復旧までお待ちください",
  button: { label: "お知らせを見る", url: "https://example.com/news" },
  source: "owner",
  changedAt: "2026-11-25T07:00:00.000Z",
};

/** message も button も無いメンテナンス中の応答 */
export const IN_MAINTENANCE_WITHOUT_BUTTON_JSON = {
  maintenance: true,
  message: null,
  button: null,
  source: "cost",
  changedAt: "2026-11-25T07:00:00.000Z",
};

/** メンテナンス中でない応答 */
export const NOT_IN_MAINTENANCE_JSON = {
  maintenance: false,
  message: null,
  button: null,
  source: "owner",
  changedAt: "2026-11-25T08:00:00.000Z",
};

/** body を JSON で返す 200 の応答を返す fetch の代わり。呼ばれた回数を calls に数える */
export function fetchReturning(body: unknown, status = 200): { fetchImpl: () => Promise<Response>; calls: () => number } {
  let callCount = 0;
  return {
    calls: () => callCount,
    fetchImpl: async () => {
      callCount += 1;
      return new Response(JSON.stringify(body), { status });
    },
  };
}

/** fetchImpl で状態を読む、サーバー用の読み手を作る */
export function readerWith(fetchImpl: () => Promise<Response>) {
  return createMaintenanceReader({ stateURL: STATE_URL, fetchImpl });
}

/** 通信の失敗で reject する fetch の代わり */
export async function fetchFailing(): Promise<Response> {
  throw new TypeError("fetch failed");
}
