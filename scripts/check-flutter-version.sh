#!/usr/bin/env bash
# 手元の Flutter SDK の版が、pubspec.yaml の environment: flutter: (CI の subosito/flutter-action も
# flutter-version-file でこの値を読む) と一致するかを検査する。違えば揃えるコマンドを示して止まる。
# pub は flutter の制約の下限しか検査しない (https://dart.dev/tools/pub/pubspec#flutter-sdk-constraints) ため、
# 手元の SDK が新しすぎる場合はこの検査でしか気付けない。
#
# 置いたのは bannzai/castle の flutter-sdk-update skill。手で直さず skill を再実行して更新する。
#
# Usage: bash scripts/check-flutter-version.sh
# 環境変数: PUBSPEC (既定 pubspec.yaml)、FLUTTER (既定 flutter。テストで差し替える)
# Exit codes: 0 一致 / 1 不一致 / 2 版を読めない (pubspec に environment: flutter: が無い・flutter が無い)
set -euo pipefail

pubspec="${PUBSPEC:-pubspec.yaml}"
flutter_command="${FLUTTER:-flutter}"

expected="$(awk '
  /^[^[:space:]#]/ { in_environment = ($0 ~ /^environment:[[:space:]]*(#.*)?$/); next }
  in_environment && /^[[:space:]]+flutter:/ {
    value = $0
    sub(/^[[:space:]]+flutter:[[:space:]]*/, "", value)
    sub(/[[:space:]]*#.*$/, "", value)
    gsub(/["\047]/, "", value)
    print value
    exit
  }
' "$pubspec")"
if [ -z "$expected" ]; then
  echo "Error: $pubspec の environment: に flutter: <版> がありません" >&2
  exit 2
fi

if ! machine="$("$flutter_command" --version --machine 2>/dev/null)"; then
  echo "Error: $flutter_command --version を実行できません (Flutter SDK が PATH にあるか確認してください)" >&2
  exit 2
fi
actual="$(printf '%s\n' "$machine" | sed -n 's/.*"frameworkVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
flutter_root="$(printf '%s\n' "$machine" | sed -n 's/.*"flutterRoot"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"

if [ "$actual" = "$expected" ]; then
  exit 0
fi

{
  echo "Error: 手元の Flutter SDK は ${actual:-不明} で、$pubspec (CI と同じ版) は $expected です。"
  if [ -n "$flutter_root" ] && [ -d "$flutter_root/.git" ]; then
    echo "次のコマンドで $flutter_root を $expected に揃えてから再実行してください (この SDK を使う他のリポジトリの版も変わります):"
    # origin が fork の checkout でもタグを取れるよう、本家から取る
    echo "  git -C \"$flutter_root\" fetch https://github.com/flutter/flutter.git refs/tags/$expected:refs/tags/$expected"
    echo "  git -C \"$flutter_root\" checkout $expected"
    echo "  $flutter_command --version"
  else
    echo "Flutter SDK $expected を https://docs.flutter.dev/install/archive から入れて PATH に通してから再実行してください。"
  fi
} >&2
exit 1
