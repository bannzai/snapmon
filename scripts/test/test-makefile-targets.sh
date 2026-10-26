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

# 引数: 作業ディレクトリ、gh variable get が返すサイトキー (空なら未登録として exit 1)。Makefile が呼ぶ gh の差し替えを置く
prepare_gh_stub() {
  local work=$1 site_key=$2
  cat > "$work/bin/gh" <<EOF
#!/usr/bin/env bash
if [ "\$1 \$2 \$3" = "variable get RECAPTCHA_ENTERPRISE_SITE_KEY" ]; then
  [ -n "$site_key" ] || exit 1
  printf '%s\n' "$site_key"
fi
EOF
  chmod +x "$work/bin/gh"
}

test_web_enables_web_then_runs_chrome() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  if ! run_make "$work" '[]' web; then
    fail "web: 失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/flutter-args")" != $'config --enable-web\nrun --debug -d chrome --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=site-key-from-gh' ]; then
    fail "web: config --enable-web の後に、gh の Variable のサイトキーを付けて run --debug -d chrome を呼んでいない ($(cat "$work/flutter-args"))"
    return
  fi
  pass "web: enable-web を有効にしてから gh の Variable のサイトキーを付けて Chrome で起動する"
}

test_web_prefers_environment_site_key() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  if ! RECAPTCHA_ENTERPRISE_SITE_KEY=site-key-from-env run_make "$work" '[]' web; then
    fail "web: 環境変数のサイトキー指定で失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(recorded_run "$work")" != "run --debug -d chrome --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=site-key-from-env" ]; then
    fail "web: 環境変数 RECAPTCHA_ENTERPRISE_SITE_KEY を gh の Variable より優先していない ($(recorded_run "$work"))"
    return
  fi
  pass "web: 環境変数のサイトキーを gh の Variable より優先する"
}

test_web_runs_without_site_key() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" ""
  if ! run_make "$work" '[]' web; then
    fail "web: サイトキー未設定で失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(recorded_run "$work")" != "run --debug -d chrome --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=" ]; then
    fail "web: サイトキーが無い時に空の --dart-define で起動していない ($(recorded_run "$work"))"
    return
  fi
  pass "web: サイトキーが無くても空の --dart-define で起動する"
}

test_ios_device_selects_supported_physical_device
test_ios_device_fails_without_physical_device
test_ios_device_uses_device_variable
test_web_enables_web_then_runs_chrome
test_web_prefers_environment_site_key
test_web_runs_without_site_key

if [ "$failures" -ne 0 ]; then
  echo "$failures 件失敗"
  exit 1
fi
echo "all passed"
