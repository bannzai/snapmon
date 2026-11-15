#!/usr/bin/env bash
# Makefile の ios-device・web・dart-defines-file・verify と、エディタの実行の設定 (.vscode) のテスト。flutter を差し替えて (呼ばれた引数を記録し、devices --machine には
# 用意した一覧を返す)、実機の自動選択・実機が無い時の失敗・DEVICE= の指定・web の起動の引数を確かめる。
# 一時ディレクトリにリポジトリの Makefile を写して実行し、手元の simulator・Chrome には触れない。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
failures=0
# 手元のシェルで export したサイトキー・debug token・RevenueCat の鍵が Makefile の変数に効き、gh の差し替えを使うテストの期待値を変えるため外す
unset RECAPTCHA_ENTERPRISE_SITE_KEY FIREBASE_APPCHECK_DEBUG_TOKEN_WEB REVENUECAT_PUBLIC_API_KEY_IOS REVENUECAT_PUBLIC_API_KEY_ANDROID

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
  cat > "$work/bin/flutter" <<'EOF'
#!/usr/bin/env bash
if [ "$1 $2" = "--version --machine" ]; then
  printf '{"frameworkVersion": "9.9.9"}\n'
  exit 0
fi
EOF
  cat >> "$work/bin/flutter" <<'EOF'
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

# 引数: 作業ディレクトリ。dart-defines-file が書き出したファイルを、キーの順を揃えた 1 行の JSON で出す
written_dart_defines() {
  jq -c -S . "$1/build/dart_defines.json"
}

test_dart_defines_file_writes_public_values() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  # 値に = を含んでも最初の = でキーと値に分かれることを確かめるため、iOS の鍵に = を入れる
  if ! REVENUECAT_PUBLIC_API_KEY_IOS='ios-key=from-env' REVENUECAT_PUBLIC_API_KEY_ANDROID=android-key-from-env \
    FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=debug-token-from-env run_make "$work" '[]' dart-defines-file; then
    fail "dart-defines-file: 失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(written_dart_defines "$work")" != '{"RECAPTCHA_ENTERPRISE_SITE_KEY":"site-key-from-gh","REVENUECAT_PUBLIC_API_KEY_ANDROID":"android-key-from-env","REVENUECAT_PUBLIC_API_KEY_IOS":"ios-key=from-env"}' ]; then
    fail "dart-defines-file: 公開値の 3 つだけ (debug token を除く) を書き出していない ($(written_dart_defines "$work"))"
    return
  fi
  if [ -s "$work/flutter-args" ]; then
    fail "dart-defines-file: ファイルを書くだけなのに flutter を呼んだ ($(cat "$work/flutter-args"))"
    return
  fi
  pass "dart-defines-file: 環境変数と gh の Variable の公開値を書き出し、debug token は書かない"
}

test_dart_defines_file_writes_empty_values_without_keys() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" ""
  if ! run_make "$work" '[]' dart-defines-file; then
    fail "dart-defines-file: 鍵が無い時に失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(written_dart_defines "$work")" != '{"RECAPTCHA_ENTERPRISE_SITE_KEY":"","REVENUECAT_PUBLIC_API_KEY_ANDROID":"","REVENUECAT_PUBLIC_API_KEY_IOS":""}' ]; then
    fail "dart-defines-file: 鍵が無い時に空の値で書き出していない ($(written_dart_defines "$work"))"
    return
  fi
  pass "dart-defines-file: 鍵が無くても空の値で書き出す (make の各 target と同じ)"
}

test_dart_defines_file_stops_on_version_mismatch() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" "site-key-from-gh"
  set_flutter_version "$work" "9.9.10"
  if run_make "$work" '[]' dart-defines-file; then
    fail "dart-defines-file: 手元の版が pubspec と違うのに成功した"
    return
  fi
  if [ -e "$work/build/dart_defines.json" ]; then
    fail "dart-defines-file: 版が違うのにファイルを書いた"
    return
  fi
  pass "dart-defines-file: 手元の版が pubspec と違えばファイルを書かずに止まる"
}

# アプリが String.fromEnvironment で受けるキーは、書き出すキーと、秘匿値のため書き出さない debug token のどちらかに入る
# (キーを足した時に、エディタの実行にだけ渡らない状態を見つける)
test_dart_defines_file_covers_keys_read_by_app() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" ""
  if ! run_make "$work" '[]' dart-defines-file; then
    fail "dart-defines-file: 失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$({ jq -r 'keys[]' "$work/build/dart_defines.json"; echo FIREBASE_APPCHECK_DEBUG_TOKEN_WEB; } | sort)" != "$(find "$repo_root/lib" -name '*.dart' -exec perl -0777 -ne 'print "$1\n" while /fromEnvironment\(\s*\x27([A-Z0-9_]+)\x27/g' {} + | sort -u)" ]; then
    fail "dart-defines-file: 書き出すキーと debug token の合計が、lib の String.fromEnvironment のキーと一致しない ($(jq -c 'keys' "$work/build/dart_defines.json"))"
    return
  fi
  pass "dart-defines-file: lib が受けるキーを debug token を除いてすべて書き出す"
}

# エディタの実行の設定が、dart-defines-file を実行の前に呼び、その target が書いたファイルを flutter run に渡す
test_editor_launch_reads_file_written_by_task() {
  local work task
  work="$(mktemp -d)"
  prepare_workspace "$work"
  prepare_gh_stub "$work" ""
  task="$(jq -r '.configurations[0].preLaunchTask' "$repo_root/.vscode/launch.json")"
  if [ "$(jq -r --arg label "$task" '.tasks[] | select(.label == $label) | .command' "$repo_root/.vscode/tasks.json")" != "make dart-defines-file" ]; then
    fail "launch.json: preLaunchTask ($task) が tasks.json で make dart-defines-file を呼んでいない"
    return
  fi
  if ! run_make "$work" '[]' dart-defines-file; then
    fail "dart-defines-file: 失敗した ($(cat "$work/stdout"))"
    return
  fi
  # toolArgs (flutter run への引数) に置く。args は main() への引数で、flutter run に渡らない (https://dartcode.org/docs/launch-configuration/)
  if [ ! -f "$work/$(jq -r '.configurations[0].toolArgs[] | select(startswith("--dart-define-from-file=")) | sub("^--dart-define-from-file="; "")' "$repo_root/.vscode/launch.json")" ]; then
    fail "launch.json: toolArgs の --dart-define-from-file が、dart-defines-file の書くファイルを指していない ($(jq -c '.configurations[0].toolArgs' "$repo_root/.vscode/launch.json"))"
    return
  fi
  pass "launch.json: 実行の前に dart-defines-file を呼び、書かれたファイルを flutter run に渡す"
}

test_ios_device_selects_supported_physical_device
test_ios_device_fails_without_physical_device
test_ios_device_uses_device_variable
test_web_enables_web_then_runs_chrome
test_web_prefers_environment_site_key
test_web_runs_without_site_key
test_web_passes_debug_token_from_environment
test_build_web_does_not_pass_debug_token
test_dart_defines_file_writes_public_values
test_dart_defines_file_writes_empty_values_without_keys
test_dart_defines_file_stops_on_version_mismatch
test_dart_defines_file_covers_keys_read_by_app
test_editor_launch_reads_file_written_by_task
test_verify_runs_after_version_check_passes
test_verify_stops_on_version_mismatch

if [ "$failures" -ne 0 ]; then
  echo "$failures 件失敗"
  exit 1
fi
echo "all passed"
