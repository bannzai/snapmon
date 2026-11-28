import { afterEach, expect, it, vi } from "vitest";

import { IN_MAINTENANCE_WITH_BUTTON_JSON } from "./support/fixtures";

afterEach(() => {
  vi.unstubAllGlobals();
});

// 本番の読み手 (reader.ts) が、グローバルの fetch で snapmon の状態の URL を読み、その応答を状態にすることを確かめる。
// 費用のかかる関数のテスト (entries.test.ts) は reader.ts を差し替えるため、ここで差し替えずに呼ぶ
it("readMaintenanceState は snapmon の状態の URL を読み、その応答を返す", async () => {
  const fetchMock = vi.fn(async () => new Response(JSON.stringify(IN_MAINTENANCE_WITH_BUTTON_JSON), { status: 200 }));
  vi.stubGlobal("fetch", fetchMock);
  const { readMaintenanceState } = await import("../../../src/maintenance/reader");

  await expect(readMaintenanceState()).resolves.toEqual(IN_MAINTENANCE_WITH_BUTTON_JSON);
  expect(fetchMock).toHaveBeenCalledTimes(1);
  expect(String(fetchMock.mock.calls[0]?.[0])).toBe("https://service-maintenance.star-kojiki.workers.dev/snapmon");
});
