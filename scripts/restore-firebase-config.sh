#!/usr/bin/env bash
# CI で Flutter をビルドする前に、git の管理から外した Firebase の設定ファイルを GitHub Secrets から書き出す。
#
# 入力 (環境変数。どれも各ファイルを base64 にした 1 行の値):
#   FIREBASE_OPTIONS_DART_B64     -> lib/firebase_options.dart
#   GOOGLE_SERVICE_INFO_PLIST_B64 -> ios/Runner/GoogleService-Info.plist
#   GOOGLE_SERVICES_JSON_B64      -> android/app/google-services.json
# 引数: 書き出すファイルの種類 (dart / ios / android) を 1 つ以上。ビルドしないプラットフォームの Secret を要求しないため。
# exit code: 0 = 書き出した、1 = 指定した種類の Secret が未登録・base64 として読めない、2 = 引数の誤り。
# 同じ値で何度実行しても同じファイルになる (冪等)。手元では flutterfire configure で生成する (.claude/rules/firebase-config-files.md)。
set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "Usage: $0 <dart|ios|android>..." >&2
  exit 2
fi

cd "$(dirname "$0")/.."

restore() {
  local secret_name="$1" output_path="$2"
  local encoded="${!secret_name:-}"
  if [ -z "$encoded" ]; then
    echo "::error::Secret ${secret_name} が未登録のため ${output_path} を書き出せません"
    exit 1
  fi
  if ! printf '%s' "$encoded" | base64 --decode > "$output_path"; then
    echo "::error::Secret ${secret_name} を base64 として読めません"
    exit 1
  fi
  echo "${output_path} を書き出しました"
}

for kind in "$@"; do
  case "$kind" in
    dart) restore FIREBASE_OPTIONS_DART_B64 lib/firebase_options.dart ;;
    ios) restore GOOGLE_SERVICE_INFO_PLIST_B64 ios/Runner/GoogleService-Info.plist ;;
    android) restore GOOGLE_SERVICES_JSON_B64 android/app/google-services.json ;;
    *)
      echo "不明な種類: ${kind} (dart / ios / android のどれか)" >&2
      exit 2
      ;;
  esac
done
