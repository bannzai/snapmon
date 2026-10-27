// 生成の経路ごとのテスト写真 (test/fixtures/photos/) を generate に順に送り、結果を期待 (expectations.json) と突き合わせて表にする。
// アプリと同じ経路 (匿名ログイン → 写真を Storage へ置く → generate) を HTTP で通し、終わったら匿名ユーザーを deleteAccount で消す。
// 同じ被写体の判定はユーザー単位のため、1 回の実行の写真は 1 人の匿名ユーザーで expectations.json の paths の順に送る。
//
// 使い方: node scripts/probe-generation-paths.mjs --project <snapmon-prod | demo-snapmon> [--yes] [--paths ordinary,person] [--keep]
//   --yes: 費用の概算を出した後に実行する (無ければ概算だけを出して止まる)
//   --paths: 流す経路をカンマ区切りで絞る (既定は全経路。same_subject は比べる元の ordinary と一緒に流す)
//   --keep: 終わった後に匿名ユーザーを消さない (結果のモンスターを Firestore で確かめる時)
//
// snapmon-prod: Web の API キー (公開値) を環境変数 FIREBASE_WEB_API_KEY か --firebase-options の lib/firebase_options.dart
// (既定はリポジトリの lib/firebase_options.dart。.claude/rules/firebase-config-files.md) から読む。キーは出力しない。
// Functions の App Check の強制を外している間 (functions/src/app_check.ts) だけ通る。
// 実行が残すもの: deleteAccount は本人のデータを消すが、プロジェクト全体の 1 日の生成数 (generationDailyCounts) と、
// その場で作った属性・技の定義 (definitions・definitionCounters) は残る。
//
// demo-snapmon: firebase emulators:start --project demo-snapmon --only auth,firestore,storage,functions で起動した Emulator に送る。
// Emulator の generate は本番と同じ依存 (functions/src/generation/dependencies.ts) で Cloud Vision・Claude・Jev を呼ぶため、
// Application Default Credentials (Vision)・ANTHROPIC_API_KEY (Claude)・functions/.secret.local の TYPESAFE_API_KEY (Jev) が要る。
// どれも無い環境 (CI) では、外部の API をモックにした test/emulator/probe_generation_paths.test.ts が probeGenerationPaths を呼ぶ。
import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { randomUUID } from "node:crypto";

const functionsRoot = path.join(path.dirname(fileURLToPath(import.meta.url)), "..");

/** テスト写真のディレクトリ。 */
export const PHOTOS_FIXTURES_DIRECTORY = path.join(functionsRoot, "test", "fixtures", "photos");

/** Emulator のプロジェクト ID (package.json の test:emulator と同じ)。 */
const EMULATOR_PROJECT_ID = "demo-snapmon";

/** 本番のプロジェクト ID。 */
const PRODUCTION_PROJECT_ID = "snapmon-prod";

/** 写真を置くバケット (functions/src/generation/dependencies.ts の STORAGE_BUCKET_NAME)。 */
const STORAGE_BUCKET_NAME = "snapmon-prod-storage";

/**
 * 1 枚あたりの費用の概算 (ドル)。documents/adr/0002-subject-cutout-and-generation-cost.md「1 体あたりの原価の見積もり」の合計 約 0.03 ドル
 * (Claude が大半で未実測)。人物で Vision の段階で止まる写真は Claude を呼ばないため、概算は上に振れる。
 */
const ESTIMATED_COST_PER_PHOTO_USD = 0.03;

/** Claude Opus 5.5 の 100 万トークンあたりの単価 (ドル)。ADR 0002 の Claude の行 (claude-api skill のモデル表、2026-10-06 時点)。 */
const CLAUDE_PRICE_PER_MILLION_TOKENS_USD = { input: 4, output: 20 };

/** Jev (jev-1.13.0) の 10 億入力トークンあたりの単価 (ドル)。ADR 0002 の Jev の行 ( https://docs.typesafe.ai/models.md )。 */
const JEV_PRICE_PER_BILLION_INPUT_TOKENS_USD = 42;

/**
 * 終了状態を待つ時間。generate の timeoutSeconds (300 秒。functions/src/generation/generate.ts) に、
 * 予約が切れた生成を再試行のタスクが引き継ぐまでの余裕を足した。
 */
const GENERATION_DEADLINE_MILLISECONDS = 8 * 60 * 1000;

/** 生成のレコードを読み直す間隔。1 枚の生成が 15 秒前後 (ADR 0002 の Functions の行) のため、その 1/3 にした。 */
const GENERATION_POLL_INTERVAL_MILLISECONDS = 5_000;

