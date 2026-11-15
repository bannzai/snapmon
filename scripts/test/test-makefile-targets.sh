#!/usr/bin/env bash
# Makefile の ios-device・web・verify のテスト。flutter を差し替えて (呼ばれた引数を記録し、devices --machine には
# 用意した一覧を返す)、実機の自動選択・実機が無い時の失敗・DEVICE= の指定・web の起動の引数を確かめる。
# web が開くブラウザの選択 (scripts/resolve-web-chrome.sh) は、uname・npx を差し替え、Chrome for Testing を探す場所を
# 作業ディレクトリに向けて確かめる。
# 一時ディレクトリにリポジトリの Makefile を写して実行し、手元の simulator・Chrome・ブラウザのキャッシュには触れない。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
failures=0
# 手元のシェルで export したサイトキー・debug token・RevenueCat の鍵が Makefile の変数に効き、gh の差し替えを使うテストの期待値を変えるため外す
unset RECAPTCHA_ENTERPRISE_SITE_KEY FIREBASE_APPCHECK_DEBUG_TOKEN_WEB REVENUECAT_PUBLIC_API_KEY_IOS REVENUECAT_PUBLIC_API_KEY_ANDROID
# 手元のシェルの指定が web のブラウザの選択と差し替えの振る舞いを変えるため外す
unset CHROME_EXECUTABLE FAKE_UNAME NPX_STUB_MODE

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $1"
}

# 引数: 作業ディレクトリ。Makefile と、引数を $FLUTTER_ARGS_FILE に追記し devices --machine に $FLUTTER_DEVICES_JSON を返す flutter の差し替えを置く。
# flutter-version-check (各 target の前提) が通るよう、pubspec.yaml と検査の script も置き、--version --machine には
# pubspec の版を返す (この呼び出しは引数の記録に含めない)
prepare_workspace() {
  local work=$1
  mkdir -p "$work/bin" "$work/scripts"
  cp "$repo_root/Makefile" "$work/Makefile"
  # 版の検査が読む pubspec は、リポジトリの版を読み直さずに済むよう、差し替えの flutter と同じ固定の版で置く
  printf 'name: snapmon\nenvironment:\n  flutter: 9.9.9\n' > "$work/pubspec.yaml"
  cp "$repo_root/scripts/check-flutter-version.sh" "$work/scripts/check-flutter-version.sh"
  cp "$repo_root/scripts/resolve-web-chrome.sh" "$work/scripts/resolve-web-chrome.sh"
  cat > "$work/bin/flutter" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "--version --machine" ]; then
  printf '{"frameworkVersion": "9.9.9"}\n'
  exit 0
fi
EOF
  cat >> "$work/bin/flutter" <<'EOF'
printf '%s\n' "$*" >> "$FLUTTER_ARGS_FILE"
if [ "$1" = "run" ]; then
  printf '%s\n' "${CHROME_EXECUTABLE-<unset>}" > "$FLUTTER_CHROME_EXECUTABLE_FILE"
fi
if [ "$1 $2" = "devices --machine" ]; then
  printf '%s' "$FLUTTER_DEVICES_JSON"
fi
EOF
  # CI (Linux) でも macOS の経路を確かめられるよう、uname -s は FAKE_UNAME (既定 Darwin) を返す
  cat > "$work/bin/uname" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "${FAKE_UNAME:-Darwin}"
EOF
  # 呼ばれた引数を記録する。NPX_STUB_MODE=install の時だけ --path の場所へ Chrome for Testing 11.0.0.0 を置き、それ以外は取得の失敗として exit 1
  cat > "$work/bin/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$NPX_ARGS_FILE"
[ "${NPX_STUB_MODE:-fail}" = "install" ] || exit 1
macos_dir="${*: -1}/chrome/mac_arm-11.0.0.0/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS"
mkdir -p "$macos_dir"
printf '#!/bin/sh\n' > "$macos_dir/Google Chrome for Testing"
chmod +x "$macos_dir/Google Chrome for Testing"
EOF
  chmod +x "$work/bin/flutter" "$work/bin/uname" "$work/bin/npx"
}

