#!/usr/bin/env bash
# make web が flutter run に環境変数 CHROME_EXECUTABLE で渡す、Chrome for Testing の実行ファイルのパスを stdout に出す。
# flutter run -d chrome は既定で /Applications/Google Chrome.app を別のプロセスとして起動し、macOS のアプリケーション
# スイッチャーに普段使いの Chrome と同じ名前・同じアイコンで並ぶ。Chrome for Testing は別のアプリ (名前が
# 「Google Chrome for Testing」、アイコンに TEST の帯) として並ぶため、こちらで起動して見分けられるようにする
# ( https://github.com/bannzai/snapmon/issues/319 )。
#
# - 探す場所は @puppeteer/browsers のキャッシュ (既定 ~/.cache/puppeteer。WEB_CHROME_CACHE_DIR で変えられる) で、
#   複数の版があれば最も新しい版を選ぶ
# - 1 つも無ければ `npx @puppeteer/browsers install chrome@stable` で同じ場所へ取得する (初回だけ。数百 MB)
# - macOS 以外と、取得できなかった時 (npx が無い・オフライン) は何も出さずに exit 0 で終え、呼び出し側は
#   Flutter の既定の Chrome で起動する。見分けが付かないだけで make web は止めない
# - 冪等: 取得済みなら何も書き込まず、同じパスを出す
set -euo pipefail

cache_dir="${WEB_CHROME_CACHE_DIR:-$HOME/.cache/puppeteer}"

# キャッシュにある Chrome for Testing のうち、最も新しい版の実行ファイルのパスを出す (無ければ何も出さない)
newest_installed_chrome() {
  local app executable
  for app in "$cache_dir"/chrome/mac*-*/chrome-mac-*/"Google Chrome for Testing.app"; do
    executable="$app/Contents/MacOS/Google Chrome for Testing"
    [ -x "$executable" ] || continue
    # 版は 2 つ上のディレクトリ名 (mac_arm-155.0.8059.79 等) の最後の - より後ろ
    printf '%s\t%s\n' "$(basename "$(dirname "$(dirname "$app")")" | sed 's/.*-//')" "$executable"
  done | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -n 1 | cut -f2-
}

[ "$(uname -s)" = "Darwin" ] || exit 0

chrome="$(newest_installed_chrome)"
if [ -z "$chrome" ]; then
  echo "Chrome for Testing が $cache_dir に無いため取得します (初回だけ)" >&2
  if ! npx --yes @puppeteer/browsers install chrome@stable --path "$cache_dir" >&2; then
    echo "Warning: Chrome for Testing を取得できませんでした。通常の Chrome で起動します (アプリケーションスイッチャーで見分けは付きません)" >&2
    exit 0
  fi
  chrome="$(newest_installed_chrome)"
fi
[ -z "$chrome" ] || printf '%s\n' "$chrome"
