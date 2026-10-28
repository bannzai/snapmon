# App Privacy とデータセーフティの回答

App Store の App Privacy (`fastlane/app_privacy_details.json`) と Google Play のデータセーフティの回答の根拠。回答の正は App Store 側が `fastlane/app_privacy_details.json`、Google Play 側がこの文書の「Google Play のデータセーフティ」の節で、Play Console の Web UI への入力はユーザー作業 (#3) で行う。

収集の実態を変える変更 (SDK の追加、Analytics に `setUserId` を呼ぶ、広告 SDK の追加等) をした時は、両方の回答と `docs/PrivacyPolicy.md` を同じ PR で直す。App Store の回答とポリシーの食い違いは `bash ~/.agents/skills/appstore-app-privacy/scripts/check-app-privacy-consistency.sh --privacy-json fastlane/app_privacy_details.json --policy docs/PrivacyPolicy.md` で確かめる。

## 収集するデータと出どころ

| データ | 出どころ (実装) | App Store の種別 | 用途 | ユーザーに紐付くか |
| --- | --- | --- | --- | --- |
| 撮影・選択した写真 | `lib/firebase/monster_generation.dart` が Storage の `users/{uid}/photos/{requestId}` に送る | Photos or Videos | App Functionality | 紐付く (uid のパスに置く) |
| 生成したモンスター・手持ち・バトルの記録 | Firestore の `users/{uid}/monsters`・`party/current`・`battles` (`.claude/rules/firestore.md`) | Gameplay Content | App Functionality | 紐付く |
| 表示名・通報の内容 | Functions の setDisplayName が `users/{uid}.displayName` に、reportMonster が `reports/{reporterUid}_{monsterId}` に書く | Other User Content | App Functionality | 紐付く |
| Firebase Authentication の uid | 匿名ログイン (`lib/firebase/session.dart`)。PvP の通報・ブロックの宛先にも使う | User ID | App Functionality | 紐付く |
| メールアドレス・名前 | Apple / Google の連携 (`lib/firebase/account.dart`) で、プロバイダが渡した値を Firebase Authentication がユーザーに保存する | Email Address・Name | App Functionality | 紐付く |
| 利用状況のイベント | Google Analytics for Firebase (`lib/analytics/analytics_events.dart`) | Product Interaction | Analytics | 紐付かない |
| アプリインスタンス ID | Google Analytics for Firebase が自動で割り当てる | Device ID | Analytics | 紐付かない |
| IP アドレスから推定したおおまかな地域 | Google Analytics for Firebase | Coarse Location | Analytics | 紐付かない |
| クラッシュ情報 | Firebase Crashlytics | Crash Data | App Functionality | 紐付かない |

トラッキング (`DATA_USED_TO_TRACK_YOU`) は申告しない。広告 SDK・IDFA を使わず (`docs/PrivacyPolicy.md`「広告」)、Analytics にユーザー ID を設定しない (`lib/` に `setUserId` の呼び出しが無い)。

### 判断の根拠

- Analytics と Crashlytics を「紐付かない」にした理由: アプリは Analytics の `setUserId` も Crashlytics の `setUserIdentifier` も呼ばない (2026-10-26 に `rg -n "setUserId|setUserIdentifier" lib` で 0 件)。Google は「By default, this identifier is not associated with a user identifier, like screen name or account ID」とする <!-- source: https://support.google.com/analytics/answer/10285841 (2026-10-26 に確認) -->
- Device ID と Coarse Location を申告する理由: Google は「An app instance id is automatically assigned to each instance of an app」「Analytics derives general location data from users’ masked IP addresses」とする <!-- source: https://support.google.com/analytics/answer/10285841 (2026-10-26 に確認) -->。申告しない方が実態より少なく見えるため、申告する方に倒した
- Crash Data: Crashlytics は「Collects stack traces and relevant application state when an application crashes」「Collects device and OS information to assist with debugging crashes」 <!-- source: https://firebase.google.com/docs/ios/app-store-data-collection (2026-10-26 に確認) -->
- User ID: Firebase Authentication は「Generates and stores identifiers for user authentication purposes」 <!-- source: https://firebase.google.com/docs/ios/app-store-data-collection (2026-10-26 に確認) -->
- Email Address・Name: アプリはメールアドレスと名前を読まないが、連携のたびにプロバイダが渡した値を Firebase Authentication がユーザーに保存し得る。Apple は初回のサインインで表示名を渡し、転送用のメールアドレスを発行する (`docs/PrivacyPolicy.md` の脚注 authprovider の出典)。Google の提供範囲は未確認のため、渡されるものとして申告した
- App Check の DeviceCheck / App Attest のトークンは、正規のアプリからの呼び出しかの検証にだけ使い、保存しない (Firebase の説明は「collects both the attestation object and the assertion object」「collects the `DCDevice` token」)。Apple の Device ID の定義はアプリ・端末を識別する ID を指し、これらの検証用のトークンは当たらないと判断した (仮説。Apple の定義の文言で確かめていない)

## Google Play のデータセーフティ

Play の「収集」は端末の外に送ることを指し、「共有」は第三者への移転を指す。サービス提供者 (処理を委託した先) への移転と、ユーザーの明示的な操作による移転は「共有」に当たらない <!-- source: https://support.google.com/googleplay/android-developer/answer/10787469 「"Sharing" refers to transferring user data collected from your app to a third party」、例外に service provider と「Transferring user data to a third party based on a specific user-initiated action」(2026-10-26 に確認) -->。写真を送る Cloud Vision API・Claude API・Jev は生成の処理の委託先のため、共有に当たらないと判断した。

### 回答

| 質問 | 回答 |
| --- | --- |
| 必須のユーザーデータを収集・共有するか | はい (収集する。共有しない) |
| すべてのユーザーデータを転送時に暗号化するか | はい (Firebase・Cloud Functions への通信は HTTPS) |
| ユーザーがデータの削除をリクエストできるか | はい。アプリの「設定」→「アカウントを削除」と、 https://bannzai.github.io/snapmon/AccountDeletion |
| アカウントの作成 | 匿名ログインで自動作成。Apple / Google の連携は任意 |
| アカウント削除の URL | https://bannzai.github.io/snapmon/AccountDeletion |

### データの種類ごとの回答

すべて「共有」はしない。「収集」の欄は次のとおり。

| Play のデータの種類 | 収集 | 処理は一時的か | 必須か任意か | 目的 |
| --- | --- | --- | --- | --- |
| 個人情報: 名前 | する | いいえ | 任意 (連携した時だけ) | アカウント管理 |
| 個人情報: メールアドレス | する | いいえ | 任意 (連携した時だけ) | アカウント管理 |
| 個人情報: ユーザー ID | する | いいえ | 必須 | アプリの機能、アカウント管理、不正行為の防止とセキュリティ (通報・ブロック) |
| 写真と動画: 写真 | する | いいえ | 必須 (モンスターの生成に要る) | アプリの機能 |
| アプリのアクティビティ: アプリの操作 | する | いいえ | 必須 | 分析 |
| アプリのアクティビティ: その他のユーザー作成コンテンツ (モンスター・表示名・通報) | する | いいえ | 必須 | アプリの機能、不正行為の防止とセキュリティ |
| アプリの情報とパフォーマンス: クラッシュログ | する | いいえ | 必須 | 分析 |
| アプリの情報とパフォーマンス: 診断 (端末の種類・OS のバージョン) | する | いいえ | 必須 | 分析 |
| デバイスやその他の ID | する | いいえ | 必須 | 分析 |
| 位置情報: おおよその位置情報 | する (IP アドレスから推定) | いいえ | 必須 | 分析 |

Analytics と Crashlytics はログインと同時に有効にし、オプトアウトの設定は無いため「必須」とした (`lib/firebase/session.dart` の `setAnalyticsCollectionEnabled(true)`)。
