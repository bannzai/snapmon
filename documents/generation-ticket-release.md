# 生成チケットの解放の手順

生成チケットの課金は実装済みで閉じている。何を決めたかは [DIRECTION.md](DIRECTION.md)「決めたこと」2026-11-07 の #186 の行が正で、この文書は解放の時に打つ操作をまとめる。

RevenueCat の値は `revenuecat/config.json` が正で、生成チケットの offering は `ofrng07ce9e2214`、閉じている間の offering (package が無い) は `ofrngd8f9737dda`。

## 解放の前に揃えるもの

- App Store Connect のアプリのレコードと商品 2 つ (#183)。アプリのレコードの作成は Apple ID の認証が要る (`~/.claude/skills/appstore-in-app-purchase/references/api_endpoints.md`)
- Google Play Console の商品 2 つ (同じ識別子。`googleplay/iap/config.json` を `play_apply_config.sh` で適用。DRAFT で登録し、有効化は「解放」で行う)
- RevenueCat の app に App Store の In-App Purchase Key と Google Play のサービスアカウントを登録する
- RevenueCat の webhook を `revenueCatWebhook` に向ける (Authorization は Secret Manager の `REVENUECAT_WEBHOOK_AUTHORIZATION` と同じ値)

## ストアへ出すビルド

`lib/firebase/purchases.dart` は鍵の `--dart-define` が空のビルドで SDK を初期化しないため、鍵なしのビルドを出すと offering を切り替えても購入画面が出ず、再リリースが要る。iOS は `--dart-define=REVENUECAT_PUBLIC_API_KEY_IOS=<GitHub Variable の値>`、Android は `--dart-define=REVENUECAT_PUBLIC_API_KEY_ANDROID=<GitHub Variable の値>` を付けてビルドする。

Android の署名済みの AAB は `.github/workflows/build-android-release.yml` を `gh workflow run build-android-release.yml --ref main -f build_number=<versionCode>` で動かして artifact `android-aab` から取る (鍵を付けてビルドし、upload key で署名する。この Mac では flutter build を実行しない)。Play Console へのアップロードは人が行う。

## iOS の最初の提出

current の offering は project に 1 つで、iOS と Android の両方に効く (`revenuecat/config.json` の 1 つの project に両方の app がある)。Android を一般に公開していて Play の商品も有効なら、審査の間は Android の一般の利用者にも購入画面が出る。Play の商品 2 つは DRAFT (購入できない。`googleplay/iap/config.json` の `status: inactive`) で登録してある。Android の一般公開は、iOS の審査が通って閉じ直す (手順 4) まで待つ。Android が内部テストのトラックにしか無い間は一般の利用者がいないため、商品の有効化と sandbox の確認は審査の間に行える (手順 3 の後の「Android の sandbox の確認」)。

Apple は最初の消耗型の商品を新しいアプリのバージョンと一緒に提出するよう求める。出典: https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase (2026-11-07 に確認)。そのため最初のアプリの提出に商品を含めて審査を通す。

1. 提出の前に App Store Connect でリリースの方法を手動にする (自動だと、閉じ直す前に公開されて利用者に購入画面が出ることがあるため)。App Store Connect の選択肢は「Manually release this version.」。出典: https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/ (2026-11-07 に確認)
2. App Review の notes に購入画面への着き方を書く。購入画面は 1 日の無料の生成回数を使い切った後にしか出ず (今は 20 回。`functions/src/generation/pipeline.ts` の `DAILY_GENERATION_LIMIT_PER_USER`)、同じ写真の組の結果は使い回されるので回数が進まない (`users/{uid}/generationAliases`)。別々の写真が要ることを書く。審査の担当者の手間を減らすために先に無料の回数を減らすかは、提出の時に決める
3. 審査の間だけ生成チケットの offering を current にする (審査の担当者が購入の経路を見られるようにするため)

   ```sh
   rc offerings set-current ofrng07ce9e2214 --project-id proj682b16be --yes --json --no-input
   ```

   Android の sandbox の確認 (offering が current のこの間に行う。Android の `one_time` の商品を 2 回続けて買えるか (消耗型として扱われるか) を確かめる。未確認)。DRAFT の商品はライセンステスターも買えない ("You must publish your one-time products and subscriptions before they can be tested." 出典: https://support.google.com/googleplay/android-developer/answer/6062777 、2026-11-08 に確認) ため、先に有効にする
   1. Google Play の商品 2 つを有効にする (下の「解放」の 1 と同じコマンド。有効化は取り消せるが、有効にした商品は DRAFT には戻らず INACTIVE になる。出典: Play Developer API v3 の purchase option の `state` "INACTIVE: The purchase option is not available to users anymore." https://developers.google.com/android-publisher/api-ref/rest/v3/monetization.onetimeproducts 、2026-11-08 に確認)
   2. Play Console の「設定」→「ライセンステスト」に確認用の Google アカウントを登録する (同じ出典: "authorized users can also purchase one-time products and subscriptions without charging their accounts")。Web UI でしか登録できない
   3. 内部テストのトラックの AAB (上の「ストアへ出すビルド」) をそのアカウントの端末に入れ、無料の回数を使い切った後の購入画面から同じ商品を 2 回続けて買い、残高が 2 回分増えることを確かめる。結果をこの文書の上の「未確認」に書き換える

4. 審査が通ったら、公開の前に閉じ直す。解放するまで次の操作でストアの利用者に購入画面を出さない (Play の商品は有効のままでよい。current の offering に package が無ければアプリは購入画面を出さない)

   ```sh
   rc offerings set-current ofrngd8f9737dda --project-id proj682b16be --yes --json --no-input
   ```

5. 閉じ直した後にバージョンを手動で公開する

## 解放

先に商品を買える状態にしてから offering を切り替える。逆の順だと、買えないのに無料の回数だけ減る時間ができる。

1. Google Play の商品 2 つを有効にする (DRAFT で登録してあるため。「iOS の最初の提出」の sandbox の確認で有効にしていれば何も変わらない。App Store の商品は審査で承認済みのものを使うので操作は無い)

   ```sh
   op run --env-file .env.1password -- bash ~/.claude/skills/googleplay-in-app-purchase/scripts/play_otp_set_state.sh snapmon_generationticket10_200yen buy activate
   op run --env-file .env.1password -- bash ~/.claude/skills/googleplay-in-app-purchase/scripts/play_otp_set_state.sh snapmon_generationticket30_500yen buy activate
   ```

2. 生成チケットの offering を current にする。アプリの再リリースは要らない

   ```sh
   rc offerings set-current ofrng07ce9e2214 --project-id proj682b16be --yes --json --no-input
   ```

3. SDK は offering をキャッシュするため、端末に反映されるまで時間がかかることがある (未計測)。反映を確かめる
4. 無料の生成を 1 日 3 回にする PR をマージしてデプロイする (`functions/src/generation/pipeline.ts` の `DAILY_GENERATION_LIMIT_PER_USER`)

解放の前に、「iOS の最初の提出」の「Android の sandbox の確認」を済ませておく。

## 閉じ直す

解放の逆の順で戻す。先に上限を戻さないと、無料の 3 回を使い切った後に買えない時間ができる。

1. 無料の生成を 1 日 20 回に戻す PR をマージしてデプロイする (`functions/src/generation/pipeline.ts` の `DAILY_GENERATION_LIMIT_PER_USER`。閉じている間は 20 回。DIRECTION.md 2026-11-07 の #182 の行)
2. `ofrngd8f9737dda` を current に戻す。買ったチケットの残高は残り、生成に使える

   ```sh
   rc offerings set-current ofrngd8f9737dda --project-id proj682b16be --yes --json --no-input
   ```