/** 待つのをやめる状態 (終了状態と、1 時間おきの再試行を待つ判定待ち)。 */
const SETTLED_STATUSES = ["saved", "duplicate", "rejected", "failed", "pending_judge"];

/** expectations.json を読む。 */
export function readExpectations(fixturesDirectory = PHOTOS_FIXTURES_DIRECTORY) {
  return JSON.parse(readFileSync(path.join(fixturesDirectory, "expectations.json"), "utf8"));
}

/**
 * 流す写真を、expectations.json の paths の順と、経路の中のファイル名の順に並べて返す。
 * `pathNames` で経路を絞る。絞った経路の duplicateOf が指す写真の経路は、比べる元が無いと判定できないため足す。
 * 返す値: `{ photoName: "<経路>/<ファイル名>", pathExpectation, photoExpectation }` の配列。
 */
export function listProbePhotos({ fixturesDirectory = PHOTOS_FIXTURES_DIRECTORY, expectations, pathNames }) {
  const knownPathNames = expectations.paths.map((pathExpectation) => pathExpectation.path);
  const unknownPathNames = (pathNames ?? []).filter((pathName) => !knownPathNames.includes(pathName));
  if (unknownPathNames.length > 0) {
    throw new Error(`expectations.json に無い経路です: ${unknownPathNames.join(", ")}`);
  }
  const selectedPathNames = new Set(pathNames ?? knownPathNames);
  for (const pathExpectation of expectations.paths.filter((candidate) => selectedPathNames.has(candidate.path))) {
    for (const photoExpectation of Object.values(pathExpectation.photos ?? {})) {
      selectedPathNames.add(photoExpectation.duplicateOf.split("/")[0]);
    }
  }
  return expectations.paths
    .filter((pathExpectation) => selectedPathNames.has(pathExpectation.path))
    .flatMap((pathExpectation) =>
      readdirSync(path.join(fixturesDirectory, pathExpectation.path))
        .filter((fileName) => /\.(jpe?g|png)$/i.test(fileName))
        .sort()
        .map((fileName) => ({ photoName: `${pathExpectation.path}/${fileName}`, pathExpectation, photoExpectation: pathExpectation.photos?.[fileName] ?? {} })),
    );
}

/** 期待を表の 1 列に書く文字列にする。 */
function describeExpectation({ pathExpectation, photoExpectation }) {
  return [
    pathExpectation.expected.status,
    pathExpectation.expected.rejectionReasons ? `(${pathExpectation.expected.rejectionReasons.join(" / ")})` : "",
    photoExpectation.duplicateOf ? `of ${photoExpectation.duplicateOf}` : "",
  ]
    .filter(Boolean)
    .join(" ");
}

/**
 * 1 枚の結果を期待と突き合わせ、合わない理由を返す。合えば undefined。
 * `photoNamesByMonsterId` は、それまでに saved で生まれたモンスターの ID から写真への対応。
 */
export function findMismatch({ pathExpectation, photoExpectation, outcome, photoNamesByMonsterId }) {
  const expected = pathExpectation.expected;
  if (outcome.status !== expected.status) {
    return `status が ${expected.status} ではなく ${outcome.status}`;
  }
  if (expected.rejectionReasons && !expected.rejectionReasons.includes(outcome.rejectionReason)) {
    return `rejectionReason が ${expected.rejectionReasons.join(" / ")} のどれでもなく ${outcome.rejectionReason}`;
  }
  if (photoExpectation.duplicateOf) {
    const duplicatePhotoName = photoNamesByMonsterId.get(outcome.monsterId);
    if (duplicatePhotoName !== photoExpectation.duplicateOf) {
      return `同じ被写体と判定した相手が ${photoExpectation.duplicateOf} ではなく ${duplicatePhotoName ?? `不明なモンスター ${outcome.monsterId}`}`;
    }
  }
  return undefined;
}

/**
 * 写真を順に `generatePhoto` に渡し、結果と判定の行を返す。
 * `generatePhoto({ photoName, photo })` は 1 枚を生成して待つ関数で、
 * `{ status, rejectionReason?, monsterId?, monsterName?, elementTypeIds?, claudeUsages?, jevInputTokens?, failureMessage? }` を返す。
 * 同じ被写体の判定のため、すべての写真を同じユーザーで生成する関数を渡す。`onRow` は 1 枚が終わるたびに呼ぶ。
 */
