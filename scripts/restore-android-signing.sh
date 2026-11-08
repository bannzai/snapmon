#!/usr/bin/env bash
# CI で Google Play 向けの AAB をビルドする前に、Android の upload key を GitHub Secrets から書き出す (build-android-release.yml)。
#
# 入力 (環境変数。どちらもファイルを base64 にした 1 行の値。1Password の vault snapmon が正):
#   ANDROID_KEYSTORE_JKS_BASE64    -> android/app/upload-keystore.jks
#   ANDROID_KEY_PROPERTIES_BASE64  -> android/key.properties (storeFile は android/app からの相対パス upload-keystore.jks)
# exit code: 0 = 書き出した、1 = Secret が未登録・base64 として読めない・keystore が小さすぎる (Secrets の配信の不具合で壊れた JKS は
#   署名の段階で分かりにくく失敗するため、ここでサイズで止める)。
# 同じ値で何度実行しても同じファイルになる (冪等)。どちらのファイルも .gitignore 済みで、値は出力しない。
set -euo pipefail

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
  echo "${output_path} を書き出しました ($(wc -c < "$output_path" | tr -d ' ') bytes)"
}

restore ANDROID_KEYSTORE_JKS_BASE64 android/app/upload-keystore.jks
restore ANDROID_KEY_PROPERTIES_BASE64 android/key.properties

jks_size=$(wc -c < android/app/upload-keystore.jks | tr -d ' ')
if [ "$jks_size" -lt 1000 ]; then
  echo "::error::android/app/upload-keystore.jks が ${jks_size} bytes しかありません。Secret の値が壊れています"
  exit 1
fi
