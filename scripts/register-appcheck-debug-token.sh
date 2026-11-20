#!/usr/bin/env bash
# iOS・Android の debug ビルドが App Check を通るための debug token を、1Password と Firebase の App Check に登録する。
#
# debug ビルドは lib/firebase/session.dart が debug provider を使い、--dart-define で渡された token を送る
# (iOS: FIREBASE_APPCHECK_DEBUG_TOKEN_IOS、Android: FIREBASE_APPCHECK_DEBUG_TOKEN_ANDROID)。App Check を強制しているため、
# Firebase のアプリに登録済みの token を送らない debug ビルドは匿名ログインも Functions の呼び出しも断られる。
#
# 使い方:
#   初めて発行する:        bash scripts/register-appcheck-debug-token.sh <ios|android>
#   1Password にある token を Firebase に登録し直す (アプリを作り直した時等):
#                          op run --env-file .env.1password -- bash scripts/register-appcheck-debug-token.sh <ios|android>
# 行うこと:
#   1. 環境変数 FIREBASE_APPCHECK_DEBUG_TOKEN_<IOS|ANDROID> が無ければ、UUID で token を作り、1Password (vault snapmon、
#      item は環境変数と同じ名前) に置く。item が既にあれば作らずに止まる (1Password が正のため。上の op run の形で実行する)
#   2. Firebase の App Check の、そのプラットフォームのアプリに token を登録する (同じ token が登録済みなら何もしない)
# GitHub Actions (simtunnel の .github/workflows/simulator-session.yml が読む Secret FIREBASE_APPCHECK_DEBUG_TOKEN_IOS) へは、
# このスクリプトではなく onepassword-sync skill が .env.1password.github-actions の宣言から写す。
# token は画面にも引数にも出さない (curl・op には標準入力で渡す。引数はプロセス一覧から読めるため)。
# 冪等にしない: 環境変数なしの実行は token を新しく作る (2 回目は item があるため 1 で止まり、何も変えない)。
#
# 前提: op (1Password CLI) にサインイン済み、gcloud が snapmon-prod の App Check を編集できるアカウントで認証済み。
# exit code: 0 = 登録した (登録済みを含む)、1 = 前提が足りない・登録に失敗した、2 = 引数の誤り
set -euo pipefail

cd "$(dirname "$0")/.."

case "${1:-}" in
  ios) name=FIREBASE_APPCHECK_DEBUG_TOKEN_IOS ;;
  android) name=FIREBASE_APPCHECK_DEBUG_TOKEN_ANDROID ;;
  *)
    echo "使い方: bash scripts/register-appcheck-debug-token.sh <ios|android>" >&2
    exit 2
    ;;
esac

# アプリの ID は firebase.json (flutterfire configure が書く) が正
app_id="$(jq -r --arg platform "$1" '.flutter.platforms[$platform].default.appId // empty' firebase.json)"
[ -n "$app_id" ] || {
  echo "firebase.json から $1 のアプリの ID を読めません" >&2
  exit 1
}

token="${!name:-}"
if [ -z "$token" ]; then
  # 認可切れを「item が無い」と読み違えて作り直さないよう、先に vault を読めることを確かめる
  op vault get snapmon > /dev/null || {
    echo "1Password の vault snapmon を読めません (app で認可してから実行し直してください)" >&2
    exit 1
  }
  if op item get "$name" --vault snapmon --format json --fields label=title > /dev/null 2>&1; then
    echo "1Password に ${name} が既にあります。op run --env-file .env.1password -- で実行してください" >&2
    exit 1
  fi
  token="$(uuidgen | tr 'A-Z' 'a-z')"
  [ -n "$token" ] || {
    echo "token を作れませんでした" >&2
    exit 1
  }
  jq -n --arg name "$name" --arg token "$token" \
    '{title: $name, category: "PASSWORD", fields: [{id: "password", type: "CONCEALED", purpose: "PASSWORD", value: $token}]}' \
    | op item create --vault snapmon - > /dev/null
  echo "1Password に ${name} を作りました"
fi

# 同じ token の登録は 409 (ALREADY_EXISTS) が返るため、登録済みとして扱う
status="$(jq -n --arg token "$token" '{displayName: "debug-build", token: $token}' \
  | curl -sS -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" -H "x-goog-user-project: snapmon-prod" \
    -H 'Content-Type: application/json' --data-binary @- \
    "https://firebaseappcheck.googleapis.com/v1/projects/snapmon-prod/apps/${app_id}/debugTokens")"
case "$status" in
  200) echo "App Check の $1 のアプリに debug token を登録しました" ;;
  409) echo "App Check の $1 のアプリには同じ debug token が登録済みです" ;;
  *)
    echo "App Check への登録に失敗しました (HTTP ${status})" >&2
    exit 1
    ;;
esac
