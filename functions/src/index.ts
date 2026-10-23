import { initializeApp } from "firebase-admin/app";
import { setGlobalOptions } from "firebase-functions/v2";

// asia-northeast1: Firestore・Storage と同じリージョンに置き、読み書きの往復を短くするため。
// maxInstances 10: 匿名ログインで uid を作り放題な間、暴走時の課金の上限を抑えるため (原価の上限は ADR 0001)。
// serviceAccount: Claude API の WIF の federation rule が、このサービスアカウントの email と uniqueId の ID トークンだけを受け付けるため (anthropic.ts)。
// ロールの付与とデプロイ用サービスアカウントの actAs は .claude/rules/firebase-config-files.md の「Claude API の認証」。
setGlobalOptions({
  region: "asia-northeast1",
  maxInstances: 10,
  serviceAccount: "snapmon-functions@snapmon-prod.iam.gserviceaccount.com",
});
initializeApp();

export { deleteAccount, deleteAccountFilesTask as deleteAccountFiles } from "./account";
export { recordBattle, startBattle } from "./battle";
export { generate, resumeGenerationTask as resumeGeneration } from "./generation/generate";
export { healthCheck } from "./health_check";
export { blockUser, fetchOpponents, getDisplayName, notifyReport, reportMonster, setDisplayName } from "./pvp";
