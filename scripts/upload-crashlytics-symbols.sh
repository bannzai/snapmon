#!/bin/bash
# Xcode のビルドの手順「FlutterFire: "flutterfire upload-crashlytics-symbols"」(ios/Runner.xcodeproj/project.pbxproj) の本体。
# クラッシュの解析に使うシンボルを Firebase Crashlytics へ送る。Xcode がビルド設定を環境変数で渡す前提で、手で直接は実行しない。
#
# 送信用のスクリプト (firebase-ios-sdk の Crashlytics/run) は、ビルドの経路で置かれる場所が違うため、候補を順に探して最初にあったものを使う。
# どこにも無い時と flutterfire CLI が無い時 (CI の Simulator 向けビルド等) は、警告を出して送信を飛ばし、ビルドを止めない (exit 0)。
# 同じ入力なら同じ結果になる (ファイルを書かない)。テストは scripts/test/test-upload-crashlytics-symbols.sh
PATH="${PATH}:$FLUTTER_ROOT/bin:${PUB_CACHE}/bin:$HOME/.pub-cache/bin"

if ! command -v flutterfire >/dev/null 2>&1; then
  echo "warning: flutterfire CLI が無いため Crashlytics のシンボルをアップロードしません"
  exit 0
fi

swift_package_run_path="SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
upload_script_path=""
for candidate in \
  "${PODS_ROOT:+$PODS_ROOT/FirebaseCrashlytics/run}" \
  "${SRCROOT}/../${FLUTTER_BUILD_DIR:-build}/ios/${swift_package_run_path}" \
  "$(echo "$BUILD_ROOT" | sed -E 's|(.*DerivedData/[^/]+).*|\1|')/${swift_package_run_path}"; do
  # 1 つ目: CocoaPods で入れた時。
  # 2 つ目: flutter run / flutter build 経由のビルド。flutter_tools が xcodebuild に
  #   -clonedSourcePackagesDirPath <Flutter のビルド先>/ios/SourcePackages を渡す (packages/flutter_tools/lib/src/ios/xcodeproj.dart)。
  # 3 つ目: Xcode から直接ビルドした時 (Xcode の既定の DerivedData)。
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    upload_script_path="$candidate"
    break
  fi
done

if [ -z "$upload_script_path" ]; then
  echo "warning: Crashlytics の送信用のスクリプト (Crashlytics/run) が見つからないため、シンボルをアップロードしません"
  exit 0
fi

flutterfire upload-crashlytics-symbols --upload-symbols-script-path="$upload_script_path" --platform=ios --apple-project-path="${SRCROOT}" --env-platform-name="${PLATFORM_NAME}" --env-configuration="${CONFIGURATION}" --env-project-dir="${PROJECT_DIR}" --env-built-products-dir="${BUILT_PRODUCTS_DIR}" --env-dwarf-dsym-folder-path="${DWARF_DSYM_FOLDER_PATH}" --env-dwarf-dsym-file-name="${DWARF_DSYM_FILE_NAME}" --env-infoplist-path="${INFOPLIST_PATH}" --default-config=default
