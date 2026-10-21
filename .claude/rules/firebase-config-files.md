# Firebase の設定ファイルを git に入れない

`lib/firebase_options.dart`・`ios/Runner/GoogleService-Info.plist`・`android/app/google-services.json` は Google API キーを含むため、git の管理から外し `.gitignore` に入れている (GitHub の secret scanning の通報を受けて bannzai が決めた。2026-10-21)。

- 手元では、リポジトリのルートで次を実行して生成する。生成後、3 つのファイルの Storage のバケットを `snapmon-prod-storage` に直す (生成される既定のバケット `snapmon-prod.firebasestorage.app` はプロジェクトに無い)

  ```sh
  flutterfire configure --project=snapmon-prod --platforms=ios,android,web --ios-bundle-id=com.bannzai.snapmon --android-package-name=com.bannzai.snapmon --yes
  ```

- CI は、Flutter をビルドする前に `scripts/restore-firebase-config.sh` で GitHub Secrets (`FIREBASE_OPTIONS_DART_B64`・`GOOGLE_SERVICE_INFO_PLIST_B64`・`GOOGLE_SERVICES_JSON_B64`。各ファイルを base64 にした値) から書き出す。Flutter をビルドする workflow を足す時は、このスクリプトのステップも足す
- 3 つのファイルを作り直した時 (アプリの追加・キーの作り直し) は、Secrets も同じ内容で更新する (例: `base64 -i lib/firebase_options.dart | gh secret set FIREBASE_OPTIONS_DART_B64`)
- 3 つのファイルを commit しない。中身 (API キー) を PR 本文・issue・コメントに貼らない
