/** 1 つのサービスが、いまメンテナンス中かどうか (状態を返す Worker の `GET /<サービス名>` の応答) */
export type MaintenanceState = {
  /** true の間、クライアントはメンテナンス中の画面を出し、サーバーは費用のかかる処理を断る */
  maintenance: boolean;
  /** 利用者に見せる文。null ならサービス側の既定の文 */
  message: string | null;
  /** メンテナンス中の画面に出すボタン。null ならボタンを出さない */
  button: { label: string; url: string } | null;
  /** 何が切り替えたか (owner のコマンド・利用料・利用量) */
  source: "owner" | "cost" | "usage";
  /** 最後に切り替わった時刻 (ISO 8601) */
  changedAt: string;
};

/** 状態が 1 度も書かれていない時と、状態を読めなかった時に使う「メンテナンス中でない」状態 */
export const NOT_IN_MAINTENANCE: MaintenanceState = {
  maintenance: false,
  message: null,
  button: null,
  // 通常に戻せるのは owner のコマンドだけのため、メンテナンス中でない状態の切り替え元は owner になる
  source: "owner",
  // 1 度も切り替わっていないことを、型 (ISO 8601 の文字列) を変えずに表せる値として UNIX 時刻の起点を使う
  changedAt: "1970-01-01T00:00:00.000Z",
};

/** 状態を読む時の入出力の差し替え口 */
export type MaintenanceFetchOptions = {
  /** 状態の取得に使う fetch。テストと、fetch を別の this で呼べない実行環境で差し替える */
  fetchImpl?: (url: string, init: { signal: AbortSignal }) => Promise<Response>;
  /** 応答を待つ上限 (ミリ秒) */
  timeoutMs?: number;
};

/**
 * 状態の応答を待つ上限の既定 (ミリ秒)。
 * サーバーは費用のかかる処理の入口でこの読み取りを待つため、状態を返す Worker が応答しない時に処理が待つ時間を 2 秒までにする
 * (service-maintenance-setup skill の SKILL.md「読む間隔と待つ上限」)
 */
export const DEFAULT_FETCH_TIMEOUT_MS = 2000;

/** ボタンの遷移先として開いてよい URL か (http・https だけ。javascript: 等を画面のリンクにしないため) */
function isOpenableURL(url: string): boolean {
  try {
    return ["http:", "https:"].includes(new URL(url).protocol);
  } catch {
    return false;
  }
}

/** JSON から読んだ値のうち、ボタンとして使えるものだけを返す。形が違う・開けない URL の時は null (ボタンを出さない) */
function parseButton(value: unknown): MaintenanceState["button"] {
  if (typeof value !== "object" || value === null) return null;
  const { label, url } = value as Record<string, unknown>;
  if (typeof label !== "string" || label === "" || typeof url !== "string" || !isOpenableURL(url)) return null;
  return { label, url };
}

/**
 * JSON から読んだ値を MaintenanceState として読む。maintenance・source・changedAt の形が違う時は null を返す。
 * message と button は、形が違っても状態全体を捨てず null にする (メンテナンス中の切り替えそのものを落とさないため)
 */
export function parseMaintenanceState(value: unknown): MaintenanceState | null {
  if (typeof value !== "object" || value === null) return null;
  const { maintenance, message, button, source, changedAt } = value as Record<string, unknown>;
  if (typeof maintenance !== "boolean") return null;
  if (source !== "owner" && source !== "cost" && source !== "usage") return null;
  if (typeof changedAt !== "string") return null;
  return {
    maintenance,
    message: typeof message === "string" && message !== "" ? message : null,
    button: parseButton(button),
    source,
    changedAt,
  };
}

/**
 * stateURL (`<状態を返す Worker の URL>/<サービス名>`) から状態を読む。
 * 読めなかった時 (通信の失敗・時間切れ・200 以外・形の違う応答) は NOT_IN_MAINTENANCE を返し、例外を投げない
 * (状態の置き場の障害で、読む側のサービスを止めないため)
 */