export async function probeGenerationPaths({ fixturesDirectory = PHOTOS_FIXTURES_DIRECTORY, expectations, pathNames, generatePhoto, onRow = () => {} }) {
  const photoNamesByMonsterId = new Map();
  const rows = [];
  for (const { photoName, pathExpectation, photoExpectation } of listProbePhotos({ fixturesDirectory, expectations, pathNames })) {
    const outcome = await generatePhoto({ photoName, photo: readFileSync(path.join(fixturesDirectory, photoName)) });
    if (outcome.status === "saved" && outcome.monsterId) {
      photoNamesByMonsterId.set(outcome.monsterId, photoName);
    }
    const mismatch = findMismatch({ pathExpectation, photoExpectation, outcome, photoNamesByMonsterId });
    const row = {
      photoName,
      expected: describeExpectation({ pathExpectation, photoExpectation }),
      ...outcome,
      duplicateOfPhotoName: outcome.status === "duplicate" ? photoNamesByMonsterId.get(outcome.monsterId) : undefined,
      verdict: mismatch ? "FAIL" : "PASS",
      mismatch,
    };
    rows.push(row);
    onRow(row);
  }
  return rows;
}

/** 行の Claude と Jev の費用 (ドル)。使用量が無い (Vision で止まった) 行は 0。 */
export function rowCostUsd(row) {
  const claude = (row.claudeUsages ?? []).reduce(
    (sum, usage) => sum + (usage.inputTokens * CLAUDE_PRICE_PER_MILLION_TOKENS_USD.input + usage.outputTokens * CLAUDE_PRICE_PER_MILLION_TOKENS_USD.output) / 1_000_000,
    0,
  );
  return claude + ((row.jevInputTokens ?? 0) * JEV_PRICE_PER_BILLION_INPUT_TOKENS_USD) / 1_000_000_000;
}

/** 結果の行を markdown の表にする (PR と issue のコメントに貼る形)。 */
export function formatResultTable(rows) {
  const tableRow = (cells) => `| ${cells.map((value) => String(value ?? "").replaceAll("|", "\\|").replaceAll("\n", " ")).join(" | ")} |`;
  return [
    "| 写真 | 期待 | 結果 | 判定 | 名前 | 属性 | 同じ被写体の相手 | Claude 入力 / 出力 | Jev 入力 | 費用 (ドル) |",
    "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ...rows.map((row) =>
      tableRow([
        row.photoName,
        row.expected,
        [row.status, row.rejectionReason, row.failureMessage].filter(Boolean).join(" "),
        row.mismatch ? `FAIL: ${row.mismatch}` : "PASS",
        row.monsterName,
        (row.elementTypeIds ?? []).join(", "),
        row.duplicateOfPhotoName,
        row.claudeUsages?.length ? row.claudeUsages.map((usage) => `${usage.inputTokens} / ${usage.outputTokens}`).join(", ") : "",
        row.jevInputTokens ?? "",
        rowCostUsd(row).toFixed(4),
      ]),
    ),
    "",
    `PASS ${rows.filter((row) => row.verdict === "PASS").length} / FAIL ${rows.filter((row) => row.verdict === "FAIL").length}。` +
      `Claude 入力 ${rows.flatMap((row) => row.claudeUsages ?? []).reduce((sum, usage) => sum + usage.inputTokens, 0)} / 出力 ${rows.flatMap((row) => row.claudeUsages ?? []).reduce((sum, usage) => sum + usage.outputTokens, 0)} トークン、Jev 入力 ${rows.reduce((sum, row) => sum + (row.jevInputTokens ?? 0), 0)} トークン、` +
      `費用 ${rows.reduce((sum, row) => sum + rowCostUsd(row), 0).toFixed(4)} ドル (Claude Opus 5.5 は入力 ${CLAUDE_PRICE_PER_MILLION_TOKENS_USD.input}・出力 ${CLAUDE_PRICE_PER_MILLION_TOKENS_USD.output} ドル / 100 万トークン、Jev は ${JEV_PRICE_PER_BILLION_INPUT_TOKENS_USD} ドル / 10 億トークンで計算)`,
  ].join("\n");
}

/** プロジェクトの各サービスの URL。Emulator のポートは firebase.json の emulators。 */
function serviceEndpoints(projectId) {
  if (projectId === EMULATOR_PROJECT_ID) {
    return {
      identityToolkit: "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1",
      storage: `http://127.0.0.1:9199/v0/b/${STORAGE_BUCKET_NAME}/o`,
      functions: `http://127.0.0.1:5001/${projectId}/asia-northeast1`,
      firestore: `http://127.0.0.1:8080/v1/projects/${projectId}/databases/(default)/documents`,
    };
  }
  return {
    identityToolkit: "https://identitytoolkit.googleapis.com/v1",
    storage: `https://firebasestorage.googleapis.com/v0/b/${STORAGE_BUCKET_NAME}/o`,
    functions: `https://asia-northeast1-${projectId}.cloudfunctions.net`,
    firestore: `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents`,
  };
}

