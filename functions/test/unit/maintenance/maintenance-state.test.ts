import assert from "node:assert/strict";
import { test } from "vitest";

import { createMaintenanceReader, fetchMaintenanceState, parseMaintenanceState } from "../../../src/maintenance/maintenance-state";
import {
  fetchFailing,
  fetchReturning,
  IN_MAINTENANCE_WITH_BUTTON_JSON,
  IN_MAINTENANCE_WITHOUT_BUTTON_JSON,
  NOT_IN_MAINTENANCE_JSON,
  STATE_URL,
} from "./support/fixtures";

/** 状態を読めなかった時に使うと issue が決めた「メンテナンス中でない」状態 */
const UNREADABLE_FALLBACK = {
  maintenance: false,
  message: null,
  button: null,
  source: "owner",
  changedAt: "1970-01-01T00:00:00.000Z",
};

test("parseMaintenanceState: 5 つの項目がそろった値をそのまま読む", () => {
  assert.deepEqual(parseMaintenanceState(IN_MAINTENANCE_WITH_BUTTON_JSON), {
    maintenance: true,
    message: "復旧までお待ちください",
    button: { label: "お知らせを見る", url: "https://example.com/news" },
    source: "owner",
    changedAt: "2026-11-25T07:00:00.000Z",
  });
  assert.deepEqual(parseMaintenanceState(IN_MAINTENANCE_WITHOUT_BUTTON_JSON), {
    maintenance: true,
    message: null,
    button: null,
    source: "cost",
    changedAt: "2026-11-25T07:00:00.000Z",
  });
});

for (const [name, value] of [
  ["null", null],
  ["文字列", "maintenance"],
  ["maintenance が真偽値でない", { ...IN_MAINTENANCE_WITH_BUTTON_JSON, maintenance: "true" }],
  ["maintenance が無い", { message: null, button: null, source: "owner", changedAt: "2026-11-25T07:00:00.000Z" }],
  ["source が決まった 3 つの値でない", { ...IN_MAINTENANCE_WITH_BUTTON_JSON, source: "admin" }],
  ["changedAt が文字列でない", { ...IN_MAINTENANCE_WITH_BUTTON_JSON, changedAt: 1764054000 }],
] as const) {
  test(`parseMaintenanceState: ${name} は null を返す`, () => {
    assert.equal(parseMaintenanceState(value), null);
  });
}

for (const [name, button] of [
  ["url が javascript: の button", { label: "開く", url: "javascript:alert(1)" }],
  ["url が URL の形でない button", { label: "開く", url: "example.com/news" }],
  ["label が空の button", { label: "", url: "https://example.com/news" }],
  ["label が無い button", { url: "https://example.com/news" }],
  ["文字列の button", "https://example.com/news"],
  ["url が無い button", { label: "開く" }],
  ["url が数値の button", { label: "開く", url: 1 }],
  // 配列は文字列にすると開ける URL になるため、url が文字列かを確かめないと button として読まれる
  ["url が配列の button", { label: "開く", url: ["https://example.com/news"] }],
] as const) {
  test(`parseMaintenanceState: ${name} は、メンテナンス中のまま button だけ null にする`, () => {
    const state = parseMaintenanceState({ ...IN_MAINTENANCE_WITH_BUTTON_JSON, button });
    assert.equal(state?.maintenance, true);
    assert.equal(state?.button, null);
  });
}

test("parseMaintenanceState: source が usage の値をメンテナンス中として読む", () => {
  const state = parseMaintenanceState({ ...IN_MAINTENANCE_WITH_BUTTON_JSON, source: "usage" });
  assert.equal(state?.maintenance, true);
  assert.equal(state?.source, "usage");
});

test("parseMaintenanceState: http の url の button は読む", () => {
  assert.deepEqual(parseMaintenanceState({ ...IN_MAINTENANCE_WITH_BUTTON_JSON, button: { label: "開く", url: "http://example.com/" } })?.button, {
    label: "開く",
    url: "http://example.com/",
  });
});

