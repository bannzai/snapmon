#!/usr/bin/env bash
# scripts/register-appcheck-debug-token.sh と scripts/launch-simtunnel-app.sh のテスト。op・gcloud・curl・uuidgen と ios-wda.sh を
# 差し替え、呼ばれた引数と標準入力を記録して、分岐ごとの exit code・登録先・token が画面と引数に出ないことを確かめる。
# 一時ディレクトリにスクリプトを写して実行し、1Password・Firebase・simulator には触れない。
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
failures=0
# 呼び出し元の環境 (op run で token を渡した端末等) に token があると、token が無い時の分岐のテストが別の経路に入るため消す。
# 各テストは必要な値だけを run_script の前に付けて渡す
unset FIREBASE_APPCHECK_DEBUG_TOKEN_IOS FIREBASE_APPCHECK_DEBUG_TOKEN_ANDROID

# 引数: 失敗の内容。FAIL の行を出し、失敗の件数を 1 増やす
fail() {
  echo "FAIL: $1"
  failures=$((failures + 1))
}

# 引数: 確かめた内容。PASS の行を出す
pass() {
  echo "PASS: $1"
}

# 引数: 作業ディレクトリ。スクリプトと firebase.json と、op・gcloud・curl・uuidgen の差し替えを置く。
# 差し替えの挙動は環境変数で決める: OP_VAULT_EXIT (op vault get の exit code)、OP_ITEM_EXISTS (1 なら op item get が成功)、
# OP_ITEM_GET_ERROR (item が無い時の文言の代わりに op item get が出すエラー文)、
# CURL_STATUS (curl が返す HTTP の状態)
prepare_workspace() {
  local work=$1
  mkdir -p "$work/scripts" "$work/bin"
  cp "$repo_root/scripts/register-appcheck-debug-token.sh" "$repo_root/scripts/launch-simtunnel-app.sh" "$work/scripts/"
  printf '%s\n' '{"flutter":{"platforms":{"ios":{"default":{"appId":"ios-app-id"}},"android":{"default":{"appId":"android-app-id"}}}}}' > "$work/firebase.json"
  cat > "$work/bin/op" <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
  "vault get") exit "${OP_VAULT_EXIT:-0}" ;;
  "item get")
    # 実物の op と同じく、--fields label=title は「title はフィールドではない」で失敗させる (title は item の名前で、フィールドではない)
    case "$*" in *"--fields label=title"*) echo '[ERROR] "title" is not a field' >&2; exit 1 ;; esac
    if [ "${OP_ITEM_EXISTS:-0}" = 1 ]; then echo '{"fields":[{"value":"stored-token-value"}]}'; exit 0; fi
    if [ -n "${OP_ITEM_GET_ERROR:-}" ]; then
      echo "[ERROR] ${OP_ITEM_GET_ERROR}" >&2
    else
      printf '[ERROR] "%s" isn%st an item in the "snapmon" vault.\n' "$3" "'" >&2
    fi
    exit 1
    ;;
  "item create")
    printf '%s\n' "$*" > "$WORK/op-create-args"
    cat > "$WORK/op-create-stdin"
    exit "${OP_CREATE_EXIT:-0}"
    ;;
esac
EOF
  cat > "$work/bin/gcloud" <<'EOF'
#!/usr/bin/env bash
echo fake-access-token
EOF
  cat > "$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
# -H @<ファイル> のヘッダーは、ファイルの中身を curl-header-file に写し、引数の記録では @FILE に置き換える (読み口のパスは実行ごとに変わるため)
recorded=()
for argument in "$@"; do
  if [ "${argument#@}" != "$argument" ] && [ "$argument" != "@-" ]; then
    cat "${argument#@}" > "$WORK/curl-header-file"
    recorded+=("@FILE")
  else
    recorded+=("$argument")
  fi
done
printf '%s\n' "${recorded[*]}" > "$WORK/curl-args"
cat > "$WORK/curl-stdin"
printf '%s' "${CURL_STATUS:-200}"
EOF
  # jq に渡された引数を記録してから本物の jq を実行する (秘匿値が引数に載っていないことを確かめるため)
  cat > "$work/bin/jq" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "\$WORK/jq-args"
exec "$(command -v jq)" "\$@"
EOF
  cat > "$work/bin/uuidgen" <<'EOF'
#!/usr/bin/env bash
echo GENERATED-TOKEN-VALUE
EOF
  cat > "$work/bin/ios-wda" <<'EOF'
