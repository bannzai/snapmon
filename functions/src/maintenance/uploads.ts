import { getStorage } from "firebase-admin/storage";

import { STORAGE_BUCKET_NAME } from "../generation/dependencies";
import { assertNotInMaintenance } from "./firebase-functions-maintenance-guard";
import { readMaintenanceState } from "./reader";

/**
 * メンテナンス中なら、端末が呼び出しの前に Storage へ置いたファイル (uploadedPaths) を消してから unavailable を投げる
 * (投げる値は assertNotInMaintenance と同じ)。メンテナンス中でない時と状態を読めない時は何もしない。
 * 断った要求には生成のレコードも消すタスクも無く、誰も消さないため、ここで消す。端末はやり直すたびに置き直すため (生成は同じパスへ。lib/features/capture/generation_screen.dart の _generate。
 * アイコンは新しい uploadID で。lib/firebase/pvp.dart)、消しても次の呼び出しは進められる。
 */
export async function assertNotInMaintenanceDeletingUploads({ uploadedPaths }: { uploadedPaths: string[] }): Promise<void> {
  try {
    await assertNotInMaintenance(readMaintenanceState);
  } catch (error) {
    const bucket = getStorage().bucket(STORAGE_BUCKET_NAME);
    await Promise.all(uploadedPaths.map((path) => bucket.file(path).delete({ ignoreNotFound: true })));
    throw error;
  }
}
