#!/usr/bin/env bash
# make web が flutter run に環境変数 CHROME_EXECUTABLE で渡す、Chrome for Testing の実行ファイルのパスを stdout に出す。
# flutter run -d chrome は既定で /Applications/Google Chrome.app を別のプロセスとして起動し、macOS のアプリケーション
# スイッチャーに普段使いの Chrome と同じ名前・同じアイコンで並ぶ。Chrome for Testing は別のアプリ (名前が
# 「Google Chrome for Testing」、アイコンに TEST の帯) として並ぶため、こちらで起動して見分けられるようにする
# ( https://github.com/bannzai/snapmon/issues/319 )。
#
# - 探す場所は @puppeteer/browsers のキャッシュ (既定 ~/.cache/puppeteer。WEB_CHROME_CACHE_DIR で変えられる) で、
#   複数の版があれば最も新しい版を選ぶ
# - macOS 以外と、1 つも無い時は stdout に何も出さずに exit 0 で終え、呼び出し側は Flutter の既定の Chrome で起動する。
#   無い時は取得のコマンドを stderr に出す (数百 MB の取得を make web が黙って始めないよう、取得は人が実行する)
# - 冪等: 何も書き込まず、同じ状態なら同じパスを出す
set -euo pipefail

cache_dir="${WEB_CHROME_CACHE_DIR:-$HOME/.cache/puppeteer}"

[ "$(uname -s)" = "Darwin" ] || exit 0

chrome="$(
  for app in "$cache_dir"/chrome/mac*-*/chrome-mac-*/"Google Chrome for Testing.app"; do
    executable="$app/Contents/MacOS/Google Chrome for Testing"
    [ -x "$executable" ] || continue
    # 版は 2 つ上のディレクトリ名 (mac_arm-155.0.8059.79 等) の最後の - より後ろ
    printf '%s\t%s\n' "$(basename "$(dirname "$(dirname "$app")")" | sed 's/.*-//')" "$executable"
  done | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -n 1 | cut -f2-
)"
if [ -z "$chrome" ]; then
  echo "Warning: Chrome for Testing が $cache_dir に無いため、通常の Chrome で起動します (アプリケーションスイッチャーで見分けは付きません)。見分けられるようにするには次を 1 回実行してください: npx @puppeteer/browsers install chrome@stable --path \"$cache_dir\"" >&2
  exit 0
fi
printf '%s\n' "$chrome"
