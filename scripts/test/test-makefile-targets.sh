#!/usr/bin/env bash
# Makefile の ios-device と web のテスト。flutter を差し替えて (呼ばれた引数を記録し、devices --machine には
# 用意した一覧を返す)、実機の自動選択・実機が無い時の失敗・DEVICE= の指定・web の起動の引数を確かめる。
# 一時ディレクトリにリポジトリの Makefile を写して実行し、手元の simulator・Chrome には触れない。
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

# 引数: 作業ディレクトリ。Makefile と、引数を $FLUTTER_ARGS_FILE に追記し devices --machine に $FLUTTER_DEVICES_JSON を返す flutter の差し替えを置く
prepare_workspace() {
  local work=$1
  mkdir -p "$work/bin"
  cp "$repo_root/Makefile" "$work/Makefile"
  cat > "$work/bin/flutter" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FLUTTER_ARGS_FILE"
if [ "$1 $2" = "devices --machine" ]; then
  printf '%s' "$FLUTTER_DEVICES_JSON"
fi
EOF
  chmod +x "$work/bin/flutter"
}

# 引数: 作業ディレクトリ、devices --machine が返す JSON、make の引数...。make の exit code を返し、出力は $work/stdout に残す
run_make() {
  local work=$1 devices_json=$2
  shift 2
  : > "$work/flutter-args"
  PATH="$work/bin:$PATH" FLUTTER_ARGS_FILE="$work/flutter-args" FLUTTER_DEVICES_JSON="$devices_json" \
    make -C "$work" "$@" > "$work/stdout" 2>&1
}

# 引数: 作業ディレクトリ。flutter run に渡された引数の行を出す
recorded_run() {
  grep '^run ' "$1/flutter-args" || true
}

devices_with_supported_phone='[
  {"id":"sim-1","name":"iPhone 17","targetPlatform":"ios","emulator":true,"isSupported":true},
  {"id":"old-phone","name":"iPhone 6","targetPlatform":"ios","emulator":false,"isSupported":false},
  {"id":"pixel","name":"Pixel","targetPlatform":"android-arm64","emulator":false,"isSupported":true},
  {"id":"my-phone","name":"iPhone 15 Pro","targetPlatform":"ios","emulator":false,"isSupported":true}
]'

test_ios_device_selects_supported_physical_device() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  if ! run_make "$work" "$devices_with_supported_phone" ios-device; then
    fail "ios-device: 実機があるのに失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(recorded_run "$work")" != "run --debug -d my-phone" ]; then
    fail "ios-device: simulator・非対応の実機・Android を飛ばして対応している実機を選んでいない ($(cat "$work/flutter-args"))"
    return
  fi
  pass "ios-device: 対応している iOS の実機だけを選ぶ"
}

test_ios_device_fails_without_physical_device() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  local only_simulator='[{"id":"sim-1","name":"iPhone 17","targetPlatform":"ios","emulator":true,"isSupported":true}]'
  if run_make "$work" "$only_simulator" ios-device; then
    fail "ios-device: 実機が無いのに成功した"
    return
  fi
  if ! grep -q '繋がっている iOS の実機が見つかりません' "$work/stdout"; then
    fail "ios-device: 実機が無い時のエラーメッセージが出ていない ($(cat "$work/stdout"))"
    return
  fi
  if [ -n "$(recorded_run "$work")" ]; then
    fail "ios-device: 実機が無いのに flutter run を呼んだ"
    return
  fi
  pass "ios-device: 実機が無ければ flutter run を呼ばずに失敗する"
}

test_ios_device_uses_device_variable() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  if ! run_make "$work" '[]' ios-device DEVICE=given-id; then
    fail "ios-device: DEVICE= 指定で失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(recorded_run "$work")" != "run --debug -d given-id" ]; then
    fail "ios-device: DEVICE= の値を使っていない ($(cat "$work/flutter-args"))"
    return
  fi
  if grep -q '^devices ' "$work/flutter-args"; then
    fail "ios-device: DEVICE= 指定なのに flutter devices を呼んだ"
    return
  fi
  pass "ios-device: DEVICE= の指定をそのまま使う"
}

test_web_enables_web_then_runs_chrome() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  if ! run_make "$work" '[]' web; then
    fail "web: 失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/flutter-args")" != $'config --enable-web\nrun --debug -d chrome' ]; then
    fail "web: config --enable-web の後に run --debug -d chrome を呼んでいない ($(cat "$work/flutter-args"))"
    return
  fi
  pass "web: enable-web を有効にしてから Chrome で起動する"
}

test_ios_device_selects_supported_physical_device
test_ios_device_fails_without_physical_device
test_ios_device_uses_device_variable
test_web_enables_web_then_runs_chrome

if [ "$failures" -ne 0 ]; then
  echo "$failures 件失敗"
  exit 1
fi
echo "all passed"