#!/usr/bin/env bash
# 呼ばれた順に command (--session <名前> の次の語) とアプリを wda-calls に残す。terminate は記録だけして WDA_TERMINATE_EXIT (既定 0) で終わり、
# launch の引数を wda-args に残す (WDA_EXIT は launch の exit code)
printf '%s %s\n' "$3" "$4" >> "$WORK/wda-calls"
if [ "$3" = terminate ]; then exit "${WDA_TERMINATE_EXIT:-0}"; fi
printf '%s\n' "$*" > "$WORK/wda-args"
while [ $# -gt 0 ]; do
  if [ "$1" = --env-file ]; then cp "$2" "$WORK/wda-env-file"; printf "%s\n" "$2" > "$WORK/wda-env-path"; fi
  shift
done
exit "${WDA_EXIT:-0}"
EOF
  chmod +x "$work/bin/op" "$work/bin/gcloud" "$work/bin/curl" "$work/bin/jq" "$work/bin/uuidgen" "$work/bin/ios-wda"
}

# 引数: 作業ディレクトリ、スクリプト名、スクリプトの引数...。差し替えを PATH の先頭に置いて実行し、出力を $work/stdout に書く
run_script() {
  local work=$1 script=$2
  shift 2
  WORK="$work" PATH="$work/bin:$PATH" IOS_WDA="$work/bin/ios-wda" bash "$work/scripts/$script" "$@" > "$work/stdout" 2>&1
}

# 引数: アプリの ID。App Check の debugTokens の作成 (POST。出典は登録のスクリプトのコメントの公式ドキュメント) で、
# snapmon-prod のそのアプリへ、認証のヘッダーをファイルの読み口から (引数に access token を載せずに)、本文を標準入力から送る時の curl の引数を出す
expected_curl_args() {
  printf '%s\n' "-sS -o /dev/null -w %{http_code} -X POST -H @FILE -H x-goog-user-project: snapmon-prod -H Content-Type: application/json --data-binary @- https://firebaseappcheck.googleapis.com/v1/projects/snapmon-prod/apps/$1/debugTokens"
}

test_register_stops_when_app_id_is_missing() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  printf '%s\n' '{"flutter":{"platforms":{"android":{"default":{"appId":"android-app-id"}}}}}' > "$work/firebase.json"
  FIREBASE_APPCHECK_DEBUG_TOKEN_IOS=token-from-env run_script "$work" register-appcheck-debug-token.sh ios || exit_code=$?
  if [ "$exit_code" != 1 ] || [ -e "$work/curl-args" ] || [ -e "$work/op-create-args" ]; then
    fail "register: firebase.json に iOS のアプリの ID が無いのに登録へ進んだ (exit $exit_code)"
    return
  fi
  pass "register: firebase.json にそのプラットフォームのアプリの ID が無ければ、何も登録せず exit 1"
}

test_register_stops_when_item_creation_fails() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  OP_CREATE_EXIT=1 run_script "$work" register-appcheck-debug-token.sh ios || exit_code=$?
  if [ "$exit_code" != 1 ] || [ -e "$work/curl-args" ] || ! grep -q 'App Check には登録していません' "$work/stdout"; then
    fail "register: 1Password に置けなかった token を App Check に登録した、または exit 1 と理由の表示にならない (exit $exit_code)"
    return
  fi
  pass "register: 1Password への作成が失敗したら、App Check に登録せず理由を出して exit 1"
}

test_launch_stops_when_terminate_fails() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  FIREBASE_APPCHECK_DEBUG_TOKEN_IOS=token-from-env WDA_TERMINATE_EXIT=1 run_script "$work" launch-simtunnel-app.sh snapmon-issue-1 || exit_code=$?
  if [ "$exit_code" != 1 ] || [ "$(cat "$work/wda-calls")" != "terminate com.bannzai.snapmon" ]; then
    fail "launch: アプリの終了が失敗したのに起動へ進んだ、または exit 1 にならない (exit $exit_code: $(cat "$work/wda-calls"))"
    return
  fi
  if ! grep -q 'アプリを終了できませんでした' "$work/stdout" || grep -q 'token-from-env' "$work/stdout"; then
    fail "launch: 終了の失敗の理由を出していない、または token が画面に出ている ($(cat "$work/stdout"))"
    return
  fi
  pass "launch: アプリの終了が失敗したら (起動中のまま残り得るため) 起動せず、理由を出して exit 1"
}

test_launch_fails_and_removes_file_when_launch_fails() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  FIREBASE_APPCHECK_DEBUG_TOKEN_IOS=token-from-env WDA_EXIT=22 run_script "$work" launch-simtunnel-app.sh snapmon-issue-1 || exit_code=$?
  if [ "$exit_code" != 1 ]; then
    fail "launch: 起動の失敗 (差し替えの exit 22) を exit 1 に揃えていない (exit $exit_code)"
    return
  fi
  if [ ! -s "$work/wda-env-path" ] || [ -e "$(cat "$work/wda-env-path")" ]; then
    fail "launch: 起動に失敗した時に token を書いた一時ファイルが残っている"
    return
  fi
  pass "launch: 起動に失敗したら (ios-wda.sh の exit code によらず) exit 1 で終わり、token を書いた一時ファイルを消す"
}

