#!/usr/bin/env bash
# scripts/upload-crashlytics-symbols.sh (Xcode のビルドの手順が呼ぶ本体) のテスト。
# flutterfire を引数を記録するだけの偽物に差し替え、HOME と PATH を一時ディレクトリに向けて、手元の flutterfire を拾わないようにする。
# 確かめること: 送信用のスクリプトを探す順 (CocoaPods → Flutter のビルド先 → DerivedData)、どこにも無い時に送信を飛ばして exit 0 になること、
# flutterfire が無い時に何もせず exit 0 になること、flutterfire の失敗がそのまま返ること、pbxproj がこの本体を呼んでいること。
# 置き場所そのものが正しいか (flutter のビルドが実際にどこへ置くか) は、このテストでは確かめられない。実際のビルドで確かめる。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
target="$repo_root/scripts/upload-crashlytics-symbols.sh"
run_relative_path="SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
failures=0

fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $1"
}

# 作業場所を作る。$work/project/ios が SRCROOT、$work/DerivedData/Runner-abc が Xcode の既定のビルドの作業場所
prepare_workspace() {
  work=$(mktemp -d)
  mkdir -p "$work/bin" "$work/home" "$work/project/ios" "$work/DerivedData/Runner-abc/Build/Products"
}

# 偽の flutterfire。引数を 1 行 1 個で $work/flutterfire-args に書き、FAKE_FLUTTERFIRE_EXIT で終了する
install_fake_flutterfire() {
  cat > "$work/bin/flutterfire" <<'EOF'
#!/bin/sh
printf '%s\n' "$@" > "$FAKE_FLUTTERFIRE_ARGS"
exit "${FAKE_FLUTTERFIRE_EXIT:-0}"
EOF
  chmod +x "$work/bin/flutterfire"
}

place_run_script() {
  mkdir -p "$(dirname "$1")"
  : > "$1"
}

# 本体を Xcode が渡す環境変数の最小限で実行する。追加の環境変数は引数 (KEY=VALUE) で渡す
run_target() {
  env -i \
    PATH="$work/bin:/usr/bin:/bin" \
    HOME="$work/home" \
    FAKE_FLUTTERFIRE_ARGS="$work/flutterfire-args" \
    SRCROOT="$work/project/ios" \
    BUILD_ROOT="$work/DerivedData/Runner-abc/Build/Products" \
    PLATFORM_NAME=iphonesimulator \
    CONFIGURATION=Debug \
    "$@" \
    /bin/sh "$target" > "$work/out.log" 2>&1
}

uploaded_script_path() {
  sed -n 's/^--upload-symbols-script-path=//p' "$work/flutterfire-args"
}

# 1. Flutter のビルド先 (build/ios/SourcePackages) にだけある時は、そこを渡す (issue #321 の場面。DerivedData の下には無い)
prepare_workspace
install_fake_flutterfire
place_run_script "$work/project/build/ios/$run_relative_path"
if run_target && [ "$(uploaded_script_path)" = "$work/project/ios/../build/ios/$run_relative_path" ]; then
  pass "Flutter のビルド先にだけある時はそこを渡す"
else
  fail "Flutter のビルド先にだけある時はそこを渡す (出力: $(cat "$work/out.log"))"
fi

# 2. FLUTTER_BUILD_DIR が既定と違う時は、そのビルド先を見る (既定の build の下のものは使わない)
prepare_workspace
install_fake_flutterfire
place_run_script "$work/project/out/ios/$run_relative_path"
if run_target FLUTTER_BUILD_DIR=out && [ "$(uploaded_script_path)" = "$work/project/ios/../out/ios/$run_relative_path" ]; then
  pass "FLUTTER_BUILD_DIR のビルド先を見る"
else
  fail "FLUTTER_BUILD_DIR のビルド先を見る (出力: $(cat "$work/out.log"))"
fi

# 3. DerivedData にだけある時 (Xcode から直接ビルド) は、そこを渡す
prepare_workspace
install_fake_flutterfire
place_run_script "$work/DerivedData/Runner-abc/$run_relative_path"
if run_target && [ "$(uploaded_script_path)" = "$work/DerivedData/Runner-abc/$run_relative_path" ]; then
  pass "DerivedData にだけある時はそこを渡す"
else
  fail "DerivedData にだけある時はそこを渡す (出力: $(cat "$work/out.log"))"
fi

