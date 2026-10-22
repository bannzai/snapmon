// 被写体の切り出しに使うモデル (isnet-general-use.onnx) を functions/models/ に取得する。
// デプロイ (firebase.json の predeploy) と CI (.github/workflows/firebase-ci.yml) の前に実行する。
// モデルは 178 MB あるためリポジトリに置かず、取得元を版と SHA-256 で固定する (選定の根拠は documents/adr/0002-subject-cutout-and-generation-cost.md)。
// 同じハッシュのファイルが既にあれば何もしない (冪等)。
import { createHash } from "node:crypto";
import { createReadStream, createWriteStream, existsSync, mkdirSync, renameSync } from "node:fs";
import path from "node:path";
import { Readable } from "node:stream";
import { pipeline } from "node:stream/promises";
import { fileURLToPath } from "node:url";

const MODEL_URL = "https://github.com/danielgatis/rembg/releases/download/v0.0.0/isnet-general-use.onnx";
const MODEL_SHA256 = "60920e99c45464f2ba57bee2ad08c919a52bbf852739e96947fbb4358c0d964a";
const modelDirectory = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "models");
const modelPath = path.join(modelDirectory, "isnet-general-use.onnx");

async function sha256(file) {
  const hash = createHash("sha256");
  await pipeline(createReadStream(file), hash);
  return hash.digest("hex");
}

if (existsSync(modelPath) && (await sha256(modelPath)) === MODEL_SHA256) {
  console.log(`[SKIP] ${modelPath} は取得済み`);
  process.exit(0);
}
mkdirSync(modelDirectory, { recursive: true });
const response = await fetch(MODEL_URL);
if (!response.ok) {
  console.error(`モデルを取得できませんでした: HTTP ${response.status}`);
  process.exit(1);
}
const temporaryPath = `${modelPath}.download`;
await pipeline(Readable.fromWeb(response.body), createWriteStream(temporaryPath));
const actualHash = await sha256(temporaryPath);
if (actualHash !== MODEL_SHA256) {
  console.error(`モデルのハッシュが違います: ${actualHash}`);
  process.exit(1);
}
renameSync(temporaryPath, modelPath);
console.log(`[FETCH] ${modelPath}`);
