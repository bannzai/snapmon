// 機能を出すかの切り替え (Firestore の config/features) の 1 つのキーを書く。アプリが読み、クライアントからは書けない (firebase/firestore.rules)。
//
// 使い方: node scripts/set-feature-flag.mjs --project <プロジェクト ID> --key <キー> --value <true|false>
//
// 例: Action Card の画面を出す: node scripts/set-feature-flag.mjs --project snapmon-prod --key actionCardsVisible --value true
// 書けるキーは knownKeys だけ (打ち間違いのキーで画面が出ないままになるのを防ぐため)。
// 同じ値を書き直しても結果は変わらない (冪等)。他のキーは変えない (merge で書く)。
// 認証は Application Default Credentials (GOOGLE_APPLICATION_CREDENTIALS) を使う。
import { parseArgs } from "node:util";

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

/** config/features のキー。actionCardsVisible は Action Card の画面を出すか (無ければ出さない。documents/game-rules.md「Action Card」)。 */
const knownKeys = ["actionCardsVisible"];

const { values } = parseArgs({
  options: {
    project: { type: "string" },
    key: { type: "string" },
    value: { type: "string" },
  },
});
if (!values.project || !values.key || !values.value) {
  console.error("Usage: node scripts/set-feature-flag.mjs --project <プロジェクト ID> --key <キー> --value <true|false>");
  process.exit(2);
}
if (!knownKeys.includes(values.key)) {
  console.error(`--key は ${knownKeys.join(", ")} のどれかで指定してください: ${values.key}`);
  process.exit(2);
}
if (values.value !== "true" && values.value !== "false") {
  console.error(`--value は true か false で指定してください: ${values.value}`);
  process.exit(2);
}

initializeApp({ projectId: values.project });
await getFirestore().doc("config/features").set({ [values.key]: values.value === "true" }, { merge: true });
console.log(`[SET] config/features.${values.key} = ${values.value}`);