export async function fetchMaintenanceState(stateURL: string, options: MaintenanceFetchOptions = {}): Promise<MaintenanceState> {
  try {
    // options.fetchImpl が無い時は fetch をそのまま呼ぶ (fetch を変数に取り出して別の this で呼ぶと、Cloudflare Workers では Illegal invocation になる)
    const init = { signal: AbortSignal.timeout(options.timeoutMs ?? DEFAULT_FETCH_TIMEOUT_MS) };
    const response = await (options.fetchImpl === undefined ? fetch(stateURL, init) : options.fetchImpl(stateURL, init));
    if (!response.ok) return NOT_IN_MAINTENANCE;
    return parseMaintenanceState(await response.json()) ?? NOT_IN_MAINTENANCE;
  } catch {
    return NOT_IN_MAINTENANCE;
  }
}

/** 読んだ状態を一定時間覚える読み手の設定 */
export type MaintenanceReaderOptions = MaintenanceFetchOptions & {
  /** `<状態を返す Worker の URL>/<サービス名>` */
  stateURL: string;
  /** 読んだ状態を覚えておく時間 (ミリ秒) */
  cacheMs?: number;
  /** 現在時刻 (ミリ秒) を返す関数。テストで差し替える */
  now?: () => number;
  /**
   * 同時に呼ばれた読み直しを 1 回にまとめるか。Cloudflare Workers では false にする
   * (あるリクエストが始めた subrequest を別のリクエストが待つと、最初のリクエストが取り消された時に待つ側が解決されない)
   */
  shareConcurrentReads?: boolean;
};

/**
 * サーバーが読んだ状態を覚えておく時間の既定 (ミリ秒)。
 * 読む回数を 1 インスタンスあたり 1 分に 1 回までにし、切り替えてから処理を断り始めるまでの遅れを
 * deploy の反映の遅れに 60 秒を足した時間までにする (service-maintenance-setup skill の SKILL.md「読む間隔と待つ上限」)
 */
export const DEFAULT_SERVER_CACHE_MS = 60_000;

/**
 * サーバー用の読み手を作る。返す関数は、cacheMs の間は覚えた状態を返し、過ぎていれば読み直す。
 * 読めなかった結果 (NOT_IN_MAINTENANCE) も同じ時間覚える (状態の置き場が応答しない間、全部の処理が時間切れまで待たないようにするため)。
 * shareConcurrentReads が false でなければ、同時に呼ばれた読み直しは 1 回にまとめる。
 * まとめない時は、後から始めた読み取りの結果を先に覚えていれば、先に始めた読み取りの結果で上書きしない
 * (先に始めた読み取りが時間切れで後から返り、新しい状態を古い結果で cacheMs の間覆わないため)
 */
export function createMaintenanceReader(options: MaintenanceReaderOptions): () => Promise<MaintenanceState> {
  const now = options.now ?? Date.now;
  let cached: { state: MaintenanceState; readAt: number; readNumber: number } | null = null;
  let reading: Promise<MaintenanceState> | null = null;
  let latestReadNumber = 0;
  /** 状態を読んで返す。後から始めた読み取りの結果を既に覚えていなければ、読んだ状態を覚える */
  const readAndRemember = () => {
    const readNumber = ++latestReadNumber;
    return fetchMaintenanceState(options.stateURL, options).then((state) => {
      if (cached === null || cached.readNumber < readNumber) cached = { state, readAt: now(), readNumber };
      return state;
    });
  };
  return () => {
    if (cached !== null && now() - cached.readAt < (options.cacheMs ?? DEFAULT_SERVER_CACHE_MS)) return Promise.resolve(cached.state);
    if (options.shareConcurrentReads === false) return readAndRemember();
    reading ??= readAndRemember().finally(() => {
      reading = null;
    });
    return reading;
  };
}
