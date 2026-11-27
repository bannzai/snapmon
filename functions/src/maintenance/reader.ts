// snapmon がメンテナンス中かを読む、Functions で 1 つだけの読み手。費用のかかる関数 (generate・resumeGeneration・setProfileIcon) が
// 外部の API (Vision・Claude・Jev) を呼ぶ前に読む。状態の切り替えは owner が `service-maintenance on snapmon` / `off snapmon` で行う
// (castle の service-maintenance-setup skill。https://github.com/bannzai/castle/issues/3490 )。

import { createMaintenanceReader } from "./maintenance-state";

/** snapmon の状態を返す URL (`<状態を返す Worker の URL>/<サービス名>`)。誰でも読める公開の URL。 */
export const SNAPMON_MAINTENANCE_STATE_URL = "https://service-maintenance.star-kojiki.workers.dev/snapmon";

/**
 * 読んだ状態をインスタンスごとに 60 秒覚える読み手 (maintenance-state.ts の createMaintenanceReader)。
 * 関数ごとに作ると覚えた状態を使い回せないため、モジュールの先頭で 1 度だけ作る。
 */
export const readMaintenanceState = createMaintenanceReader({ stateURL: SNAPMON_MAINTENANCE_STATE_URL });
