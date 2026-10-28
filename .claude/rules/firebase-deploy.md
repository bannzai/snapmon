# Firebase へのデプロイの認証

`.github/workflows/deploy-functions.yml` は、デプロイ用サービスアカウントの鍵を持たず、GitHub Actions の OIDC トークンを Workload Identity Federation で交換して認証する (bannzai の指示。2026-10-22。https://github.com/bannzai/snapmon/issues/32 )。provider・サービスアカウントの値は workflow の `google-github-actions/auth` の step を正とする。

- GCP 側の前提 (workflow が指す Workload Identity pool・provider、デプロイ用サービスアカウントへの `roles/iam.workloadIdentityUser`、workflow のヘッダーに書いたデプロイに要るロールと actAs) は owner 権限が要り、bannzai が `with-gcloud-owner` で /firebase-functions-deploy-iam-setup skill の手順に沿って整える
- provider の attribute condition がリポジトリ ID と environment `firebase-prod` を要求するため、OIDC で認証する job には `environment: firebase-prod` と `permissions: id-token: write` を付ける
- `.github/workflows/deploy-hosting.yml` も同じ provider・サービスアカウントで認証する (鍵の Secret `FIREBASE_SERVICE_ACCOUNT_BASE64` は一度も登録されず、鍵での実行は失敗していた。2026-10-28)
