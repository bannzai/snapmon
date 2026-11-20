#!/usr/bin/env bash
set -euo pipefail

# Firebase Local Emulator Suite (Auth・Firestore・Functions・Storage) を起動し、master と見本のモンスターを入れてから、
# ビルド済みの Web 版 (build/web) を配信する。本番に出す前の Functions・Rules を、Web 版の画面から通して確かめるために使う
# (例: 人との対戦を 2 人の利用者で最後まで進める)。`.github/workflows/browser-session.yml` の `firebase_emulator` が
# webtunnel の start_command として呼ぶ。手元でも同じ手順で使える。
#
# 前提 (呼ぶ前に済ませる):
#   - `npm ci --prefix functions` と `npm run build --prefix functions` (Functions の Emulator は functions/lib を読む)
#   - `flutter build web --debug --dart-define=FIREBASE_EMULATOR_HOST=127.0.0.1` (lib/firebase/emulator.dart がつなぎ先を Emulator にする)
#   - Java 21 以上 (Firestore・Storage の Emulator の要件。GitHub Actions のランナーは JAVA_HOME_21_X64 にある)
#
# Usage: PORT=<Web 版を配信するポート> bash scripts/start-web-with-firebase-emulators.sh
#   PORT は Emulator のポート (firebase.json の emulators: 9099・8080・9199・5001) と別にする
# 冪等でない: Emulator と見本を入れるスクリプトを常駐させ、Web 版の配信のプロセスに置き換わる (止める時はこのスクリプトのプロセスグループごと止める)。
#   Emulator のデータは保存せず、起動のたびに空から始まる

# Functions の Emulator のテスト (functions/package.json の test:emulator) と、アプリがつなぐプロジェクト (lib/firebase/emulator.dart) と同じ値
EMULATOR_PROJECT_ID="demo-snapmon"
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [ -n "${JAVA_HOME_21_X64:-}" ]; then
  export JAVA_HOME="$JAVA_HOME_21_X64"
  export PATH="$JAVA_HOME/bin:$PATH"
fi

functions/node_modules/.bin/firebase emulators:start --project "$EMULATOR_PROJECT_ID" --only auth,firestore,storage,functions &

# 4 つの Emulator のポートが応答するまで待つ (HTTP のステータスは問わない)。
# 120 秒: ランナーで Emulator の jar の取得と Functions の読み込みにかかった時間 (30〜60 秒) の 2 倍
for port in 9099 8080 9199 5001; do
  for attempt in $(seq 1 120); do
    if curl -s -o /dev/null -m 2 "http://127.0.0.1:${port}/"; then
      break
    fi
    if [ "$attempt" = 120 ]; then
      echo "Emulator のポート ${port} が 120 秒待っても応答しない" >&2
      exit 1
    fi
    sleep 1
  done
done

export FIRESTORE_EMULATOR_HOST="127.0.0.1:8080"
export FIREBASE_AUTH_EMULATOR_HOST="127.0.0.1:9099"
node functions/scripts/seed-master.mjs \
  --project "$EMULATOR_PROJECT_ID" \
  --version "$(node -p "require('./assets/master/master.json').version")" \
  --file assets/master/master.json
node functions/scripts/seed-emulator-players.mjs --project "$EMULATOR_PROJECT_ID" --samples assets/samples/sample_monsters.json &

exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory build/web