# 引数: 作業ディレクトリ、プラットフォーム (mac_arm 等)、版。Chrome for Testing を探す場所に、その版の実行ファイルを置く
install_fake_chrome_for_testing() {
  local work=$1 platform=$2 version=$3
  local macos_dir="$work/browser-cache/chrome/$platform-$version/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS"
  mkdir -p "$macos_dir"
  printf '#!/bin/sh\n' > "$macos_dir/Google Chrome for Testing"
  chmod +x "$macos_dir/Google Chrome for Testing"
}

# 引数: 作業ディレクトリ、プラットフォーム、版。install_fake_chrome_for_testing が置く実行ファイルのパスを出す
fake_chrome_for_testing_path() {
  printf '%s\n' "$1/browser-cache/chrome/$2-$3/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"
}

# 引数: 作業ディレクトリ、devices --machine が返す JSON、make の引数...。make の exit code を返し、出力は $work/stdout に残す
run_make() {
  local work=$1 devices_json=$2
  shift 2
  : > "$work/flutter-args"
  : > "$work/npx-args"
  : > "$work/flutter-chrome-executable"
  PATH="$work/bin:$PATH" FLUTTER_ARGS_FILE="$work/flutter-args" FLUTTER_DEVICES_JSON="$devices_json" \
    FLUTTER_CHROME_EXECUTABLE_FILE="$work/flutter-chrome-executable" NPX_ARGS_FILE="$work/npx-args" \
    WEB_CHROME_CACHE_DIR="$work/browser-cache" \
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
  if [ "$(recorded_run "$work")" != "run --debug -d my-phone --dart-define=REVENUECAT_PUBLIC_API_KEY_IOS= --dart-define=REVENUECAT_PUBLIC_API_KEY_ANDROID=" ]; then
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
  if [ "$(recorded_run "$work")" != "run --debug -d given-id --dart-define=REVENUECAT_PUBLIC_API_KEY_IOS= --dart-define=REVENUECAT_PUBLIC_API_KEY_ANDROID=" ]; then
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
  if [ "$(cat "$work/flutter-args")" != $'config --enable-web\nrun --debug -d chrome --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=site-key-from-gh --dart-define=FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=' ]; then
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
  if [ "$(recorded_run "$work")" != "run --debug -d chrome --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=site-key-from-env --dart-define=FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=" ]; then
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
  if [ "$(recorded_run "$work")" != "run --debug -d chrome --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY= --dart-define=FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=" ]; then
    fail "web: サイトキーが無い時に空の --dart-define で起動していない ($(recorded_run "$work"))"
    return
  fi
  pass "web: サイトキーが無くても空の --dart-define で起動する"
}

test_web_passes_debug_token_from_environment() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  if ! FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=debug-token-from-env run_make "$work" '[]' web; then
    fail "web: debug token の指定で失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(recorded_run "$work")" != "run --debug -d chrome --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=site-key-from-gh --dart-define=FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=debug-token-from-env" ]; then
    fail "web: 環境変数 FIREBASE_APPCHECK_DEBUG_TOKEN_WEB を --dart-define に渡していない ($(recorded_run "$work"))"
    return
  fi
  pass "web: 環境変数の debug token を --dart-define に渡す"
}

