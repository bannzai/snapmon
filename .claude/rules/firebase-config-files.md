# Firebase の設定ファイルを git に入れない

`lib/firebase_options.dart`・`ios/Runner/GoogleService-Info.plist`・`android/app/google-services.json` は Google API キーを含むため、git の管理から外し `.gitignore` に入れている (GitHub の secret scanning の通報を受けて bannzai が決めた。2026-10-21)。

- 手元では、リポジトリのルートで次を実行して生成する。生成後、3 つのファイルの Storage のバケットを `snapmon-prod-storage` に直す (生成される既定のバケット `snapmon-prod.firebasestorage.app` はプロジェクトに無い)

  ```sh
  flutterfire configure --project=snapmon-prod --platforms=ios,android,web --ios-bundle-id=com.bannzai.snapmon --android-package-name=com.bannzai.snapmon --yes
  ```

- CI は、Flutter をビルドする前に `scripts/restore-firebase-config.sh` で GitHub Secrets (`FIREBASE_OPTIONS_DART_B64`・`GOOGLE_SERVICE_INFO_PLIST_B64`・`GOOGLE_SERVICES_JSON_B64`。各ファイルを base64 にした値) から書き出す。Flutter をビルドする workflow を足す時は、このスクリプトのステップも足す
- Web の動作確認 (webtunnel。`.github/workflows/browser-session.yml`) は、reusable workflow が caller の Secrets を `setup_command` へ個別に渡せないため、Secret `WEBTUNNEL_SETUP_ENV` (`FIREBASE_OPTIONS_DART_B64=<値>` の行と、任意で App Check の Web の debug token `FIREBASE_APPCHECK_DEBUG_TOKEN_WEB=<値>` の行を base64 にしたもの) を webtunnel が復号して `setup_command` に渡し、その先頭の `scripts/restore-firebase-config.sh dart` が書き出す。登録は、手元に `lib/firebase_options.dart` を生成した上で、リポジトリのルートで `bash scripts/set-webtunnel-setup-env-secret.sh` を実行する (GitHub Secrets は値を読み出せないため、`FIREBASE_OPTIONS_DART_B64` と同じ元のファイルから作る。値は画面に出ない)
- Web の App Check は、reCAPTCHA Enterprise のサイトキー (公開値。Variable `RECAPTCHA_ENTERPRISE_SITE_KEY`。`deploy-hosting.yml`・`browser-session.yml`・`make web` / `make build-web` が `--dart-define` で渡す) で動く。自動操作のブラウザ (webtunnel の Chromium) は reCAPTCHA のスコアが低く証明が通らないため、debug ビルドだけ debug token (`--dart-define=FIREBASE_APPCHECK_DEBUG_TOKEN_WEB`。発行と登録は `scripts/set-webtunnel-setup-env-secret.sh` のヘッダー) で代える。token は 1Password (vault `snapmon`、item `FIREBASE_APPCHECK_DEBUG_TOKEN_WEB`) が正で、手元の `make web` には `op run --env-file .env.1password -- make web` で渡す。リリースの成果物に埋め込まない
- 3 つのファイルを作り直した時 (アプリの追加・キーの作り直し) は、Secrets も同じ内容で更新する (例: `base64 -i lib/firebase_options.dart | gh secret set FIREBASE_OPTIONS_DART_B64`)。`lib/firebase_options.dart` を作り直した時は `bash scripts/set-webtunnel-setup-env-secret.sh` も実行し、`WEBTUNNEL_SETUP_ENV` を揃える
- 3 つのファイルを commit しない。中身 (API キー) を PR 本文・issue・コメントに貼らない

## Claude API の認証

Functions は Claude API の API キーを持たず、Workload Identity Federation で認証する (`functions/src/anthropic.ts`。根拠は ADR 0001 の「写真の理解と文章の生成」の行)。

- WIF の ID 4 つ (`ANTHROPIC_FEDERATION_RULE_ID`・`ANTHROPIC_ORGANIZATION_ID`・`ANTHROPIC_SERVICE_ACCOUNT_ID`・`ANTHROPIC_WORKSPACE_ID`) は秘密ではなく、`anthropic.ts` の定数に置いている。`GCLOUD_PROJECT` が snapmon-prod の時だけ使い、同名の環境変数があればそちらを優先する
- Emulator (`demo-snapmon`) とローカルでは 4 つを使わないため、Claude を呼ぶなら `ANTHROPIC_API_KEY` を環境変数で渡す。どちらも無ければクライアントの作成が throw する。キーをリポジトリに書かない
- federation rule は Functions の実行サービスアカウント `snapmon-functions@snapmon-prod.iam.gserviceaccount.com` の ID トークンだけを受け付ける。ロールの付与とデプロイ用サービスアカウントの actAs は owner 権限が要り、bannzai が `with-gcloud-owner` で付ける
- デプロイ後は `healthCheck` の `anthropicTokenExchange` が `ok` になることと、Claude Console の Workload identity の認証履歴に成功が残ることを確かめる