test("parseMaintenanceState: 空文字と文字列でない message は null にする", () => {
  assert.equal(parseMaintenanceState({ ...IN_MAINTENANCE_WITH_BUTTON_JSON, message: "" })?.message, null);
  assert.equal(parseMaintenanceState({ ...IN_MAINTENANCE_WITH_BUTTON_JSON, message: 503 })?.message, null);
});

test("fetchMaintenanceState: stateURL を読み、応答の状態を返す", async () => {
  const requestedURLs: string[] = [];
  const state = await fetchMaintenanceState(STATE_URL, {
    fetchImpl: async (url) => {
      requestedURLs.push(url);
      return new Response(JSON.stringify(IN_MAINTENANCE_WITH_BUTTON_JSON));
    },
  });
  assert.deepEqual(requestedURLs, ["https://service-maintenance.example.workers.dev/snapmon"]);
  assert.equal(state.maintenance, true);
  assert.equal(state.message, "復旧までお待ちください");
});

for (const [name, fetchImpl] of [
  ["通信の失敗", fetchFailing],
  ["500 の応答 (body はメンテナンス中)", fetchReturning(IN_MAINTENANCE_WITH_BUTTON_JSON, 500).fetchImpl],
  ["404 の応答", fetchReturning({ error: "not found" }, 404).fetchImpl],
  ["JSON でない応答", async () => new Response("<html>error 1027</html>")],
  ["形の違う JSON", fetchReturning({ maintenance: "yes" }).fetchImpl],
] as const) {
  test(`fetchMaintenanceState: ${name}では例外を投げず、メンテナンス中でない状態を返す`, async () => {
    assert.deepEqual(await fetchMaintenanceState(STATE_URL, { fetchImpl }), UNREADABLE_FALLBACK);
  });
}

/**
 * abort が届くまで返らない fetch の代わり。abort が届いたら onAbort を呼んで reject する。
 * abort が届かない時 (時間切れが効かなくなった時) も 4 秒で reject し、テストが止まり続けないようにする
 * (4 秒は、既定の待つ上限 2 秒の倍。このタイマーは Node のプロセスも生かすため、待つ上限のタイマーが動かない時もテストが途中で終わらずに済む)
 */
function fetchUntilAbort(onAbort: () => void) {
  return (_url: string, init: { signal: AbortSignal }) =>
    new Promise<Response>((_resolve, reject) => {
      const giveUp = setTimeout(() => reject(new Error("abort が届かなかった")), 4_000);
      init.signal.addEventListener("abort", () => {
        clearTimeout(giveUp);
        onAbort();
        reject(init.signal.reason);
      });
    });
}

test("fetchMaintenanceState: timeoutMs までに応答が無ければ待つのをやめ、メンテナンス中でない状態を返す", async () => {
  let aborted = false;
  assert.deepEqual(
    await fetchMaintenanceState(STATE_URL, {
      timeoutMs: 10,
      fetchImpl: fetchUntilAbort(() => {
        aborted = true;
      }),
    }),
    UNREADABLE_FALLBACK,
  );
  assert.equal(aborted, true);
});

/**
 * AbortSignal.timeout が無い実行環境 (React Native は AbortSignal を timeout の無い polyfill に置き換える) を作って body を実行し、終わったら戻す。
 * Expo のアプリは maintenance-state.ts をそのまま写すため (SKILL.md「SwiftUI と Expo に組み込む」)、この環境でも状態を読めることを確かめる
 */
async function withoutAbortSignalTimeout(body: () => Promise<void>) {
  const originalAbortSignalTimeoutDescriptor = Object.getOwnPropertyDescriptor(AbortSignal, "timeout");
  Object.defineProperty(AbortSignal, "timeout", { value: undefined, configurable: true, writable: true });
  try {
    await body();
  } finally {
    if (originalAbortSignalTimeoutDescriptor !== undefined) Object.defineProperty(AbortSignal, "timeout", originalAbortSignalTimeoutDescriptor);
  }
}

