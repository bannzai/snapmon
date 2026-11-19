# 生成チケットの解放の手順

生成チケットの課金は実装済みで閉じている。何を決めたかは [DIRECTION.md](DIRECTION.md)「決めたこと」2026-11-07 の #186 の行 (Web 版の販売は 2026-11-19 の #371 の行) が正で、この文書は解放の時に打つ操作をまとめる。

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

## Web 版で売る準備

Web 版は、同じ offering の package を RevenueCat の Web での販売の機能 (RevenueCat Billing。決済は Stripe) で売る (DIRECTION.md 2026-11-19 の #371 の行)。アプリと webhook は実装済みで、次が済むまで Web 版に購入の画面は出ない。Stripe の接続のように bannzai にしかできない作業の手順と、接続の後に agent が進める作業の分担は https://github.com/bannzai/snapmon/issues/375 にある。

1. Firebase Authentication で Google のサインインを有効にし、Web 版のドメイン (`play.snapmonster.app`) が Authentication の承認済みドメインにあることを確かめる。Web 版で買えるのは Google と連携済みのアカウントだけで、2026-11-19 の時点では snapmon-prod の Google のサインインが有効になっておらず、連携ができない (documents/adr/0003-account-link-and-deletion.md の「確かめていないこと」。有効化は [ユーザー作業の一覧](https://github.com/bannzai/snapmon/issues/3) にある)
2. Stripe のアカウントを作り、RevenueCat に接続する ( https://www.revenuecat.com/docs/web/connect-stripe-account )
3. RevenueCat の project `proj682b16be` に Web の設定 (RevenueCat Billing の app) を作る (RevenueCat の API v2 の app の種類に `rc_billing` があるが、API で作れるかは確かめていない。 https://www.revenuecat.com/docs/api-v2/product の App の定義、2026-11-19 に確認)。既定の通貨は日本円にする (既定の通貨は app の設定で選び、利用者の地域の通貨の値段が無い時に使われる。 https://www.revenuecat.com/docs/web/web-billing/multi-currency-support )
4. Web の商品 5 つを RevenueCat のダッシュボードで作る (種類は Consumable。Web の商品は API では作れない。API v2 の「Create a product」の警告: 「This endpoint does not allow to create Web Billing products.」 https://www.revenuecat.com/docs/api-v2/product 、2026-11-19 に確認)。ID は、アプリの商品の ID の末尾に `_web` を付ける (webhook とアプリが末尾の `_web` を外してアプリの商品として読む。`functions/src/generation_tickets.ts` の `WEB_PRODUCT_ID_SUFFIX`)。値段は保存した後に変えられない (「Once you've saved the product, it's only possible to add prices for new currencies, and not edit existing ones.」 https://www.revenuecat.com/docs/web/web-billing/product-setup 、2026-11-19 に確認)

   | Web の商品の ID | 値段 | 足す package (offering `generation_tickets`) |
   | --- | --- | --- |
   | `snapmon_generationticket10_200yen_web` | 200 円 | `ticket10` |
   | `snapmon_generationticket30_500yen_web` | 500 円 | `ticket30` |
   | `snapmon_actioncardrank1_100yen_web` | 100 円 | `actioncard_rank1` |
   | `snapmon_actioncardrank2_300yen_web` | 300 円 | `actioncard_rank2` |
   | `snapmon_actioncardrank3_500yen_web` | 500 円 | `actioncard_rank3` |

5. Web の設定の public API key (公開値) を GitHub の Variable `REVENUECAT_PUBLIC_API_KEY_WEB` に登録し、Web 版をビルドする workflow (`.github/workflows/deploy-hosting.yml`・`.github/workflows/browser-session.yml` の `flutter build web`) に `--dart-define=REVENUECAT_PUBLIC_API_KEY_WEB=<Variable の値>` を足す。手元の `make web`・`make build-web` とエディタの実行 (`make dart-defines-file`) は、Variable を登録すれば Makefile が読んで渡す (workflow を直す必要は無い)。鍵を渡していない Web のビルドは SDK を初期化せず、購入の画面を出さない。Web の鍵には本番用と試験用 (sandbox) がある (「If your connected Stripe account doesn't have access to live mode, only RevenueCat sandbox purchases can be made (only sandbox API keys and web purchase links will be available)」「RevenueCat will automatically use Stripe's test mode for sandbox web purchase links and web SDK purchases」 https://www.revenuecat.com/docs/web/connect-stripe-account 、2026-11-19 に確認)。Variable と本番のビルドに入れるのは本番用の鍵だけにし、試験用の鍵を入れたビルドを本番にデプロイしない
6. `docs/SpecifiedCommercialTransactions.md` (特定商取引法に基づく表記) と `docs/Terms.md` 第4条の2 の Web の販売条件 (返品・キャンセル・返金に応じない等) を owner が読んで確かめる
7. Apple Pay・Google Pay を決済の画面に出す時は、Stripe に Web 版のドメイン (`play.snapmonster.app`) を登録する (「You only need to register a domain manually in Stripe if you're initiating purchases with the Web SDK on your own domain.」 https://www.revenuecat.com/docs/web/web-billing/payment-methods 、2026-11-19 に確認)
8. Stripe の sandbox の購入で次を確かめる (どれも未確認。実際の購入は Stripe の接続が前提のため、実装の時には確かめていない)。試験用の鍵を渡したビルドで行う (手元なら `REVENUECAT_PUBLIC_API_KEY_WEB=<試験用の鍵> make web`。Makefile は環境変数を Variable より優先する)。連携を通すには、ビルドを開くドメインが Firebase Authentication の承認済みドメインにあることが要る (2026-11-19 の webtunnel の確認では `localhost` で `[firebase_auth/unauthorized-domain]` になった)。確認には検証用のアカウントを使い、確認の後に設定の「アカウントを削除」で消す (webhook は `environment` を記録するだけで、`SANDBOX` の購入も本番の残高に足すため。`functions/src/generation_tickets.ts`)
   - 最初の購入で、webhook に届いたイベントの `environment` が `SANDBOX` であること (Slack の通知の「環境 SANDBOX」) を確かめる。`PRODUCTION` なら本番用の鍵で実際の支払いをしているため、そこで止める
   - 匿名のままでは連携の案内が出て、Google と連携すると決済の画面に進む
   - 購入の後、webhook に `NON_RENEWING_PURCHASE` が `store: RC_BILLING`・Web の商品の ID で届き、生成チケットの残高が増える・Action Card の技を受け取れる
   - 同じ商品を 2 回続けて買える (消耗型として扱われる)
   - 決済の画面を閉じた時に、エラーの表示にならず購入の画面に戻る
   - RevenueCat のダッシュボードから返金した時に `CANCELLATION` が届き、Slack に知らせが出る
   - 決済の画面 (申込みの最終確認の画面) の表示が、特定商取引法 第12条の6 の求める事項 (分量・価格・支払いの時期と方法・提供の時期・解除に関する事項) を満たす。画面は RevenueCat が用意するため、足りない時は RevenueCat の設定で足せるかを調べる

current の offering は project に 1 つで、Web の設定にも効く。そのため、Web 版で売り始める切り替えは「Web の鍵を渡したビルドのデプロイ」と「offering `generation_tickets` が current であること」の両方が揃った時で、片方だけでは Web 版に購入の画面は出ない。2026-11-17 から、App Store の審査のために current を `generation_tickets` にし、`config/features.actionCardsVisible` を true にしている ( https://github.com/bannzai/snapmon/issues/3 の 2026-11-17 のコメント)。この間に Web の鍵を渡したビルドをデプロイすると、その時点で Web 版にも購入の画面が出るため、デプロイは上の 8 の確認と bannzai の確認の後に行う。Web の商品を package に足していない間に Web 版の SDK がその package を返すかは未確認のため、デプロイは上の 4 より後にする。

## 閉じ直す

解放の逆の順で戻す。先に上限を戻さないと、無料の 3 回を使い切った後に買えない時間ができる。

1. 無料の生成を 1 日 20 回に戻す PR をマージしてデプロイする (`functions/src/generation/pipeline.ts` の `DAILY_GENERATION_LIMIT_PER_USER`。閉じている間は 20 回。DIRECTION.md 2026-11-07 の #182 の行)
2. `ofrngd8f9737dda` を current に戻す。買ったチケットの残高は残り、生成に使える

   ```sh
   rc offerings set-current ofrngd8f9737dda --project-id proj682b16be --yes --json --no-input
   ```
