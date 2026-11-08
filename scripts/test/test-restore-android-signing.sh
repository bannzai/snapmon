#!/usr/bin/env bash
# scripts/restore-android-signing.sh のテスト。一時ディレクトリにリポジトリの scripts/ を写して実行し、手元の android/ には触れない。
# 確かめること: 2 つの Secret から元のファイルに戻ること (冪等)、Secret が無い・base64 でない・keystore が小さい時に exit 1 で止まること。
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

prepare_workspace() {
  local work=$1
  mkdir -p "$work/scripts" "$work/android/app"
  cp "$repo_root/scripts/restore-android-signing.sh" "$work/scripts/"
}

# 本物の JKS ではなく、サイズの下限 (1000 bytes) を超えるバイナリ風の中身
fake_jks() {
  head -c 2600 /dev/urandom
}

fake_properties() {
  printf 'storePassword=fake-store-password\nkeyPassword=fake-key-password\nkeyAlias=upload\nstoreFile=upload-keystore.jks\n'
}

# 1. 2 つの Secret から元のファイルに戻る。2 回実行しても同じ
work=$(mktemp -d)
prepare_workspace "$work"
fake_jks > "$work/expected.jks"
fake_properties > "$work/expected.properties"
export ANDROID_KEYSTORE_JKS_BASE64 ANDROID_KEY_PROPERTIES_BASE64
ANDROID_KEYSTORE_JKS_BASE64=$(base64 < "$work/expected.jks" | tr -d '\n')
ANDROID_KEY_PROPERTIES_BASE64=$(base64 < "$work/expected.properties" | tr -d '\n')
for round in 1 2; do
  if (cd "$work" && bash scripts/restore-android-signing.sh > /dev/null) \
    && cmp -s "$work/expected.jks" "$work/android/app/upload-keystore.jks" \
    && cmp -s "$work/expected.properties" "$work/android/key.properties"; then
    pass "Secret から upload-keystore.jks と key.properties に戻る (${round} 回目)"
  else
    fail "Secret から upload-keystore.jks と key.properties に戻る (${round} 回目)"
  fi
done

# 2. keystore の Secret が無いと exit 1 で、key.properties も書かない
work=$(mktemp -d)
prepare_workspace "$work"
if (cd "$work" && ANDROID_KEYSTORE_JKS_BASE64= bash scripts/restore-android-signing.sh > "$work/out.log" 2>&1); then
  fail "keystore の Secret が無い時に止まる"
elif grep -q 'ANDROID_KEYSTORE_JKS_BASE64 が未登録' "$work/out.log" && [ ! -e "$work/android/key.properties" ]; then
  pass "keystore の Secret が無い時に止まる"
else
  fail "keystore の Secret が無い時に止まる (出力: $(cat "$work/out.log"))"
fi

# 3. key.properties の Secret が base64 でないと exit 1 (macOS の base64 は英数字以外を読み飛ばすため、記号だけの入力にする)
work=$(mktemp -d)
prepare_workspace "$work"
if (cd "$work" && ANDROID_KEY_PROPERTIES_BASE64='!!!!' bash scripts/restore-android-signing.sh > "$work/out.log" 2>&1); then
  fail "key.properties の Secret が base64 でない時に止まる"
elif grep -q 'ANDROID_KEY_PROPERTIES_BASE64 を base64 として読めません' "$work/out.log"; then
  pass "key.properties の Secret が base64 でない時に止まる"
else
  fail "key.properties の Secret が base64 でない時に止まる (出力: $(cat "$work/out.log"))"
fi

# 4. keystore が 1000 bytes 未満なら exit 1 (999 bytes は止まり、1 のケースの 2600 bytes は通る)
work=$(mktemp -d)
prepare_workspace "$work"
small_jks=$(head -c 999 /dev/urandom | base64 | tr -d '\n')
if (cd "$work" && ANDROID_KEYSTORE_JKS_BASE64="$small_jks" bash scripts/restore-android-signing.sh > "$work/out.log" 2>&1); then
  fail "keystore が小さすぎる時に止まる"
elif grep -q '999 bytes しかありません' "$work/out.log"; then
  pass "keystore が小さすぎる時に止まる"
else
  fail "keystore が小さすぎる時に止まる (出力: $(cat "$work/out.log"))"
fi

if [ "$failures" -ne 0 ]; then
  echo "${failures} 件失敗"
  exit 1
fi
echo "すべて成功"
