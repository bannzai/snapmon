// master (属性・技・相性表・分類) の 1 つの版を Firestore の master/{version} に投入する。
// Functions のデプロイ (.github/workflows/deploy-functions.yml の master_file 入力) から呼ぶ。
//
// 使い方: node scripts/seed-master.mjs --project <プロジェクト ID> --version <版番号> --file <master の JSON>
//
// 版は一度投入したら変えない (モンスターは判定に使った master の版を参照し続けるため。ADR 0001)。
// 同じ版が既にあれば書き換えずに終える (冪等)。中身を変える時は版番号を上げて投入する。
// 認証は Application Default Credentials (GOOGLE_APPLICATION_CREDENTIALS) を使う。
import { readFileSync } from "node:fs";
import { parseArgs } from "node:util";

import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

const { values } = parseArgs({
  options: {
    project: { type: "string" },
    version: { type: "string" },
    file: { type: "string" },
  },
});
if (!values.project || !values.version || !values.file) {
  console.error("Usage: node scripts/seed-master.mjs --project <プロジェクト ID> --version <版番号> --file <master の JSON>");
  process.exit(2);
}
if (!/^[1-9][0-9]*$/.test(values.version)) {
  console.error(`--version は 1 以上の整数で指定してください: ${values.version}`);
  process.exit(2);
}

const master = JSON.parse(readFileSync(values.file, "utf8"));
initializeApp({ projectId: values.project });
const masterDocument = getFirestore().doc(`master/${values.version}`);

// Firestore の ALREADY_EXISTS のエラーコード (gRPC の 6)。
const alreadyExistsCode = 6;
try {
  await masterDocument.create({ ...master, version: Number(values.version) });
  console.log(`[CREATE] master/${values.version}`);
} catch (error) {
  if (error.code !== alreadyExistsCode) {
    throw error;
  }
  console.log(`[SKIP] master/${values.version} は投入済み`);
}