test("fetchMaintenanceState: AbortSignal.timeout が無い実行環境でも、メンテナンス中の応答をメンテナンス中として読む", async () => {
  await withoutAbortSignalTimeout(async () => {
    const state = await fetchMaintenanceState(STATE_URL, { fetchImpl: fetchReturning(IN_MAINTENANCE_WITH_BUTTON_JSON).fetchImpl });
    assert.equal(state.maintenance, true);
    assert.equal(state.message, "復旧までお待ちください");
  });
});

test("fetchMaintenanceState: AbortSignal.timeout が無い実行環境でも、timeoutMs までに応答が無ければ待つのをやめる", async () => {
  await withoutAbortSignalTimeout(async () => {
    let aborted = false;
    assert.deepEqual(
      await fetchMaintenanceState(STATE_URL, {
        timeoutMs: 10,
        fetchImpl: fetchUntilAbort(() => {
          aborted = true;
        }),
      }),
      UNREADABLE_FALLBACK,
    );
    assert.equal(aborted, true);
  });
});

test("fetchMaintenanceState: ヘッダーが返った後に本文が届かなければ、timeoutMs で待つのをやめ、メンテナンス中でない状態を返す", async () => {
  let aborted = false;
  assert.deepEqual(
    await fetchMaintenanceState(STATE_URL, {
      timeoutMs: 10,
      fetchImpl: async (_url, init) =>
        new Response(
          new ReadableStream({
            start(controller) {
              const giveUp = setTimeout(() => controller.error(new Error("abort が届かなかった")), 4_000);
              init.signal.addEventListener("abort", () => {
                clearTimeout(giveUp);
                aborted = true;
                controller.error(init.signal.reason);
              });
            },
          }),
        ),
    }),
    UNREADABLE_FALLBACK,
  );
  assert.equal(aborted, true);
});

test("fetchMaintenanceState: 応答を読み終えた後に timeoutMs が過ぎても、渡した signal を abort しない (待つ上限のタイマーを残さない)", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const signals: AbortSignal[] = [];
  assert.equal(
    (
      await fetchMaintenanceState(STATE_URL, {
        timeoutMs: 1_000,
        fetchImpl: async (_url, init) => {
          signals.push(init.signal);
          return new Response(JSON.stringify(IN_MAINTENANCE_WITH_BUTTON_JSON));
        },
      })
    ).maintenance,
    true,
  );
  t.mock.timers.tick(1_000);
  assert.equal(signals.length, 1);
  assert.equal(signals[0].aborted, false);
});

test("createMaintenanceReader: cacheMs を渡さない時は 60 秒覚え、60 秒ちょうどで読み直す (SKILL.md「読む間隔と待つ上限」)", async () => {
  let nowMs = 0;
  const { fetchImpl, calls } = fetchReturning(NOT_IN_MAINTENANCE_JSON);
  const read = createMaintenanceReader({ stateURL: STATE_URL, fetchImpl, now: () => nowMs });
  await read();
  nowMs = 59_999;
  await read();
  assert.equal(calls(), 1);
  nowMs = 60_000;
  await read();
  assert.equal(calls(), 2);
});

test("fetchMaintenanceState: timeoutMs を渡さない時は 2 秒で待つのをやめる (SKILL.md「読む間隔と待つ上限」)", async () => {
  const startedAt = Date.now();
  let abortedAfterMs = -1;
  assert.deepEqual(
    await fetchMaintenanceState(STATE_URL, {
      fetchImpl: fetchUntilAbort(() => {
        abortedAfterMs = Date.now() - startedAt;
      }),
    }),
    UNREADABLE_FALLBACK,
  );
  // タイマーの遅れを見込んで、2 秒より前に止めていないことと、3 秒までに止めたことを確かめる
  assert.ok(abortedAfterMs >= 1_990 && abortedAfterMs < 3_000, `待つのをやめるまで ${abortedAfterMs} ms`);
});

