#!/usr/bin/env bash
# webtunnel (.github/workflows/browser-session.yml) の setup_command に渡す GitHub Secret WEBTUNNEL_SETUP_ENV を登録する。
#
# 値は `FIREBASE_OPTIONS_DART_B64=<lib/firebase_options.dart の base64>` の 1 行を、さらに base64 にしたもの
# (webtunnel が復号して KEY=VALUE を環境変数にし、setup_command の restore-firebase-config.sh が読む)。
# GitHub Secrets は値を読み出せないため、Secret FIREBASE_OPTIONS_DART_B64 の元と同じ手元の lib/firebase_options.dart から作る。
# 値は画面に出さず、gh secret set の標準入力にだけ流す。同じファイルから何度実行しても同じ値になる (冪等)。
#
# 環境変数: SNAPMON_REPO (既定 bannzai/snapmon) — 登録先のリポジトリ
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
setup_env="$(printf 'FIREBASE_OPTIONS_DART_B64=%s\n' "$dart_b64" | base64 | tr -d '\n')"

# 空の値で登録すると既存の Secret を空で上書きしてしまうため、書き込みの直前に止める
[ -n "$dart_b64" ] && [ -n "$setup_env" ] || {
  echo "WEBTUNNEL_SETUP_ENV の値を作れませんでした" >&2
  exit 1
}

printf '%s' "$setup_env" | gh secret set WEBTUNNEL_SETUP_ENV --repo "$repo"
