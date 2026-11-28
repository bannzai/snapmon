import assert from "node:assert/strict";
import { test } from "vitest";

import { assertNotInMaintenance } from "../../../src/maintenance/firebase-functions-maintenance-guard";
import { fetchFailing, fetchReturning, IN_MAINTENANCE_WITH_BUTTON_JSON, NOT_IN_MAINTENANCE_JSON, readerWith } from "./support/fixtures";

/** 入口で assertNotInMaintenance を待ってから費用のかかる処理を呼ぶ、Firebase Functions のハンドラーの形 */
async function firebaseHandler(readMaintenanceState: ReturnType<typeof readerWith>, costlyCall: () => void): Promise<string> {
  await assertNotInMaintenance(readMaintenanceState);
  costlyCall();
  return "generated";
}

test("メンテナンス中は unavailable のエラーで断り、費用のかかる処理を呼ばない", async () => {
  let costlyCallCount = 0;
  await assert.rejects(
    firebaseHandler(readerWith(fetchReturning(IN_MAINTENANCE_WITH_BUTTON_JSON).fetchImpl), () => {
      costlyCallCount += 1;
    }),
    (error: { code?: string; details?: unknown }) => {
      assert.equal(error.code, "unavailable");
      assert.deepEqual(error.details, {
        maintenance: {
          maintenance: true,
          message: "復旧までお待ちください",
          button: { label: "お知らせを見る", url: "https://example.com/news" },
          source: "owner",
          changedAt: "2026-11-25T07:00:00.000Z",
        },
      });
      return true;
    },
  );
  assert.equal(costlyCallCount, 0);
});

test("メンテナンス中でなければ処理を通す", async () => {
  let costlyCallCount = 0;
  assert.equal(
    await firebaseHandler(readerWith(fetchReturning(NOT_IN_MAINTENANCE_JSON).fetchImpl), () => {
      costlyCallCount += 1;
    }),
    "generated",
  );
  assert.equal(costlyCallCount, 1);
});

test("状態を読めない時は処理を通す", async () => {
  let costlyCallCount = 0;
  assert.equal(
    await firebaseHandler(readerWith(fetchFailing), () => {
      costlyCallCount += 1;
    }),
    "generated",
  );
  assert.equal(costlyCallCount, 1);
});
