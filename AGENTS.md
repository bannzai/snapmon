# snapmon

撮った写真の被写体がモンスターになってバトルするゲームです。

企画・要件は @documents/PROJECT.md、仮説・判定基準・決めたことは @documents/DIRECTION.md を参照してください。

- Flutter のコード: @lib/ 。機能ごとにディレクトリを切り、実装の説明はコード上のコメントに書く
- コーディング規約・ルール: @.claude/rules/ に配置する。プロジェクト仕様書・ADR 等のドキュメントは @documents/ に配置する

## ビルド・テスト・検証方法

ビルド・simulator・ブラウザの動作確認は外部のマシンで行い、開発に使うこの Mac では実行しない。この Mac は複数のプロダクトの agent を並列で動かしていて CPU・メモリが逼迫しやすく、Flutter のビルドや simulator を足すと他の作業まで止まるため。外部のマシンは、リポジトリが public の間は GitHub Actions (CI・simtunnel・webtunnel)、private に変わったら Devin (`/devin-macos-e2e` skill) を使う。

- 静的解析・テスト: PR ごとに `.github/workflows/flutter-ci.yml` が `flutter analyze` / `dart format` / `flutter test` を実行する。ローカルで実行するのは CI の失敗を直す時だけにし、コマンドは `make verify` (CI と同じ内容) を使う。テストが無い変更にはテストを足す
- ビルド: 同じ workflow が Web (`flutter build web`)・Android (`flutter build apk --debug`) のビルドを行う。iOS のビルドは PR の CI に置かない (macOS ランナーの同時実行数の上限をアカウント内の他のリポジトリ (Pilll 等) と共有していて、何時間も QUEUED のまま進まずマージを止めたため。bannzai の判断、2026-10-30。 https://github.com/bannzai/snapmon/pull/114 )。iOS のビルドが通るかは simtunnel での動作確認 (下の項目) とリリースの作業で確かめ、PR のマージの条件にしない。ローカルで `flutter build` を実行しない
- 動作確認 (iOS の UI・挙動): `/ios-simulator` skill を起点にし、**特別な理由がない限り simtunnel (GitHub Actions macOS Runner 上のリモート iOS Simulator) で行う**。ローカル simulator (sim-boot) は既定にしない。issue や手順書にローカル前提の記述 (`make ios` 等) があっても、それだけではローカルに倒す理由にしない
  - 手順: 検証対象のブランチを push してから `SIMTUNNEL_REPO=bannzai/snapmon ~/ghq/github.com/bannzai/simtunnel/local/simtunnel up <セッション名> --ref <ブランチ> --wait` で起動する (`--ref` を省略すると main がビルドされる)。caller workflow は `.github/workflows/simulator-session.yml`、セッション名は `snapmon-<worktree 名>` (例: `snapmon-issue-12`。tailnet ホスト名が repo 横断で衝突しないよう worktree 名だけにしない)。操作・スクリーンショットは `/ios-simulator` skill の `scripts/ios-wda.sh --session <セッション名>` (セッション途中から使う場合) か、`.mcp.json` に書き込んだ mobile-mcp 互換ツールで行う。確認が終わったら `SIMTUNNEL_REPO=bannzai/snapmon ~/ghq/github.com/bannzai/simtunnel/local/simtunnel down <セッション名>` で閉じる (`up` と同じ repo を渡す。macOS runner の並列上限を CI と共有するため放置しない)
  - 到達困難な状態 (所持モンスターの数・バトルの途中・課金状態等) は DEBUG ビルド限定の開発者メニューで作る。リモートでは `xcrun simctl` を使えないため、必要な操作が無ければ開発者メニューに追加してから検証する。Simulator にはカメラが無いため、撮影の代わりにアルバムから選ぶ経路か、開発者メニューに同梱した見本画像を読み込む経路で検証する
  - repo が private / internal に変わった場合は、`/ios-simulator` skill Phase 1 の owner による分岐に従って Devin を使う
  - simtunnel が使えない時は、ローカルの前に `/ios-simulator` skill Phase 1 の remote-mac (`remote-mac check bannzai/snapmon` が exit 0 なら使う) を試す
  - ローカル sim-boot (`/sim-manager`) に倒してよいのは、mobile-mcp 互換ツールの操作だけでは検証が成立しない場合 (Maestro E2E・XCUITest・StoreKit 検証・`xcrun simctl` が検証の本体である手順) と、`/ios-simulator` skill Phase 1 が定める運用上の条件 (検証対象が未 push・即時性が必要・セッション自動終了時間を超える作業・macOS Runner の並列上限・tailnet 未接続・simtunnel の実行権限が無い非対話実行・Secrets 未登録で導入が未完了) に当たる場合だけ。いずれの場合も、ローカルに倒した理由を完了報告に明記する (使い分けの SSOT は `/ios-simulator` skill Phase 1)
- 動作確認 (Web の UI・挙動): `/webtunnel` skill で、GitHub Actions の Linux Runner 上の Chromium に Web 版を開いて行う。ローカルのブラウザ (agent-browser) は既定にしない
  - 手順: 検証対象のブランチを push してから `WEBTUNNEL_REPO=bannzai/snapmon bash ~/.claude/skills/webtunnel/scripts/webtunnel-cli.sh up <セッション名> --ref <ブランチ> --wait` で起動する。caller workflow は `.github/workflows/browser-session.yml` で、runner 上で Flutter を取得して `flutter build web` した成果物を `http://localhost:8080/` で配信する。Flutter Web の描画は WebGL を使うため、caller workflow はソフトウェア WebGL を既定で有効にしている。操作・スクリーンショット・終了と録画の取得は `/webtunnel` skill の Phase 3・4 に従う
  - 例外 (release ビルドの App Check): webtunnel の Chromium と headless の Chrome は reCAPTCHA Enterprise のスコアが低くトークン交換が 403 になる。release ビルドで App Check が通るかは、flutter-ci の artifact `web-build` を `gh run download <検証する commit の run ID> -n web-build -D tmp/web-build-<run ID>` で取り、`python3 -m http.server 8090 --bind 127.0.0.1 --directory tmp/web-build-<run ID>` で配信して `agent-browser --headed` の Chrome で開いて確かめる (手順は QA データベースの `_root` の項目)。webtunnel で Functions を呼ぶ時は debug ビルド (`-f flutter_build_mode=debug`。debug token で App Check を通す)
- 動作確認 (Android): Android の UI 確認の外部経路は未整備で、当面は CI の `flutter build apk --debug` が通ることまでを確認する。UI の確認が要る変更は、iOS と Web の確認結果と、Android で確認していない事実を PR に書く
- 手元で触る (人が確認する時): `make` (既定 target は `ios`。sim-boot で起動したプロジェクト固有の simulator へ `flutter run` する)。繋いだ iPhone の実機は `make ios-device`、手元の Chrome で Web 版は `make web`、Android Emulator は `make android`

<!-- ai-review-config begin -->
<!--
このブロックは自動生成です。直接編集せず、テンプレートを更新してから再生成してください。
内容は AI コードレビュー時の挙動指示であり、コードベース自体への規約ではありません。
-->

## レビュー時の応答スタイル

- 応答は日本語で行う

## レビュー範囲外

以下は自動レビューで指摘しない (別の検出経路があるため):

- コンパイルエラー・型エラー (ローカル/CI のビルドで検出される)
- Lint/フォーマット違反 (リンター・フォーマッターで検出される)
<!-- ai-review-config end -->
