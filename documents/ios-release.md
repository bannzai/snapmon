# iOS の配布と審査提出の手順

iOS のビルドは開発用の Mac では作らず、`.github/workflows/ios-deploy.yml` が GitHub Actions の macOS ランナーで作って App Store Connect (TestFlight) に上げる。課金の扱い (審査の間だけ購入画面を開く・公開の前に閉じ直す) は [generation-ticket-release.md](generation-ticket-release.md)「iOS の最初の提出」が正。

## ビルドを上げる

```sh
gh workflow run ios-deploy.yml --ref main
RUN_ID="$(gh run list --workflow ios-deploy.yml --limit 1 --json databaseId --jq '.[0].databaseId')"
gh run watch "$RUN_ID"
```

- ビルド番号は run の番号。別の値にする時は `-f build_number=<番号>` を付ける (同じバージョンの中で前より大きい値が要る)
- Upload to App Store Connect まで進んで失敗した run は Re-run しない (同じビルド番号の再送は拒否される)。原因を直して新しく起動する。それより前の step で失敗した run は Re-run してよい
- 署名は手動署名で、証明書 (チームで 1 枚を使い回す。1Password の vault `bannzai`) と provisioning profile `Snapmon.AppStore` (vault `snapmon`) を Secrets から復元する。Secrets の名前は `.env.1password.github-actions` に宣言し、bannzai/castle の onepassword-sync skill で写す
- profile の名前は workflow の `IOS_PROVISIONING_PROFILE_NAME` と一致させる。App ID の Capability (App Attest・Sign in with Apple・In-App Purchase) を変えた時と証明書を更新した時は、bannzai/castle の ios-deploy-actions skill の `signing-assets.sh create-profile --name Snapmon.AppStore --bundle-id com.bannzai.snapmon --certificate-id <証明書の ID> --out tmp/signing --entitlements ios/Runner/Runner.entitlements --recreate` で作り直し、1Password の item と Secret `IOS_PROVISIONING_PROFILE_BASE64` を更新する

## メタデータとスクリーンショットを送る

```sh
fastlane ios metadata_upload
```

`fastlane/metadata` と `fastlane/screenshots` を編集中のバージョンに送る。審査には提出しない。年齢制限の申告・審査情報 (連絡先と審査メモ)・App Privacy の回答は deliver が扱わないため、App Store Connect API と bannzai/castle の appstore-app-privacy skill で入れる。

## 審査に提出する

bannzai/castle の release-app skill の手順 (QA のゲート・提出の承認) に従い、`fastlane ios submit_for_review version:<版> build_number:<ビルド番号> dry_run:true` で状態を確かめてから `dry_run:true` を外して提出する。
