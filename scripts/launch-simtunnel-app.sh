#!/usr/bin/env bash
# simtunnel の simulator で、App Check の debug token を渡して snapmon の debug ビルドを起動する。
#
# simulator のビルドは GitHub Actions の artifact に上がり、公開リポジトリでは誰でも取れるため、token をビルドに埋め込まない。
# 代わりに起動時の環境変数 FIRAAppCheckDebugToken で渡す (firebase_app_check 0.5.1 の iOS のプラグイン
# FirebaseAppCheckPlugin.swift は、Dart から token を受け取った時にこの環境変数へ書いてから debug provider を作る。
# Dart から渡さない時は、起動時に渡したこの環境変数を debug provider が読む)。
#
# 使い方: op run --env-file .env.1password -- bash scripts/launch-simtunnel-app.sh <simtunnel のセッション名>
# 環境変数: FIREBASE_APPCHECK_DEBUG_TOKEN_IOS (必須。発行と登録は scripts/register-appcheck-debug-token.sh)
#           IOS_WDA (既定 ~/.claude/skills/ios-simulator/scripts/ios-wda.sh) — 起動に使うスクリプト
# token は引数に出さず (引数はプロセス一覧から読めるため)、本人だけが読める一時ファイルで渡して終了時に消す。
# 冪等にしない: 実行のたびにアプリを終了して起動し直す。
# exit code: 0 = 起動した、1 = token が無い・アプリの終了か起動に失敗した、2 = 引数の誤り
set -euo pipefail

[ $# -eq 1 ] || {
  echo "使い方: op run --env-file .env.1password -- bash scripts/launch-simtunnel-app.sh <simtunnel のセッション名>" >&2
  exit 2
}
[ -n "${FIREBASE_APPCHECK_DEBUG_TOKEN_IOS:-}" ] || {
  echo "FIREBASE_APPCHECK_DEBUG_TOKEN_IOS がありません (op run --env-file .env.1password -- で実行してください)" >&2
  exit 1
}

umask 077
launch_env_file="$(mktemp)"
trap 'rm -f "$launch_env_file"' EXIT
printf 'FIRAAppCheckDebugToken=%s\n' "$FIREBASE_APPCHECK_DEBUG_TOKEN_IOS" > "$launch_env_file"

# 起動済みのアプリに launch を送っても環境変数は渡らず、匿名ログインが「Firebase App Check token is invalid」で断られる。
# 先に終了してから起動する (2026-11-20 に simtunnel で実測。終了せずに起動した時は断られ、終了してから起動した時は通った)。
# 起動していないアプリの終了は失敗にならない (同じ日の実測: 応答は "value": false で exit 0)。終了が失敗するのは
# 通信の失敗等で、その時はアプリが起動中のまま残り得るため、起動へ進まずに止まる (進むと token が渡らないまま成功に見える)
bash "${IOS_WDA:-$HOME/.claude/skills/ios-simulator/scripts/ios-wda.sh}" --session "$1" terminate com.bannzai.snapmon > /dev/null || {
  echo "アプリを終了できませんでした (起動中のままだと token が渡らないため、起動していません)" >&2
  exit 1
}
bash "${IOS_WDA:-$HOME/.claude/skills/ios-simulator/scripts/ios-wda.sh}" --session "$1" launch com.bannzai.snapmon --env-file "$launch_env_file"