# 4. Flutter のビルド先と DerivedData の両方にある時は、Flutter のビルド先を先に使う
prepare_workspace
install_fake_flutterfire
place_run_script "$work/project/build/ios/$run_relative_path"
place_run_script "$work/DerivedData/Runner-abc/$run_relative_path"
if run_target && [ "$(uploaded_script_path)" = "$work/project/ios/../build/ios/$run_relative_path" ]; then
  pass "両方にある時は Flutter のビルド先を先に使う"
else
  fail "両方にある時は Flutter のビルド先を先に使う (出力: $(cat "$work/out.log"))"
fi

# 5. CocoaPods のものがある時は、それを最優先にする
prepare_workspace
install_fake_flutterfire
place_run_script "$work/Pods/FirebaseCrashlytics/run"
place_run_script "$work/project/build/ios/$run_relative_path"
if run_target PODS_ROOT="$work/Pods" && [ "$(uploaded_script_path)" = "$work/Pods/FirebaseCrashlytics/run" ]; then
  pass "CocoaPods のものを最優先にする"
else
  fail "CocoaPods のものを最優先にする (出力: $(cat "$work/out.log"))"
fi

# 6. PODS_ROOT はあるが CocoaPods に Crashlytics が無い時は、次の候補に進む
prepare_workspace
install_fake_flutterfire
mkdir -p "$work/Pods"
place_run_script "$work/project/build/ios/$run_relative_path"
if run_target PODS_ROOT="$work/Pods" && [ "$(uploaded_script_path)" = "$work/project/ios/../build/ios/$run_relative_path" ]; then
  pass "CocoaPods に無い時は次の候補に進む"
else
  fail "CocoaPods に無い時は次の候補に進む (出力: $(cat "$work/out.log"))"
fi

# 7. どこにも無い時は、警告を出して flutterfire を呼ばず exit 0 (同じ名前のディレクトリがあるだけでは、あるとみなさない)
prepare_workspace
install_fake_flutterfire
mkdir -p "$work/project/build/ios/$run_relative_path"
if run_target && grep -q 'warning: Crashlytics の送信用のスクリプト' "$work/out.log" && [ ! -e "$work/flutterfire-args" ]; then
  pass "どこにも無い時は警告して送信を飛ばす"
else
  fail "どこにも無い時は警告して送信を飛ばす (出力: $(cat "$work/out.log"))"
fi

# 8. flutterfire が無い時は、送信用のスクリプトがあっても何もせず exit 0
prepare_workspace
place_run_script "$work/project/build/ios/$run_relative_path"
if run_target && grep -q 'warning: flutterfire CLI が無いため' "$work/out.log" && [ ! -e "$work/flutterfire-args" ]; then
  pass "flutterfire が無い時は何もしない"
else
  fail "flutterfire が無い時は何もしない (出力: $(cat "$work/out.log"))"
fi

# 9. flutterfire が失敗した時は、その終了コードでビルドを止める (送信の失敗を握りつぶさない)
prepare_workspace
install_fake_flutterfire
place_run_script "$work/project/build/ios/$run_relative_path"
status=0
run_target FAKE_FLUTTERFIRE_EXIT=7 || status=$?
if [ "$status" -eq 7 ]; then
  pass "flutterfire の失敗をそのまま返す"
else
  fail "flutterfire の失敗をそのまま返す (終了コード: ${status})"
fi

# 10. Xcode の環境変数が flutterfire の引数に渡る
prepare_workspace
install_fake_flutterfire
place_run_script "$work/project/build/ios/$run_relative_path"
if run_target && grep -qx -- '--platform=ios' "$work/flutterfire-args" \
  && grep -qx -- "--apple-project-path=$work/project/ios" "$work/flutterfire-args" \
  && grep -qx -- '--env-platform-name=iphonesimulator' "$work/flutterfire-args" \
  && grep -qx -- '--env-configuration=Debug' "$work/flutterfire-args"; then
  pass "Xcode の環境変数が flutterfire の引数に渡る"
else
  fail "Xcode の環境変数が flutterfire の引数に渡る (引数: $(cat "$work/flutterfire-args" 2>/dev/null))"
fi

# 11. Xcode のビルドの手順がこの本体を呼んでいて、置き場所を自分で決める行が pbxproj に残っていない
pbxproj="$repo_root/ios/Runner.xcodeproj/project.pbxproj"
if grep -q 'scripts/upload-crashlytics-symbols.sh' "$pbxproj" && ! grep -q 'SourcePackages/checkouts' "$pbxproj"; then
  pass "pbxproj のビルドの手順が本体を呼ぶ"
else
  fail "pbxproj のビルドの手順が本体を呼ぶ"
fi

if [ "$failures" -ne 0 ]; then
  echo "${failures} 件失敗"
  exit 1
fi
echo "すべて成功"