test_register_treats_empty_token_as_not_given() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  FIREBASE_APPCHECK_DEBUG_TOKEN_IOS= OP_ITEM_EXISTS=1 run_script "$work" register-appcheck-debug-token.sh ios || exit_code=$?
  if [ "$exit_code" != 1 ] || [ -e "$work/curl-args" ]; then
    fail "register: 空の token を渡された token として App Check に登録した (exit $exit_code)"
    return
  fi
  pass "register: 空の token は渡されていない時と同じに扱い、item があれば何も登録せず exit 1"
}

test_launch_treats_empty_token_as_missing() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  FIREBASE_APPCHECK_DEBUG_TOKEN_IOS= run_script "$work" launch-simtunnel-app.sh snapmon-issue-1 || exit_code=$?
  if [ "$exit_code" != 1 ] || [ -e "$work/wda-args" ]; then
    fail "launch: 空の token で起動した、または exit 1 にならない (exit $exit_code)"
    return
  fi
  pass "launch: 空の token は無い時と同じに扱い、起動せず exit 1"
}

test_register_rejects_unknown_platform() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  run_script "$work" register-appcheck-debug-token.sh web || exit_code=$?
  if [ "$exit_code" != 2 ] || [ -e "$work/curl-args" ] || [ -e "$work/op-create-args" ]; then
    fail "register: ios・android 以外の引数で exit 2 にならない、または登録を呼んだ (exit $exit_code)"
    return
  fi
  pass "register: ios・android 以外の引数は何も登録せず exit 2"
}

test_register_creates_item_and_registers_new_token() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  if ! run_script "$work" register-appcheck-debug-token.sh ios; then
    fail "register: 初めての発行が失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/op-create-args")" != "item create --vault snapmon -" ] \
    || [ "$(jq -r '.title + " " + .fields[0].value' "$work/op-create-stdin")" != "FIREBASE_APPCHECK_DEBUG_TOKEN_IOS generated-token-value" ]; then
    fail "register: 1Password に小文字にした token を item の名前で作っていない ($(cat "$work/op-create-args"))"
    return
  fi
  if [ "$(jq -r '.token' "$work/curl-stdin")" != "generated-token-value" ] || [ "$(cat "$work/curl-args")" != "$(expected_curl_args ios-app-id)" ]; then
    fail "register: App Check の iOS のアプリに同じ token を登録していない ($(cat "$work/curl-args"))"
    return
  fi
  if grep -q -i 'generated-token-value' "$work/stdout" "$work/curl-args" "$work/op-create-args" "$work/jq-args"; then
    fail "register: token が画面か引数に出ている"
    return
  fi
  if [ "$(cat "$work/curl-header-file")" != "Authorization: Bearer fake-access-token" ] || grep -q 'fake-access-token' "$work/curl-args" "$work/jq-args" "$work/stdout"; then
    fail "register: access token をヘッダーのファイルで渡していない、または引数か画面に出ている"
    return
  fi
  pass "register: 新しい token を 1Password と App Check の iOS のアプリに登録し、画面と引数に出さない"
}

test_register_stops_when_item_exists_without_token() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  OP_ITEM_EXISTS=1 run_script "$work" register-appcheck-debug-token.sh android || exit_code=$?
  if [ "$exit_code" != 1 ] || [ -e "$work/curl-args" ] || [ -e "$work/op-create-args" ]; then
    fail "register: item があるのに作り直した、または exit 1 にならない (exit $exit_code)"
    return
  fi
  pass "register: 1Password に item があり token を渡されていなければ、何も登録せず exit 1"
}

test_register_stops_when_item_lookup_fails_for_other_reason() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  OP_ITEM_GET_ERROR="could not read the item: network unreachable" run_script "$work" register-appcheck-debug-token.sh ios || exit_code=$?
  if [ "$exit_code" != 1 ] || [ -e "$work/curl-args" ] || [ -e "$work/op-create-args" ]; then
    fail "register: item の確認が「無い」以外の理由で失敗したのに、token を作って登録へ進んだ (exit $exit_code)"
    return
  fi
  pass "register: item の確認が「無い」以外の理由で失敗したら、item を作らず exit 1"
}

test_register_stops_when_vault_is_unreadable() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  OP_VAULT_EXIT=1 run_script "$work" register-appcheck-debug-token.sh ios || exit_code=$?
  if [ "$exit_code" != 1 ] || [ -e "$work/curl-args" ] || [ -e "$work/op-create-args" ]; then
    fail "register: vault を読めないのに登録へ進んだ (exit $exit_code)"
    return
  fi
  pass "register: vault を読めなければ (認可切れ)、item を作らず exit 1"
}

