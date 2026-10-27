#!/usr/bin/env bash
# webtunnel (.github/workflows/browser-session.yml) の setup_command に渡す GitHub Secret WEBTUNNEL_SETUP_ENV を登録する。
#
# 値は次の KEY=VALUE の行を base64 にしたもの (webtunnel が復号して環境変数にし、setup_command が読む)。
#   FIREBASE_OPTIONS_DART_B64=<lib/firebase_options.dart の base64>  (restore-firebase-config.sh が読む。必須)
#   FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=<App Check の Web の debug token>  (環境変数 FIREBASE_APPCHECK_DEBUG_TOKEN_WEB が
#     ある時だけ足す。debug ビルドの flutter build web の --dart-define に渡り、lib/firebase/session.dart が
#     reCAPTCHA Enterprise の代わりに debug provider に使う。自動操作の Chromium は reCAPTCHA のスコアが低く証明が通らないため)
# GitHub Secrets は値を読み出せないため、Secret FIREBASE_OPTIONS_DART_B64 の元と同じ手元の lib/firebase_options.dart から作る。
# 値は画面に出さず、gh secret set の標準入力にだけ流す。同じ入力から何度実行しても同じ値になる (冪等)。
#
# debug token の正は 1Password (vault snapmon、item FIREBASE_APPCHECK_DEBUG_TOKEN_WEB。参照は .env.1password)。
# 発行し直す時 (Firebase の App Check の Web アプリへの登録は Firebase App Check API。値は画面に出さない):
#   export FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=$(uuidgen | tr 'A-Z' 'a-z')
#   python3 ~/.agents/skills/env-secret-registry/scripts/op-item-template-from-env.py FIREBASE_APPCHECK_DEBUG_TOKEN_WEB FIREBASE_APPCHECK_DEBUG_TOKEN_WEB \
#     | op item create --vault snapmon - > /dev/null          # 既にあれば op item edit で password を更新する
#   printf '{"displayName":"webtunnel","token":"%s"}' "$FIREBASE_APPCHECK_DEBUG_TOKEN_WEB" \
#     | curl -s -X POST -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "x-goog-user-project: snapmon-prod" \
#       -H 'Content-Type: application/json' --data-binary @- \
#       "https://firebaseappcheck.googleapis.com/v1beta/projects/snapmon-prod/apps/<Web アプリの appId>/debugTokens"
#   (token は curl の引数に展開せず標準入力で渡す。引数はプロセス一覧から読めるため。printf は shell の組み込みで引数が外に出ない)
#   bash scripts/set-webtunnel-setup-env-secret.sh
# 1Password にある token を使って登録し直すだけなら: op run --env-file .env.1password -- bash scripts/set-webtunnel-setup-env-secret.sh
#
# 環境変数: SNAPMON_REPO (既定 bannzai/snapmon) — 登録先のリポジトリ
#           FIREBASE_APPCHECK_DEBUG_TOKEN_WEB — 上の debug token (任意。無ければ FIREBASE_OPTIONS_DART_B64 の行だけ登録する)
# exit code: 0 = 登録した、1 = lib/firebase_options.dart が無い・空、値を作れなかった、または gh secret set の失敗。
set -euo pipefail

cd "$(dirname "$0")/.."

repo="${SNAPMON_REPO:-bannzai/snapmon}"
source_path=lib/firebase_options.dart

if [ ! -s "$source_path" ]; then
  echo "${source_path} が無いか空です。flutterfire configure で生成してから実行してください (.claude/rules/firebase-config-files.md)" >&2
  exit 1
fi

# webtunnel は復号した値を 1 行 1 組の KEY=VALUE として読むため、どちらの base64 も改行を除いて 1 行にする
dart_b64="$(base64 < "$source_path" | tr -d '\n')"
env_lines="$(printf 'FIREBASE_OPTIONS_DART_B64=%s\n' "$dart_b64")"
if [ -n "${FIREBASE_APPCHECK_DEBUG_TOKEN_WEB:-}" ]; then
  env_lines="$(printf '%s\nFIREBASE_APPCHECK_DEBUG_TOKEN_WEB=%s\n' "$env_lines" "$FIREBASE_APPCHECK_DEBUG_TOKEN_WEB")"
fi
setup_env="$(printf '%s\n' "$env_lines" | base64 | tr -d '\n')"

# 空の値で登録すると既存の Secret を空で上書きしてしまうため、書き込みの直前に止める
[ -n "$dart_b64" ] && [ -n "$setup_env" ] || {
  echo "WEBTUNNEL_SETUP_ENV の値を作れませんでした" >&2
  exit 1
}

printf '%s' "$setup_env" | gh secret set WEBTUNNEL_SETUP_ENV --repo "$repo"