/** lib/firebase_options.dart の Web の apiKey を読む (tmp/probe-generate-e2e.sh と同じ読み方)。 */
function readWebApiKey(firebaseOptionsPath) {
  const source = readFileSync(firebaseOptionsPath, "utf8");
  const webBlock = source.slice(source.indexOf("static const FirebaseOptions web"));
  const apiKey = webBlock.slice(0, webBlock.indexOf(");")).match(/apiKey: '([^']+)'/)?.[1];
  if (!apiKey) {
    throw new Error(`${firebaseOptionsPath} に Web の apiKey がありません`);
  }
  return apiKey;
}

/** Firestore の REST の値を JavaScript の値にする。 */
function decodeFirestoreValue(value) {
  if ("mapValue" in value) {
    return Object.fromEntries(Object.entries(value.mapValue.fields ?? {}).map(([key, item]) => [key, decodeFirestoreValue(item)]));
  }
  if ("arrayValue" in value) {
    return (value.arrayValue.values ?? []).map(decodeFirestoreValue);
  }
  if ("integerValue" in value) {
    return Number(value.integerValue);
  }
  if ("nullValue" in value) {
    return null;
  }
  return value.stringValue ?? value.doubleValue ?? value.booleanValue ?? value.timestampValue ?? value.referenceValue;
}

/**
 * 匿名ユーザーで写真を生成する `generatePhoto` と、後始末の `deleteUser` を作る。
 * 返す値の `uid` は、作った匿名ユーザーの uid。
 */
