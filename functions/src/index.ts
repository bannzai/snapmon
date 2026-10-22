import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

// asia-northeast1: Firestore・Storage と同じリージョンに置き、読み書きの往復を短くするため。
// maxInstances 10: 匿名ログインで uid を作り放題な間、暴走時の課金の上限を抑えるため (原価の上限は ADR 0001)。
setGlobalOptions({ region: "asia-northeast1", maxInstances: 10 });
initializeApp();

export { recordBattle, startBattle } from "./battle";
export { confirmAge } from "./confirm_age";
export { healthCheck } from "./health_check";