test_web_opens_newest_installed_chrome_for_testing() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  # 文字列の順では 9.0.0.0 が後ろに来るため、数値の順で 10.0.0.0 を選ぶことを確かめる
  install_fake_chrome_for_testing "$work" mac_arm 9.0.0.0
  install_fake_chrome_for_testing "$work" mac_arm 10.0.0.0
  install_fake_chrome_for_testing "$work" mac 9.5.0.0
  # 取得が途中で止まって実行できないファイルだけが残った版は、新しくても選ばない
  install_fake_chrome_for_testing "$work" mac_arm 12.0.0.0
  chmod -x "$(fake_chrome_for_testing_path "$work" mac_arm 12.0.0.0)"
  if ! run_make "$work" '[]' web; then
    fail "web: Chrome for Testing がある時に失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/flutter-chrome-executable")" != "$(fake_chrome_for_testing_path "$work" mac_arm 10.0.0.0)" ]; then
    fail "web: 最も新しい版の Chrome for Testing を CHROME_EXECUTABLE に渡していない ($(cat "$work/flutter-chrome-executable"))"
    return
  fi
  if [ -s "$work/npx-args" ]; then
    fail "web: Chrome for Testing があるのに取得を呼んだ ($(cat "$work/npx-args"))"
    return
  fi
  pass "web: 取得済みの Chrome for Testing のうち最も新しい版で開き、取得は呼ばない"
}

test_web_installs_chrome_for_testing_when_missing() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  if ! NPX_STUB_MODE=install run_make "$work" '[]' web; then
    fail "web: Chrome for Testing の取得で失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/npx-args")" != "--yes @puppeteer/browsers install chrome@stable --path $work/browser-cache" ]; then
    fail "web: Chrome for Testing が無い時に、探す場所へ 1 回だけ取得していない ($(cat "$work/npx-args"))"
    return
  fi
  if [ "$(cat "$work/flutter-chrome-executable")" != "$(fake_chrome_for_testing_path "$work" mac_arm 11.0.0.0)" ]; then
    fail "web: 取得した Chrome for Testing を CHROME_EXECUTABLE に渡していない ($(cat "$work/flutter-chrome-executable"))"
    return
  fi
  pass "web: Chrome for Testing が無ければ取得して、それで開く"
}

test_web_falls_back_to_default_chrome_when_install_fails() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  if ! run_make "$work" '[]' web; then
    fail "web: Chrome for Testing を取得できない時に失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/flutter-chrome-executable")" != "<unset>" ]; then
    fail "web: 取得できない時に CHROME_EXECUTABLE を渡した ($(cat "$work/flutter-chrome-executable"))"
    return
  fi
  if ! grep -q 'Chrome for Testing を取得できませんでした。通常の Chrome で起動します' "$work/stdout"; then
    fail "web: 取得できない時の警告が出ていない ($(cat "$work/stdout"))"
    return
  fi
  pass "web: Chrome for Testing を取得できなければ、警告を出して Flutter の既定の Chrome で開く"
}

# Makefile はコマンド置換で exit code を捨てるため、取得の失敗を失敗として返さない約束はスクリプトを直接呼んで確かめる
test_resolve_web_chrome_succeeds_without_output_when_install_fails() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  if ! PATH="$work/bin:$PATH" NPX_ARGS_FILE="$work/npx-args" WEB_CHROME_CACHE_DIR="$work/browser-cache" \
    bash "$work/scripts/resolve-web-chrome.sh" > "$work/stdout" 2> "$work/stderr"; then
    fail "resolve-web-chrome: Chrome for Testing を取得できない時に exit 0 で終えていない ($(cat "$work/stderr"))"
    return
  fi
  if [ -s "$work/stdout" ]; then
    fail "resolve-web-chrome: 取得できない時に stdout へパスを出した ($(cat "$work/stdout"))"
    return
  fi
  pass "resolve-web-chrome: Chrome for Testing を取得できなければ、何も出さずに exit 0 で終える"
}

test_web_keeps_given_chrome_executable() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  install_fake_chrome_for_testing "$work" mac_arm 10.0.0.0
  if ! CHROME_EXECUTABLE=/given/browser run_make "$work" '[]' web; then
    fail "web: CHROME_EXECUTABLE の指定で失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/flutter-chrome-executable")" != "/given/browser" ]; then
    fail "web: 環境変数 CHROME_EXECUTABLE の指定を Chrome for Testing で上書きした ($(cat "$work/flutter-chrome-executable"))"
    return
  fi
  pass "web: 環境変数 CHROME_EXECUTABLE の指定をそのまま使う"
}

