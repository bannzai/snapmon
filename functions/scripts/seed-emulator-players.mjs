// Emulator に匿名ログインした利用者へ、見本のモンスターを図鑑と手持ちに入れ続ける (動作確認用。本番には使わない)。
// アプリの画面から Emulator の Functions を通して確かめる時 (例: 人との対戦を 2 人の利用者で進める) に、
// 写真からの生成 (Claude API と画像の処理が要る) を通さずに、対戦に出られる利用者を用意する。
// scripts/start-web-with-firebase-emulators.sh が Emulator の起動の後に常駐させる。
//
// 使い方: FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//   node scripts/seed-emulator-players.mjs --project demo-snapmon --samples <見本データの JSON>
//
// Auth の Emulator の利用者を 1 秒ごとに読み、`users/{uid}` がまだ無い利用者に見本のモンスター 3 体を入れる。
// 利用者ごとに違う 3 体を選ぶ (ログインした順に見本の並びを 3 体ずつ進める) ため、2 人の対戦で同じ絵が向かい合わない。
// `users/{uid}` がある利用者には何もしない (冪等)。2 つの環境変数が無い時は、本番に書かないよう何もせずに終える。
import { readFileSync } from "node:fs";
import { setTimeout as sleep } from "node:timers/promises";
import { parseArgs } from "node:util";

import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { Timestamp, getFirestore } from "firebase-admin/firestore";

const { values } = parseArgs({
  options: {
    project: { type: "string" },
    samples: { type: "string" },
  },
});
if (!values.project || !values.samples) {
  console.error("Usage: node scripts/seed-emulator-players.mjs --project <Emulator のプロジェクト ID> --samples <見本データの JSON>");
  process.exit(2);
}
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error("FIRESTORE_EMULATOR_HOST と FIREBASE_AUTH_EMULATOR_HOST を設定してください (Emulator にだけ書くスクリプトです)");
  process.exit(2);
}

// 手持ちの上限 (functions/src/battle_rules.ts の MAXIMUM_PARTY_SIZE) と同じ数を入れ、交代を含む対戦を確かめられるようにする
const monstersPerPlayer = 3;
const sampleMonsters = JSON.parse(readFileSync(values.samples, "utf8")).monsters;
initializeApp({ projectId: values.project });
const firestore = getFirestore();

/** これまでに見本のモンスターを入れた利用者の数。利用者ごとに違うモンスターを選ぶのに使う。 */
let seededPlayerCount = 0;

/**
 * uid が [uid] の利用者の図鑑と手持ちに、見本のモンスター [monstersPerPlayer] 体を入れる。
 * モンスターの ID は見本の ID に uid の先頭を足して利用者ごとに分ける (通報の記録 `reportedMonsters/{monsterID}` が ID で 1 件のため)。
 * 項目の形は functions/src/generation/records.ts の MonsterDocument。絵はアプリに同梱の見本の絵のパスをそのまま使う。
 */
async function seedPlayer({ uid }) {
  const batch = firestore.batch();
  const monsterIDs = [];
  for (let index = 0; index < monstersPerPlayer; index++) {
    const sampleMonster = sampleMonsters[(seededPlayerCount * monstersPerPlayer + index) % sampleMonsters.length];
    const monsterID = `${sampleMonster.definition.id}-${uid.slice(0, 8)}`;
    monsterIDs.push(monsterID);
    batch.set(firestore.doc(`users/${uid}/monsters/${monsterID}`), {
      definition: { ...sampleMonster.definition, id: monsterID },
      level: sampleMonster.level,
      experience: 0,
      artPath: sampleMonster.artPath,
      // 見本のモンスターは装飾を持たない。アプリは読めない版の装飾を無いものとして扱う (lib/features/dex/owned_monster.dart)
      decoration: {},
      decorationVersion: 0,
      subjectDescription: {},
      categoryIDs: [],
      definitionIDs: [],
      generationRequestID: `seed-${monsterID}`,
      // 図鑑は createdAt の順に並ぶため、入れた順になるよう 1 ミリ秒ずつずらす
      createdAt: Timestamp.fromMillis(Date.now() + index),
    });
  }
  batch.set(firestore.doc(`users/${uid}/party/current`), { monsterIDs, updatedAt: Timestamp.now() });
  // 生成を 1 回終えた利用者と同じ形 (functions/test/emulator/pvp_battle.test.ts の signInTrainer)
  batch.set(firestore.doc(`users/${uid}`), { dailyGeneration: { date: "2000-01-01", count: 1 } });
  await batch.commit();
  seededPlayerCount += 1;
  console.log(`[SEED] users/${uid}: ${monsterIDs.join(", ")}`);
}

console.log(`Emulator の利用者を待っています (project ${values.project})`);
for (;;) {
  try {
    for (const user of (await getAuth().listUsers(1000)).users) {
      if (!(await firestore.doc(`users/${user.uid}`).get()).exists) {
        await seedPlayer({ uid: user.uid });
      }
    }
  } catch (error) {
    // Emulator の起動の途中・再起動の間は読めないため、止めずに次の周期でやり直す
    console.error(error);
  }
  await sleep(1000);
}
