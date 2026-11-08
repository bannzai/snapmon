#!/usr/bin/env bash
# pubspec.yaml の environment: flutter: の版の Flutter SDK を、flutter/flutter の git から取得して <dest> に置く。
# subosito/flutter-action を使えない runner (webtunnel の setup_command 等) で、CI と同じ版の flutter を使うためのもの。
# タグは書き換えられ得るため、Flutter 公式のリリース一覧 (releases_linux.json) がその版に記録している commit と
# タグが指す commit が一致する時だけ使う。flutter_tools はタグから自分の版を求め、タグが無いと 0.0.0-unknown になって
# pubspec の SDK 制約を満たせないため、タグごと取得する。
#
# Usage: bash scripts/install-flutter-sdk.sh <dest>
# 成功すると <dest>/bin/flutter が pubspec の版になる。
set -euo pipefail

dest="${1:?Usage: install-flutter-sdk.sh <dest>}"

version="$(awk '
  /^[^[:space:]#]/ { in_environment = ($0 ~ /^environment:[[:space:]]*(#.*)?$/); next }
  in_environment && /^[[:space:]]+flutter:/ {
    value = $0
    sub(/^[[:space:]]+flutter:[[:space:]]*/, "", value)
    sub(/[[:space:]]*#.*$/, "", value)
    gsub(/["\047]/, "", value)
    print value
    exit
  }
' pubspec.yaml)"
if [ -z "$version" ]; then
  echo "Error: pubspec.yaml の environment: に flutter: <版> がありません" >&2
  exit 2
fi

expected_commit="$(curl -fsSL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json \
  | python3 -c 'import json, sys; v = sys.argv[1]; print(next(r["hash"] for r in json.load(sys.stdin)["releases"] if r["channel"] == "stable" and r["version"] == v))' "$version")"

git init -q "$dest"
git -C "$dest" fetch -q --depth 1 https://github.com/flutter/flutter.git "refs/tags/$version:refs/tags/$version"
actual_commit="$(git -C "$dest" rev-parse "$version^{commit}")"
if [ "$actual_commit" != "$expected_commit" ]; then
  echo "Error: タグ $version は $actual_commit を指していて、リリース一覧の $expected_commit と一致しません" >&2
  exit 1
fi
git -C "$dest" checkout -q --detach "$version"