test_web_uses_default_chrome_outside_macos() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  install_fake_chrome_for_testing "$work" mac_arm 10.0.0.0
  if ! FAKE_UNAME=Linux NPX_STUB_MODE=install run_make "$work" '[]' web; then
    fail "web: macOS 以外で失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/flutter-chrome-executable")" != "<unset>" ]; then
    fail "web: macOS 以外で CHROME_EXECUTABLE を渡した ($(cat "$work/flutter-chrome-executable"))"
    return
  fi
  if [ -s "$work/npx-args" ]; then
    fail "web: macOS 以外で取得を呼んだ ($(cat "$work/npx-args"))"
    return
  fi
  pass "web: macOS 以外では取得もせず、Flutter の既定の Chrome で開く"
}

test_build_web_does_not_pass_debug_token() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  if ! FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=debug-token-from-env run_make "$work" '[]' build-web; then
    fail "build-web: 失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/flutter-args")" != "build web --release --dart-define=RECAPTCHA_ENTERPRISE_SITE_KEY=site-key-from-gh" ]; then
    fail "build-web: release のビルドに debug token を渡さない・サイトキーを付ける、になっていない ($(cat "$work/flutter-args"))"
    return
  fi
  pass "build-web: release のビルドには debug token を渡さない"
}

# 引数: 作業ディレクトリ、差し替えの flutter が --version --machine に返す版。prepare_workspace の flutter の版を置き換える
set_flutter_version() {
  local work=$1 version=$2
  sed -i.bak "s/\"frameworkVersion\": \"9.9.9\"/\"frameworkVersion\": \"$version\"/" "$work/bin/flutter"
}

test_verify_runs_after_version_check_passes() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  # verify の後続 (dart format・各テストの script) は作業場所に無く失敗するため、exit code ではなく flutter の呼び出しで確かめる
  run_make "$work" '[]' verify || true
  if [ "$(head -n 1 "$work/flutter-args")" != "pub get" ]; then
    fail "verify: 手元の版が pubspec と一致するのに flutter pub get まで進んでいない ($(cat "$work/stdout"))"
    return
  fi
  pass "verify: 手元の版が pubspec と一致すれば flutter pub get から実行する"
}

test_verify_stops_on_version_mismatch() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  set_flutter_version "$work" "9.9.10"
  if run_make "$work" '[]' verify; then
    fail "verify: 手元の版が pubspec と違うのに成功した"
    return
  fi
  if ! grep -q '手元の Flutter SDK は 9.9.10 で、pubspec.yaml (CI と同じ版) は 9.9.9 です' "$work/stdout"; then
    fail "verify: 版の不一致のエラーメッセージが出ていない ($(cat "$work/stdout"))"
    return
  fi
  if [ -s "$work/flutter-args" ]; then
    fail "verify: 版が違うのに flutter を呼んだ ($(cat "$work/flutter-args"))"
    return
  fi
  pass "verify: 手元の版が pubspec と違えば flutter pub get の前に止まる"
}

test_ios_device_selects_supported_physical_device
test_ios_device_fails_without_physical_device
test_ios_device_uses_device_variable
test_web_enables_web_then_runs_chrome
test_web_prefers_environment_site_key
test_web_runs_without_site_key
test_web_passes_debug_token_from_environment
test_web_opens_newest_installed_chrome_for_testing
test_web_installs_chrome_for_testing_when_missing
test_web_falls_back_to_default_chrome_when_install_fails
test_resolve_web_chrome_succeeds_without_output_when_install_fails
test_web_keeps_given_chrome_executable
test_web_uses_default_chrome_outside_macos
test_build_web_does_not_pass_debug_token
test_verify_runs_after_version_check_passes
test_verify_stops_on_version_mismatch

if [ "$failures" -ne 0 ]; then
  echo "$failures 件失敗"
  exit 1
fi
echo "all passed"
