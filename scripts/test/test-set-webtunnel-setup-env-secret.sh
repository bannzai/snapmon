#!/usr/bin/env bash
# scripts/set-webtunnel-setup-env-secret.sh のテスト。gh を差し替えて登録される値を受け取り、
# webtunnel と同じ読み方 (base64 を復号し、行を最初の `=` で KEY と VALUE に分ける) をした後に
# restore-firebase-config.sh で元の lib/firebase_options.dart に戻ることを確かめる。
# 一時ディレクトリにリポジトリの scripts/ を写して実行し、手元の lib/ には触れない。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $1"
}

# 引数: 作業ディレクトリ。scripts/ と、標準入力を $GH_STDIN_FILE・引数を $GH_ARGS_FILE に書く gh の差し替えを置く
prepare_workspace() {
  local work=$1
  mkdir -p "$work/scripts" "$work/lib" "$work/bin"
  cp "$repo_root/scripts/set-webtunnel-setup-env-secret.sh" "$repo_root/scripts/restore-firebase-config.sh" "$work/scripts/"
  cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$GH_ARGS_FILE"
cat > "$GH_STDIN_FILE"
EOF
  chmod +x "$work/bin/gh"
}

# 76 桁を超える base64 になる大きさで、改行・`=`・非 ASCII を含む中身にする
fixture_content() {
  printf "// fake firebase_options.dart\nconst apiKey = 'not-a-real-key=abc';\n"
  for i in $(seq 1 40); do
    printf "const line%s = 'テスト %s';\n" "$i" "$i"
  done
}

test_round_trip() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  fixture_content > "$work/lib/firebase_options.dart"
  cp "$work/lib/firebase_options.dart" "$work/expected.dart"

  if ! PATH="$work/bin:$PATH" GH_ARGS_FILE="$work/gh-args" GH_STDIN_FILE="$work/gh-stdin" \
    bash "$work/scripts/set-webtunnel-setup-env-secret.sh" > "$work/stdout" 2>&1; then
    fail "round trip: スクリプトが失敗した ($(cat "$work/stdout"))"
    return
  fi

  if [ "$(cat "$work/gh-args")" != "secret set WEBTUNNEL_SETUP_ENV --repo bannzai/snapmon" ]; then
    fail "round trip: gh の引数が想定と違う ($(cat "$work/gh-args"))"
    return
  fi

  local registered decoded key value
  registered="$(cat "$work/gh-stdin")"
  case "$registered" in
    *$'\n'*) fail "round trip: 登録する値が 1 行でない"; return ;;
  esac
  if grep -qF -e 'not-a-real-key' -e "$registered" "$work/stdout"; then
    fail "round trip: 標準出力に値が出ている"
    return
  fi

  decoded="$(printf '%s' "$registered" | base64 --decode)"
  if [ "$(printf '%s\n' "$decoded" | wc -l | tr -d ' ')" != 1 ]; then
    fail "round trip: 復号した KEY=VALUE 列が 1 行でない"
    return
  fi
  key="${decoded%%=*}"
  value="${decoded#*=}"
  if [ "$key" != FIREBASE_OPTIONS_DART_B64 ]; then
    fail "round trip: KEY が FIREBASE_OPTIONS_DART_B64 でない ($key)"
    return
  fi

  : > "$work/lib/firebase_options.dart"
  if ! FIREBASE_OPTIONS_DART_B64="$value" bash "$work/scripts/restore-firebase-config.sh" dart > /dev/null; then
    fail "round trip: restore-firebase-config.sh が失敗した"
    return
  fi
  if cmp -s "$work/expected.dart" "$work/lib/firebase_options.dart"; then
    pass "round trip: 書き出したファイルが元と一致する"
  else
    fail "round trip: 書き出したファイルが元と一致しない"
  fi
}

test_missing_file_does_not_call_gh() {
  local work status=0
  work="$(mktemp -d)"
  prepare_workspace "$work"

  PATH="$work/bin:$PATH" GH_ARGS_FILE="$work/gh-args" GH_STDIN_FILE="$work/gh-stdin" \
    bash "$work/scripts/set-webtunnel-setup-env-secret.sh" > /dev/null 2>&1 || status=$?

  if [ "$status" = 1 ] && [ ! -e "$work/gh-args" ]; then
    pass "ファイルが無い時: exit 1 で gh を呼ばない"
  else
    fail "ファイルが無い時: exit=$status, gh 呼び出し=$([ -e "$work/gh-args" ] && echo あり || echo なし)"
  fi
}

test_empty_file_does_not_call_gh() {
  local work status=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  : > "$work/lib/firebase_options.dart"

  PATH="$work/bin:$PATH" GH_ARGS_FILE="$work/gh-args" GH_STDIN_FILE="$work/gh-stdin" \
    bash "$work/scripts/set-webtunnel-setup-env-secret.sh" > /dev/null 2>&1 || status=$?

  if [ "$status" = 1 ] && [ ! -e "$work/gh-args" ]; then
    pass "ファイルが空の時: exit 1 で gh を呼ばない"
  else
    fail "ファイルが空の時: exit=$status, gh 呼び出し=$([ -e "$work/gh-args" ] && echo あり || echo なし)"
  fi
}

test_round_trip
test_missing_file_does_not_call_gh
test_empty_file_does_not_call_gh

if [ "$failures" -gt 0 ]; then
  echo "${failures} 件失敗"
  exit 1
fi
echo "すべて成功"
