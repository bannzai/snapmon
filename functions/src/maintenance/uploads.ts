import { getStorage } from "firebase-admin/storage";
import { logger } from "firebase-functions";

import { STORAGE_BUCKET_NAME } from "../generation/dependencies";
import { assertNotInMaintenance } from "./firebase-functions-maintenance-guard";
import { readMaintenanceState } from "./reader";

/**
 * メンテナンス中なら、端末が呼び出しの前に Storage へ置いたファイルを消してから unavailable を投げる
 * (投げる値は assertNotInMaintenance と同じ)。メンテナンス中でない時と状態を読めない時は何もしない。
 * uploadedPaths は消すパスを返す関数で、メンテナンス中の時だけ呼ぶ。消してはいけない時 (同じ要求 ID の生成が既にあり、続きの段階が
 * そのファイルを読む時) は空の配列を返す。
 * 断った要求には生成のレコードも消すタスクも無く、誰も消さないため、ここで消す。端末はやり直すたびに置き直すため (生成は同じパスへ。
 * lib/features/capture/generation_screen.dart の _generate。アイコンは新しい uploadID で。lib/firebase/pvp.dart)、消しても次の呼び出しは
 * 進められる。消すのに失敗しても、断ることを優先して unavailable を投げる (消せなかったファイルはログに残す)。
 */
export async function assertNotInMaintenanceDeletingUploads({ uploadedPaths }: { uploadedPaths: () => Promise<string[]> }): Promise<void> {
  try {
    await assertNotInMaintenance(readMaintenanceState);
  } catch (error) {
    try {
      const bucket = getStorage().bucket(STORAGE_BUCKET_NAME);
      const paths = await uploadedPaths();
      (await Promise.allSettled(paths.map((path) => bucket.file(path).delete({ ignoreNotFound: true })))).forEach((result, index) => {
        if (result.status === "rejected") logger.warn("メンテナンス中に断った要求のファイルを消せませんでした", { path: paths[index], reason: String(result.reason) });
      });
    } catch (cleanupError) {
      logger.warn("メンテナンス中に断った要求のファイルを消せませんでした", { reason: String(cleanupError) });
    }
    throw error;
  }
}