test_register_uses_given_token_without_creating_item() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  if ! FIREBASE_APPCHECK_DEBUG_TOKEN_ANDROID=token-from-env run_script "$work" register-appcheck-debug-token.sh android; then
    fail "register: 渡された token の登録が失敗した ($(cat "$work/stdout"))"
    return
  fi
  if grep -q 'token-from-env' "$work/stdout" "$work/curl-args" "$work/jq-args"; then
    fail "register: 渡された token が画面か引数に出ている"
    return
  fi
  if [ -e "$work/op-create-args" ] || [ "$(jq -r '.token' "$work/curl-stdin")" != "token-from-env" ] \
    || [ "$(cat "$work/curl-args")" != "$(expected_curl_args android-app-id)" ]; then
    fail "register: 渡された token を Android のアプリに登録していない、または 1Password に作った"
    return
  fi
  pass "register: 渡された token は 1Password に作らず Android のアプリに登録する"
}

test_register_fails_on_other_status() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  FIREBASE_APPCHECK_DEBUG_TOKEN_IOS=token-from-env CURL_STATUS=403 run_script "$work" register-appcheck-debug-token.sh ios || exit_code=$?
  if [ "$exit_code" != 1 ] || ! grep -q 'HTTP 403' "$work/stdout"; then
    fail "register: 403 で exit 1 と状態の表示にならない (exit $exit_code: $(cat "$work/stdout"))"
    return
  fi
  pass "register: 200 以外は状態を出して exit 1"
}

test_launch_passes_token_by_env_file() {
  local work
  work="$(mktemp -d)"
  prepare_workspace "$work"
  if ! FIREBASE_APPCHECK_DEBUG_TOKEN_IOS=token-from-env run_script "$work" launch-simtunnel-app.sh snapmon-issue-1; then
    fail "launch: 起動が失敗した ($(cat "$work/stdout"))"
    return
  fi
  if [ "$(cat "$work/wda-env-file")" != "FIRAAppCheckDebugToken=token-from-env" ]; then
    fail "launch: 環境変数のファイルに FIRAAppCheckDebugToken を書いていない"
    return
  fi
  if [ "$(sed -E 's# --env-file .*##' "$work/wda-args")" != "--session snapmon-issue-1 launch com.bannzai.snapmon" ] || grep -q 'token-from-env' "$work/wda-args" "$work/stdout"; then
    fail "launch: セッションとアプリの指定が違う、または token が引数か画面に出ている ($(cat "$work/wda-args"))"
    return
  fi
  if [ ! -s "$work/wda-env-path" ] || [ -e "$(cat "$work/wda-env-path")" ]; then
    fail "launch: token を書いた一時ファイルが残っている"
    return
  fi
  if [ "$(cat "$work/wda-calls")" != "$(printf 'terminate com.bannzai.snapmon\nlaunch com.bannzai.snapmon')" ]; then
    fail "launch: アプリを終了してから起動していない ($(cat "$work/wda-calls"))"
    return
  fi
  pass "launch: アプリを終了してから、token を一時ファイルで渡して起動し、引数と画面に出さず、ファイルを消す"
}

test_launch_stops_without_token() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  run_script "$work" launch-simtunnel-app.sh snapmon-issue-1 || exit_code=$?
  if [ "$exit_code" != 1 ] || [ -e "$work/wda-args" ]; then
    fail "launch: token が無いのに起動した、または exit 1 にならない (exit $exit_code)"
    return
  fi
  pass "launch: token が無ければ起動せず exit 1"
}

test_launch_requires_session_name() {
  local work exit_code=0
  work="$(mktemp -d)"
  prepare_workspace "$work"
  FIREBASE_APPCHECK_DEBUG_TOKEN_IOS=token-from-env run_script "$work" launch-simtunnel-app.sh || exit_code=$?
  if [ "$exit_code" != 2 ] || [ -e "$work/wda-args" ]; then
    fail "launch: セッション名が無いのに起動した、または exit 2 にならない (exit $exit_code)"
    return
  fi
  pass "launch: セッション名が無ければ起動せず exit 2"
}

test_register_rejects_unknown_platform
test_register_treats_empty_token_as_not_given
test_launch_treats_empty_token_as_missing
test_register_stops_when_app_id_is_missing
test_register_stops_when_item_creation_fails
test_launch_fails_and_removes_file_when_launch_fails
test_launch_stops_when_terminate_fails
test_register_creates_item_and_registers_new_token
test_register_stops_when_item_exists_without_token
test_register_stops_when_vault_is_unreadable
test_register_stops_when_item_lookup_fails_for_other_reason
test_register_uses_given_token_without_creating_item
test_register_fails_on_other_status
test_launch_passes_token_by_env_file
test_launch_stops_without_token
test_launch_requires_session_name

if [ "$failures" -gt 0 ]; then
  echo "$failures 件失敗"
  exit 1
fi
echo "all passed"