async function createHttpGenerationSession({ projectId, apiKey }) {
  const endpoints = serviceEndpoints(projectId);
  const signUpResponse = await fetch(`${endpoints.identityToolkit}/accounts:signUp?key=${apiKey}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ returnSecureToken: true }),
  });
  const signUp = await signUpResponse.json();
  if (!signUpResponse.ok) {
    throw new Error(`匿名ログインに失敗しました: ${JSON.stringify(signUp.error ?? signUp)}`);
  }
  const uid = signUp.localId;
  let idToken = signUp.idToken;
  let refreshToken = signUp.refreshToken;
  // ID トークンは 1 時間で切れるため、1 枚ごとに更新する (全経路で 1 時間を超えうるため)
  const refreshIdToken = async () => {
    const response = await fetch(
      projectId === EMULATOR_PROJECT_ID ? `http://127.0.0.1:9099/securetoken.googleapis.com/v1/token?key=${apiKey}` : `https://securetoken.googleapis.com/v1/token?key=${apiKey}`,
      { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }) },
    );
    const refreshed = await response.json();
    if (!response.ok) {
      throw new Error(`ID トークンの更新に失敗しました: ${JSON.stringify(refreshed.error ?? refreshed)}`);
    }
    idToken = refreshed.id_token;
    refreshToken = refreshed.refresh_token;
  };
  const readDocument = async (documentPath) => {
    const response = await fetch(`${endpoints.firestore}/${documentPath}`, { headers: { Authorization: `Bearer ${idToken}` } });
    if (response.status === 404) {
      return undefined;
    }
    if (!response.ok) {
      throw new Error(`${documentPath} を読めませんでした: HTTP ${response.status} ${await response.text()}`);
    }
    return decodeFirestoreValue({ mapValue: { fields: (await response.json()).fields } });
  };
  const callFunction = async ({ name, data }) => {
    const response = await fetch(`${endpoints.functions}/${name}`, {
      method: "POST",
      headers: { Authorization: `Bearer ${idToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ data }),
    });
    const body = await response.json();
    if (body.error) {
      return { error: body.error };
    }
    return { result: body.result };
  };

  const generatePhoto = async ({ photo, photoName }) => {
    await refreshIdToken();
    const requestId = randomUUID();
    const photoPath = `users/${uid}/photos/${requestId}`;
    const uploadResponse = await fetch(`${endpoints.storage}?name=${encodeURIComponent(photoPath)}&uploadType=media`, {
      method: "POST",
      headers: { Authorization: `Firebase ${idToken}`, "Content-Type": /\.png$/i.test(photoName) ? "image/png" : "image/jpeg" },
      body: photo,
    });
    if (!uploadResponse.ok) {
      return { status: "upload_error", failureMessage: `HTTP ${uploadResponse.status} ${await uploadResponse.text()}` };
    }
    const deadline = Date.now() + GENERATION_DEADLINE_MILLISECONDS;
    // 応答を待つ間に接続が切れても (fetch の既定のヘッダー待ちは 300 秒で、generate の上限と同じ)、生成はサーバーで続くため、レコードを読みに行く
    const called = await callFunction({ name: "generate", data: { requestId, photoPath } }).catch((error) => ({ connectionError: error }));
    if (called.error) {
      return { status: `error:${called.error.status}`, failureMessage: [called.error.message, called.error.details?.reason].filter(Boolean).join(" ") };
    }
    let record = await readDocument(`users/${uid}/generations/${requestId}`);
    while (!SETTLED_STATUSES.includes(record?.status) && Date.now() < deadline) {
      await new Promise((resolve) => setTimeout(resolve, GENERATION_POLL_INTERVAL_MILLISECONDS));
      record = await readDocument(`users/${uid}/generations/${requestId}`);
    }
    if (!record) {
      return { status: "no_record", failureMessage: called.connectionError ? String(called.connectionError) : "生成のレコードがありません" };
    }
    const monster = record.status === "saved" || record.status === "duplicate" ? await readDocument(`users/${uid}/monsters/${record.monsterId}`) : undefined;
    return {
      status: record.status,
      rejectionReason: record.rejectionReason,
      monsterId: record.monsterId,
      monsterName: monster?.definition?.name,
      elementTypeIds: monster?.definition?.elementTypeIds,
      claudeUsages: record.claudeUsages,
      jevInputTokens: record.jevInputTokens,
      failureMessage: record.failureMessage,
    };
  };

  const deleteUser = async () => {
    await refreshIdToken();
    const deleted = await callFunction({ name: "deleteAccount", data: {} });
    if (deleted.error) {
      throw new Error(`deleteAccount に失敗しました: ${JSON.stringify(deleted.error)}`);
    }
  };

  return { uid, generatePhoto, deleteUser };
}

async function main() {
  const { values } = parseArgs({
    options: {
      project: { type: "string" },
      yes: { type: "boolean", default: false },
      paths: { type: "string" },
      keep: { type: "boolean", default: false },
      "firebase-options": { type: "string", default: path.join(functionsRoot, "..", "lib", "firebase_options.dart") },
    },
  });
  if (values.project !== PRODUCTION_PROJECT_ID && values.project !== EMULATOR_PROJECT_ID) {
    console.error(`Usage: node scripts/probe-generation-paths.mjs --project <${PRODUCTION_PROJECT_ID} | ${EMULATOR_PROJECT_ID}> [--yes] [--paths <経路,...>] [--keep]`);
    process.exit(2);
  }
  const expectations = readExpectations();
  const photos = listProbePhotos({ expectations, pathNames: values.paths?.split(",") });
  console.log(
    `${values.project} に ${photos.length} 枚を送ります (${[...new Set(photos.map((photo) => photo.photoName.split("/")[0]))].join(", ")})。` +
      `費用の概算は ${(photos.length * ESTIMATED_COST_PER_PHOTO_USD).toFixed(2)} ドル (1 枚 ${ESTIMATED_COST_PER_PHOTO_USD} ドル。ADR 0002)。`,
  );
  if (!values.yes) {
    console.log("--yes を付けると実行します。");
    process.exit(2);
  }
  const apiKey = values.project === EMULATOR_PROJECT_ID ? "demo-api-key" : (process.env.FIREBASE_WEB_API_KEY || readWebApiKey(values["firebase-options"]));
  const session = await createHttpGenerationSession({ projectId: values.project, apiKey });
  console.log(`匿名ユーザー uid=${session.uid.slice(0, 6)}… で送ります`);
  let rows;
  try {
    rows = await probeGenerationPaths({
      expectations,
      pathNames: values.paths?.split(","),
      generatePhoto: session.generatePhoto,
      onRow: (row) => console.log(`${row.verdict} ${row.photoName}: ${[row.status, row.rejectionReason, row.monsterName, row.mismatch].filter(Boolean).join(" ")}`),
    });
  } finally {
    if (values.keep) {
      console.log(`匿名ユーザー ${session.uid} を残しました`);
    } else {
      await session.deleteUser();
      console.log("匿名ユーザーを deleteAccount で消しました");
    }
  }
  console.log(`\n${formatResultTable(rows)}`);
  process.exit(rows.some((row) => row.verdict === "FAIL") ? 1 : 0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await main();
}