test("createMaintenanceReader: cacheMs の間は読み直さず、cacheMs ちょうどで読み直す", async () => {
  let nowMs = 1_000_000;
  let body: unknown = NOT_IN_MAINTENANCE_JSON;
  let fetchCount = 0;
  const read = createMaintenanceReader({
    stateURL: STATE_URL,
    cacheMs: 60_000,
    now: () => nowMs,
    fetchImpl: async () => {
      fetchCount += 1;
      return new Response(JSON.stringify(body));
    },
  });
  assert.equal((await read()).maintenance, false);
  body = IN_MAINTENANCE_WITH_BUTTON_JSON;
  nowMs += 59_999;
  assert.equal((await read()).maintenance, false);
  assert.equal(fetchCount, 1);
  nowMs += 1;
  assert.equal((await read()).maintenance, true);
  assert.equal(fetchCount, 2);
});

test("createMaintenanceReader: 同時に呼ばれた読み直しは 1 回にまとめる", async () => {
  const { fetchImpl, calls } = fetchReturning(IN_MAINTENANCE_WITH_BUTTON_JSON);
  const read = createMaintenanceReader({ stateURL: STATE_URL, fetchImpl });
  assert.deepEqual(
    (await Promise.all([read(), read(), read()])).map((state) => state.maintenance),
    [true, true, true],
  );
  assert.equal(calls(), 1);
});

test("createMaintenanceReader: shareConcurrentReads が false の時は、同時の読み直しをまとめず、どれも結果を受け取り、結果を覚える", async () => {
  const { fetchImpl, calls } = fetchReturning(IN_MAINTENANCE_WITH_BUTTON_JSON);
  const read = createMaintenanceReader({ stateURL: STATE_URL, fetchImpl, shareConcurrentReads: false });
  assert.deepEqual(
    (await Promise.all([read(), read(), read()])).map((state) => state.maintenance),
    [true, true, true],
  );
  assert.equal(calls(), 3);
  assert.equal((await read()).maintenance, true);
  assert.equal(calls(), 3);
});

test("createMaintenanceReader: まとめない時、先に始めた読み取りが後から失敗で返っても、後から始めた読み取りの結果を覚えたままにする", async () => {
  const resolveResponses: ((response: Response) => void)[] = [];
  const rejectResponses: ((error: Error) => void)[] = [];
  const read = createMaintenanceReader({
    stateURL: STATE_URL,
    shareConcurrentReads: false,
    fetchImpl: () =>
      new Promise((resolve, reject) => {
        resolveResponses.push(resolve);
        rejectResponses.push(reject);
      }),
  });
  const first = read();
  const second = read();
  resolveResponses[1](new Response(JSON.stringify(IN_MAINTENANCE_WITH_BUTTON_JSON)));
  assert.equal((await second).maintenance, true);
  rejectResponses[0](new TypeError("fetch failed"));
  assert.deepEqual(await first, UNREADABLE_FALLBACK);
  assert.equal((await read()).maintenance, true);
  assert.equal(resolveResponses.length, 2);
});

test("createMaintenanceReader: まとめた読み直しが終わった後、cacheMs が過ぎれば次の読み直しを始める", async () => {
  let nowMs = 0;
  const { fetchImpl, calls } = fetchReturning(NOT_IN_MAINTENANCE_JSON);
  const read = createMaintenanceReader({ stateURL: STATE_URL, fetchImpl, cacheMs: 60_000, now: () => nowMs });
  await Promise.all([read(), read()]);
  assert.equal(calls(), 1);
  nowMs = 60_000;
  await read();
  assert.equal(calls(), 2);
});

test("createMaintenanceReader: 読めなかった結果も cacheMs の間覚え、過ぎたら読み直す", async () => {
  let nowMs = 0;
  let fetchCount = 0;
  const read = createMaintenanceReader({
    stateURL: STATE_URL,
    cacheMs: 60_000,
    now: () => nowMs,
    fetchImpl: async () => {
      fetchCount += 1;
      if (fetchCount === 1) throw new TypeError("fetch failed");
      return new Response(JSON.stringify(IN_MAINTENANCE_WITH_BUTTON_JSON));
    },
  });
  assert.deepEqual(await read(), UNREADABLE_FALLBACK);
  nowMs = 30_000;
  assert.deepEqual(await read(), UNREADABLE_FALLBACK);
  assert.equal(fetchCount, 1);
  nowMs = 60_000;
  assert.equal((await read()).maintenance, true);
  assert.equal(fetchCount, 2);
});
