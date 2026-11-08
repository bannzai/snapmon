import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

import { FUNCTIONS_SERVICE_ACCOUNT } from "./service_account";

// asia-northeast1: Firestore・Storage と同じリージョンに置き、読み書きの往復を短くするため。
// maxInstances 10: 匿名ログインで uid を作り放題な間、暴走時の課金の上限を抑えるため (原価の上限は ADR 0001)。
// serviceAccount を選んだ理由は service_account.ts。
setGlobalOptions({
  region: "asia-northeast1",
  maxInstances: 10,
  serviceAccount: FUNCTIONS_SERVICE_ACCOUNT,
});
initializeApp();

export { deleteAccount, deleteAccountFilesTask as deleteAccountFiles } from "./account";
export { recordBattle, startBattle } from "./battle";
export { generate, resumeGenerationTask as resumeGeneration } from "./generation/generate";
export { revenueCatWebhook } from "./generation_tickets";
export { healthCheck } from "./health_check";
export { setProfileIcon } from "./profile";
export { blockUser, fetchOpponents, getDisplayName, notifyReport, reportMonster, setDisplayName } from "./pvp";
