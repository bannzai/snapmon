#!/usr/bin/env bash
# scripts/metadata_check/check_all_metadata.sh のテスト。一時ディレクトリに locale のメタデータを作り、METADATA_DIR で検査先を差し替えて
# 日本語の文字数の数え方・keywords のバイト数・上限超え・必須ファイルの欠けと空白だけの中身・リポジトリの fastlane/metadata を確かめる。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
check="$repo_root/scripts/metadata_check/check_all_metadata.sh"
failures=0
# 各テストの作業ディレクトリと出力はこの下に作り、成功・失敗・途中終了のどれでも終わる時に消す
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $1"
}

# 引数: 作業ディレクトリ、locale。上限以内の必須ファイルを揃えた locale を作る
prepare_locale() {
  local locale_dir="$1/$2"
  mkdir -p "$locale_dir"
  printf 'snapmon\n' > "$locale_dir/name.txt"
  printf '説明\n' > "$locale_dir/description.txt"
  printf 'モンスター\n' > "$locale_dir/keywords.txt"
  printf 'https://example.com/privacy\n' > "$locale_dir/privacy_url.txt"
  printf 'https://example.com/support\n' > "$locale_dir/support_url.txt"
}

# 引数: 作業ディレクトリ。exit code を返し、出力は <作業ディレクトリ>.stdout に残す
run_check() {
  METADATA_DIR="$1" LC_ALL=C bash "$check" > "$1.stdout" 2>&1
}

test_japanese_counts_characters_not_bytes() {
  local work
  work="$(mktemp -d "$test_root/work.XXXXXX")"
  prepare_locale "$work" ja
  # 30 文字 (UTF-8 で 90 バイト)。バイト数で数えると上限を超える
  printf '%s\n' "$(printf 'あ%.0s' $(seq 1 30))" > "$work/ja/subtitle.txt"
  if ! run_check "$work"; then
    fail "日本語 30 文字の subtitle を上限超えにした ($(cat "$work.stdout"))"
    return
  fi
  pass "日本語は C ロケールから呼んでも文字数で数える"
}

test_japanese_over_limit_fails() {
  local work
  work="$(mktemp -d "$test_root/work.XXXXXX")"
  prepare_locale "$work" ja
  printf '%s\n' "$(printf 'あ%.0s' $(seq 1 31))" > "$work/ja/subtitle.txt"
  if run_check "$work"; then
    fail "日本語 31 文字の subtitle を通した"
    return
  fi
  pass "日本語 31 文字の subtitle は上限超えになる"
}

test_keywords_count_bytes() {
  local work
  work="$(mktemp -d "$test_root/work.XXXXXX")"
  prepare_locale "$work" ja
  # 34 文字 (102 バイト)。文字数では 100 以内だがバイト数で上限を超える
  printf '%s\n' "$(printf 'あ%.0s' $(seq 1 34))" > "$work/ja/keywords.txt"
  if run_check "$work"; then
    fail "102 バイトの keywords を通した"
    return
  fi
  pass "keywords はバイト数で数える"
}

test_newlines_inside_text_are_counted() {
  local work
  work="$(mktemp -d "$test_root/work.XXXXXX")"
  prepare_locale "$work" ja
  # 2000 文字・改行・2000 文字 (4001 文字)。途中の改行を数えないと上限 (4000) 以内に見える
  printf '%s\n%s\n' "$(printf 'あ%.0s' $(seq 1 2000))" "$(printf 'あ%.0s' $(seq 1 2000))" > "$work/ja/description.txt"
  if run_check "$work"; then
    fail "途中に改行のある 4001 文字の description を通した"
    return
  fi
  pass "本文の途中の改行は 1 文字に数える"
}

test_missing_required_file_fails() {
  local work
  work="$(mktemp -d "$test_root/work.XXXXXX")"
  prepare_locale "$work" en-US
  mv "$work/en-US/privacy_url.txt" "$work/privacy_url.txt.bak"
  if run_check "$work"; then
    fail "privacy_url.txt が無いのに通した"
    return
  fi
  if ! grep -q 'privacy_url.txt が無いか中身が空です' "$work.stdout"; then
    fail "privacy_url.txt が無い時のメッセージが出ていない ($(cat "$work.stdout"))"
    return
  fi
  pass "必須のファイルが無ければ失敗する"
}

test_blank_required_file_fails() {
  local work
  work="$(mktemp -d "$test_root/work.XXXXXX")"
  prepare_locale "$work" en-US
  printf '  \n\n' > "$work/en-US/support_url.txt"
  if run_check "$work"; then
    fail "空白と改行だけの support_url.txt を通した"
    return
  fi
  pass "必須のファイルが空白と改行だけなら失敗する"
}

test_repository_metadata_passes() {
  if ! bash "$check" > /dev/null 2>&1; then
    fail "リポジトリの fastlane/metadata が検査を通らない ($(bash "$check" 2>&1 || true))"
    return
  fi
  pass "リポジトリの fastlane/metadata は上限以内"
}

test_japanese_counts_characters_not_bytes
test_japanese_over_limit_fails
test_keywords_count_bytes
test_newlines_inside_text_are_counted
test_missing_required_file_fails
test_blank_required_file_fails
test_repository_metadata_passes

if [ "$failures" -ne 0 ]; then
  echo "$failures 件失敗"
  exit 1
fi
echo "all passed"
