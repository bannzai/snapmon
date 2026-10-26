#!/usr/bin/env bash
# fastlane/metadata/<locale>/ の App Store のメタデータが App Store Connect の文字数の上限に収まっているかを検査する。
# bannzai/Focus の scripts/metadata_check/ (commit 368eb5137fa3f25921a1cfefeeb7aa1231d03fa0) を写して 1 ファイルにまとめ、
# description・promotional_text の上限、keywords のバイト数、必須のファイルの有無の検査を足した。
#
# 使い方: scripts/metadata_check/check_all_metadata.sh [locale...]   (省略すると全 locale)
# 環境変数 METADATA_DIR で検査するディレクトリを差し替えられる (既定は <リポジトリ>/fastlane/metadata。テストが使う)
# exit code: 0 = すべて上限以内、1 = 上限を超えた・必須のファイルが無い、2 = 引数・ディレクトリの誤り
#
# 上限は App Store Connect の項目の上限で、2026-10-26 に次の 2 ページで確かめた。
# - https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/
#   name「no more than 30 characters」、subtitle「can't be longer than 30 characters」
# - https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/
#   description「Limited to 4000 characters」、keywords「up to 100 bytes」、promotional_text「can't be longer than 170 characters」
# keywords だけは文字数ではなくバイト数 (UTF-8 で日本語 1 文字 = 3 バイト) で数える
set -euo pipefail

# wc -m は C / POSIX のロケールではバイト数を数え、日本語を 3 倍に数えるため UTF-8 のロケールで数える。
# 入っている UTF-8 のロケールは OS で違う (macOS は en_US.UTF-8、Linux の最小構成は C.UTF-8) ため、日本語 1 文字を 1 と数えるものを選ぶ
for utf8_locale in en_US.UTF-8 C.UTF-8; do
  if [[ "$(printf 'あ' | LC_ALL=$utf8_locale wc -m 2>/dev/null | tr -d ' ')" == 1 ]]; then
    export LC_ALL=$utf8_locale
    break
  fi
done
if [[ "$(printf 'あ' | wc -m | tr -d ' ')" != 1 ]]; then
  echo "エラー: 文字数を数えられる UTF-8 のロケールがありません (en_US.UTF-8・C.UTF-8)" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
metadata_dir="${METADATA_DIR:-$script_dir/../../fastlane/metadata}"

if [[ ! -d "$metadata_dir" ]]; then
  echo "エラー: メタデータのディレクトリがありません: $metadata_dir" >&2
  exit 2
fi

# 引数: ファイル、上限、単位 (chars = 文字数、bytes = バイト数)。末尾の改行を除いた長さが上限以内なら 0、超えたら 1 を返す。
# 本文の途中の改行は App Store Connect でも 1 文字に数えるため残し、ファイルの末尾の改行だけを除く ($(<file) が末尾の改行を落とす)
check_length() {
  local file=$1 maximum=$2 unit=$3 count
  if [[ "$unit" == bytes ]]; then
    count=$(printf '%s' "$(<"$file")" | wc -c | tr -d ' ')
  else
    count=$(printf '%s' "$(<"$file")" | wc -m | tr -d ' ')
  fi
  if [[ "$count" -le "$maximum" ]]; then
    echo "OK: $file ($count / $maximum $unit)"
    return 0
  fi
  echo "NG: $file ($count / $maximum $unit) 上限を超えています" >&2
  return 1
}

locales=()
if [[ $# -gt 0 ]]; then
  locales=("$@")
else
  for directory in "$metadata_dir"/*/; do
    locales+=("$(basename "$directory")")
  done
fi

failures=0
for locale in "${locales[@]}"; do
  locale_dir="$metadata_dir/$locale"
  if [[ ! -d "$locale_dir" ]]; then
    echo "エラー: locale のディレクトリがありません: $locale_dir" >&2
    exit 2
  fi
  # name・description・keywords・privacy_url・support_url は App Store Connect の提出に要るため、無ければ失敗にする
  for required in name description keywords privacy_url support_url; do
    # 空白・改行だけのファイルも中身が無いものとして扱う
    if [[ ! -f "$locale_dir/$required.txt" ]] || [[ -z "$(tr -d '[:space:]' < "$locale_dir/$required.txt")" ]]; then
      echo "NG: $locale_dir/$required.txt が無いか中身が空です" >&2
      failures=$((failures + 1))
    fi
  done
  for entry in name:30:chars subtitle:30:chars keywords:100:bytes promotional_text:170:chars description:4000:chars; do
    IFS=: read -r field maximum unit <<< "$entry"
    file="$locale_dir/$field.txt"
    if [[ -f "$file" ]] && ! check_length "$file" "$maximum" "$unit"; then
      failures=$((failures + 1))
    fi
  done
done

if [[ "$failures" -ne 0 ]]; then
  echo "$failures 件の問題があります" >&2
  exit 1
fi
echo "すべて上限以内です"
