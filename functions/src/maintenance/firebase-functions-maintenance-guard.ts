import { HttpsError } from "firebase-functions/v2/https";

import type { MaintenanceState } from "./maintenance-state";

/**
 * メンテナンス中なら HttpsError("unavailable") を投げる。費用のかかる処理 (外部の API の呼び出し等) の前で await する。
 * readMaintenanceState には、モジュールの先頭で 1 度だけ作った createMaintenanceReader の戻り値を渡す (呼び出しごとに作ると、読んだ状態を覚えない)。
 * エラーの details の maintenance に状態を入れるため、クライアントは受けたエラーから message と button を出せる。
 * 状態を読めなかった時は readMaintenanceState が NOT_IN_MAINTENANCE を返すため、何も投げない
 */
export async function assertNotInMaintenance(readMaintenanceState: () => Promise<MaintenanceState>): Promise<void> {
  const state = await readMaintenanceState();
  if (state.maintenance) throw new HttpsError("unavailable", "The service is under maintenance", { maintenance: state });
}
