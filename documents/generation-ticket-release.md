# 生成チケットの解放の手順

生成チケットの課金は実装済みで閉じている。何を決めたかは [DIRECTION.md](DIRECTION.md)「決めたこと」2026-11-07 の #186 の行が正で、この文書は解放の時に打つ操作をまとめる。

RevenueCat の値は `revenuecat/config.json` が正で、生成チケットの offering は `ofrng07ce9e2214`、閉じている間の offering (package が無い) は `ofrngd8f9737dda`。

## 解放の前に揃えるもの

- App Store Connect のアプリのレコードと商品 2 つ (#183)。アプリのレコードの作成は Apple ID の認証が要る (`~/.claude/skills/appstore-in-app-purchase/references/api_endpoints.md`)
- Google Play Console の商品 2 つ (同じ識別子)
- RevenueCat の app に App Store の In-App Purchase Key と Google Play のサービスアカウントを登録する
- RevenueCat の webhook を `revenueCatWebhook` に向ける (Authorization は Secret Manager の `REVENUECAT_WEBHOOK_AUTHORIZATION` と同じ値)

## ストアへ出すビルド

`lib/firebase/purchases.dart` は鍵の `--dart-define` が空のビルドで SDK を初期化しないため、鍵なしのビルドを出すと offering を切り替えても購入画面が出ず、再リリースが要る。iOS は `--dart-define=REVENUECAT_PUBLIC_API_KEY_IOS=<GitHub Variable の値>`、Android は `--dart-define=REVENUECAT_PUBLIC_API_KEY_ANDROID=<GitHub Variable の値>` を付けてビルドする。

## iOS の最初の提出

Apple は最初の消耗型の商品を新しいアプリのバージョンと一緒に提出するよう求める。出典: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase (2026-11-07 に確認)。そのため最初のアプリの提出に商品を含めて審査を通す。

1. 提出の前に App Store Connect でリリースの方法を手動にする (自動だと、閉じ直す前に公開されて利用者に購入画面が出ることがあるため)。App Store Connect の選択肢は「Manually release this version.」。出典: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/ (2026-11-07 に確認)
2. 審査の間だけ生成チケットの offering を current にする (審査の担当者が購入の経路を見られるようにするため)

   ```sh
   rc offerings set-current ofrng07ce9e2214 --project-id proj682b16be --yes --json --no-input
   ```

3. 審査が通ったら、公開の前に閉じ直す。解放するまで次の操作でストアの利用者に購入画面を出さない

   ```sh
   rc offerings set-current ofrngd8f9737dda --project-id proj682b16be --yes --json --no-input
   ```

4. 閉じ直した後にバージョンを手動で公開する

## 解放

1. 無料の生成を 1 日 3 回にする PR をマージしてデプロイする (`functions/src/generation/pipeline.ts` の `DAILY_GENERATION_LIMIT_PER_USER`)
2. 生成チケットの offering を current にする。アプリの再リリースは要らない

   ```sh
   rc offerings set-current ofrng07ce9e2214 --project-id proj682b16be --yes --json --no-input
   ```

SDK は offering をキャッシュするため、端末に反映されるまで時間がかかることがある (未計測)。

## 閉じ直す

`ofrngd8f9737dda` を current に戻す。買ったチケットの残高は残り、生成に使える。
