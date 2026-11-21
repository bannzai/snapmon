# 0003. 引き継ぎは匿名アカウントへの連携で行い、別の端末で連携済みなら端末の図鑑を捨てて切り替える。削除は Functions が行う

## Status

Accepted

## Context

[ADR 0001](0001-tech-stack.md)「認証」の行は、匿名ログインで始め、引き継ぎは Sign in with Apple / Google へのアカウントリンクで行うとした。アカウント連携の issue (#17) は、次の 2 つを agent が決めて本 ADR に書くとした。

- 連携しようとした Apple / Google のアカウントが、別の端末で既に連携済みの時の扱い。その端末の匿名アカウントの図鑑を捨てるか、連携済みのアカウントに合流させるか
- アカウント削除の手順 (Functions `deleteAccount`)。消す範囲は [docs/AccountDeletion.md](../../docs/AccountDeletion.md) に合わせる

連携済みのアカウントがある時に匿名アカウントへリンクしようとすると、Firebase Authentication は `credential-already-in-use` で失敗する (https://firebase.google.com/docs/auth/flutter/account-linking の `case "credential-already-in-use"`)。firebase_auth 7.0.0 の iOS・Android の plugin と Web の実装は、この失敗に連携済みのアカウントの credential を付けて返す (iOS: `AuthErrors.swift` が `AuthErrorUserInfoUpdatedCredentialKey` を、Web: `web_utils.dart` が `OAuthProviderJsImpl.credentialFromError` を読む)。Web の Apple の credential は、元の nonce が無くサインインに使えないと分かる時があり、その時は credential を使わずに Apple のサインインを出し直して切り替える (下の「Android と Web の Sign in with Apple の連携」の「Web の Apple が連携済みの時」)。

## 比べた選択肢

| 選択肢 | 実装 | 壊れ方 |
| --- | --- | --- |
| **端末の匿名アカウントを捨てて、連携済みのアカウントに切り替える (採用)** | 確認ダイアログで消える体数を示してから、匿名アカウントを `deleteAccount` で消し、連携済みのアカウントにサインインする | 確認したうえで端末の図鑑が消える。合流の不整合は起きない |
| 匿名アカウントの図鑑を、連携済みのアカウントに合流させる | モンスター・生成のレコード・絵 (`monsters/{monsterID}/art.png`)・バトルの記録を別の uid に移す Functions が要る。同じ被写体の二重登録の判定 (ADR 0001「同じ被写体の判定」) を合流の時にもやり直す必要がある | 合流で同じ被写体が 2 体になる、移している途中で落ちると両方に半端に残る |
| 切り替えず、匿名アカウントを残したまま連携をやめる | 何もしない | 機種変更した人が前の図鑑に戻れず、引き継ぎの目的を満たさない |

## Decision

| 項目 | 決定 | 根拠 |
| --- | --- | --- |
| 連携先 | iOS・Android・Web のどれでも、Sign in with Apple と Google から利用者が選ぶ。iOS はどちらも `linkWithProvider` (`AppleAuthProvider()`・`GoogleAuthProvider()`)。Android は Apple が `linkWithProvider(AppleAuthProvider())`、Google が google_sign_in の ID トークンを `linkWithCredential`。Web はどちらも `linkWithPopup` | iOS の Google は #370 (下の「iOS の Google の連携」)、Android と Web の Apple は #374 (下の「Android と Web の Sign in with Apple の連携」) で足した。Android で Google にサインインするには google_sign_in のような外部のライブラリが要る (https://firebase.google.com/docs/auth/flutter/federated-auth "On native platforms, a 3rd party library is required to trigger the authentication flow") |
| 連携済みのアカウントへの 2 つ目の連携 | 足さない。どれかと連携済みの時は「データを引き継ぐ」を押せない (#17 のまま) | 連携済みのアカウントから 2 つ目を選んで別の端末で連携済みだった時、切り替えの流れは連携済みの図鑑を消すことになる。切り替えは匿名アカウントだけを捨てる前提で決めた (上の比較) |
| 別の端末で連携済みの時 | 端末の匿名アカウントを捨てて、連携済みのアカウントに切り替える。切り替える前に、消える図鑑の数を示して確かめる。credential を受け取れなかった時は何も消さずにエラーを出す | 上の比較。合流は不整合の起き方が多く、引き継ぎの用途 (機種変更した人が前の図鑑に戻る) では新しい端末の図鑑は少ない |
| 捨てた後のサインインの失敗 | ログインを終え、新しい匿名アカウントから始め直す | 連携済みのアカウントはサーバーに残るため、もう一度「データを引き継ぐ」を選べば切り替えられる |
| 削除の主体 | Functions `deleteAccount` が Admin SDK で消す。クライアントは最近のログインを求められない | クライアントの `User.delete()` は最近のログインを求める (https://firebase.google.com/docs/auth/web/manage-users "To delete a user, the user must have signed in recently")。Admin SDK にこの制約は無く、Firestore・Storage のデータと一緒に消せる |
| 削除の順 | Storage → 本人の通報・ブロック → `users/{uid}` のサブコレクション → Auth → `users/{uid}`。始める時に `users/{uid}` に `accountDeletionStartedAt` を付け、付いている間は生成を受け付けない。生成中ロックが期限内の時は断る | Auth を消すまでに失敗しても、もう一度呼べば続きから消せる (冪等)。印を最後まで残し、削除の途中に生成がモンスターを書いて残さない |
| Storage の消し残し | 消すのに失敗したら、消すパス (`users/{uid}/` と、Firestore を消すと引けなくなる絵のパス) を持つタスク (`deleteAccountFiles`) を Cloud Tasks に積んでから先へ進む | ADR 0001「画像ストレージ」の「消せなかった分は Cloud Tasks の再試行で消す」と、docs/AccountDeletion.md の「一部の写真は、削除に失敗した場合に再試行する」 |
| Sign in with Apple の取り消し | iOS で Apple と連携している時は、削除の前に Apple のサインインをもう一度求め、受け取った認可コードで `revokeTokenWithAuthorizationCode` を呼ぶ | 認可コードは Apple のサインインの結果にだけ入る (https://firebase.google.com/docs/auth/flutter/federated-auth "Apple sign-in on Apple platforms returns an authorization code that can be used to revoke the Apple auth token")。firebase_auth 7.0.0 の iOS の plugin は再認証の結果にも認可コードを入れる (`FLTFirebaseAuthPlugin.swift` の `isReauthenticatingWithApple` の分岐)。Android と Web で Apple と連携済みのアカウントを削除する時 (#374 で起きるようになった) は、取り消さずに削除する。firebase_auth 7.0.1 の Android の plugin の `revokeTokenWithAuthorizationCode` は何もせずに成功を返し (`FlutterFirebaseAuthPlugin.kt`)、firebase_auth_web 6.3.2 は `UnimplementedError('revokeTokenWithAuthorizationCode() is only available on apple platforms.')` を投げるため、iOS と同じ手段が無い。Apple の側の記録は利用者が Apple のアカウントの設定から消せ、その手順を docs/AccountDeletion.md に書く (Apple の TN3194 は、トークンが無い時もアカウントの削除は行い、利用者を手動の取り消しに案内するとしている。https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple "If you don’t have the user’s refresh token, access token, or authorization code, you must still fulfill the user’s account deletion request"、2026-11-19 に確認) |

## iOS の Google の連携 (#370、2026-11-19)

Web 版か Android で Google と連携した人が iPhone のアプリで図鑑を引き継げるよう、iOS の連携先に Google を足した。iPhone のアプリに他社のサインインを出す時は Sign in with Apple も出す必要があるため (App Store Review Guidelines 4.8)、Apple は残して 2 つから選ぶ。

| 選択肢 | 要るもの | 判断 |
| --- | --- | --- |
| **firebase_auth の `linkWithProvider(GoogleAuthProvider())` (採用)** | Info.plist の URL scheme 1 つ (`app-` + Firebase の iOS アプリの ID の `:` を `-` に替えたもの)。iOS の OAuth クライアントは要らない | Firebase Authentication で Google のサインインを有効にすれば動く見込みで、有効化は Web と Android の連携にも要る作業 ([ユーザー作業の一覧](https://github.com/bannzai/snapmon/issues/3)) |
| google_sign_in の ID トークンを `linkWithCredential` (Android と同じ) | iOS の OAuth クライアントの ID (`GIDClientID` か `GoogleService-Info.plist` の `CLIENT_ID`) と、その逆順の URL scheme | 2026-11-19 の時点で snapmon-prod に iOS の OAuth クライアントが無い (`firebase apps:sdkconfig IOS` の結果に `CLIENT_ID`・`REVERSED_CLIENT_ID` が無い)。Google を有効にした後で `GoogleService-Info.plist` を作り直し、Secret を更新する作業が足される |

ソースで確かめたこと (firebase_auth 7.0.1 の iOS の plugin と、firebase_core 5.1.0 が SwiftPM で固定する firebase-ios-sdk 13.1.1。CocoaPods で固定する 12.19.3 は `OAuthProvider.swift` だけを読み、下の 2 つ目と 3 つ目が同じことを確かめた):

- plugin の `linkWithProvider` (`FLTFirebaseAuthPlugin+User.swift`) は、Apple 以外の provider を `OAuthProvider(providerID:)` にして `currentUser.link(with:uiDelegate:)` に渡す
- `OAuthProvider.init(providerID:)` (`FirebaseAuth/Sources/Swift/AuthProvider/OAuthProvider.swift`) が `fatalError` で断るのは Facebook と Apple だけで、`google.com` は断らない
- 同じ `init` は、ブラウザの画面からアプリに戻る URL scheme を、逆順のクライアント ID が Info.plist に登録されていればそれ、無ければ `app-` + `GOOGLE_APP_ID` の `:` を `-` に替えたものにする。この scheme が Info.plist に無いと、サインインを始めた時に `fatalError("Please register custom URL scheme ...")` でアプリが落ちる。そのため Info.plist に登録し、`firebase.json` のアプリの ID と食い違うと落ちるテスト (`test/firebase/account_link_url_scheme_test.dart`) を置いた
- 連携できた時の結果には credential が入り (`UserProfileUpdate.swift` の `link(user:with:)` が `OAuthCredential(withVerifyAssertionResponse:)` を付ける)、plugin はそれを受けて完了を Dart に返す
- そのサインインが別のアカウントに連携済みの時 (サーバーの `FEDERATED_USER_ID_ALREADY_LINKED`)、SDK は失敗に連携済みのアカウントの credential を付け (`AuthBackend.swift`・`AuthErrorUtils.swift` の `credentialAlreadyInUseError`)、plugin が `AuthErrorUserInfoUpdatedCredentialKey` から読んで Dart の `FirebaseAuthException.credential` に渡す (`AuthErrors.swift`)。上の「別の端末で連携済みの時」の切り替えは、この credential でサインインする

確かめていないこと: 実際の Google のアカウントでの連携と、連携済みのアカウントへの切り替え。2026-11-19 の時点で snapmon-prod の Firebase Authentication は Google も Apple もサインインを有効にしておらず (Identity Toolkit の `defaultSupportedIdpConfigs/google.com`・`apple.com` がどちらも 404 `CONFIGURATION_NOT_FOUND`)、iOS・Android・Web のどの連携も端から端までは動かせない。Firebase の文書がネイティブの Google のサインインに案内しているのは google_sign_in で (上の「連携先」の行の引用)、`linkWithProvider` での Google が通ることは上のソースの読みだけが根拠。有効化の後に実機で通らなければ、上の表の google_sign_in の案に切り替える。

## Android と Web の Sign in with Apple の連携 (#374、2026-11-19)

iPhone のアプリで Apple と連携した人が、Android のアプリか Web 版で同じ Apple を選んで図鑑を引き継げるよう、Android と Web の連携先に Sign in with Apple を足した。これで連携先は iOS・Android・Web のどれでも Apple と Google の 2 つになり、設定画面の「データを引き継ぐ」は 3 つとも #370 の下から出る一覧で選ぶ。

| プラットフォーム | 採った手段 | 設定に要るもの |
| --- | --- | --- |
| Android | `linkWithProvider(AppleAuthProvider())`。Apple のサインインの画面は Custom Chrome Tab で開く (https://firebase.google.com/docs/auth/android/apple "this will take control of your UI by opening a Custom Chrome Tab"、2026-11-19 に確認) | Apple の Services ID とサインイン用の鍵を Firebase Authentication に登録する。Firebase の Android アプリに署名の SHA-1 を登録する (同じ文書 "Specify your app's SHA-1 fingerprint if you haven't already.")。アプリのコード・manifest に足す設定は無い |
| Web | `linkWithPopup(AppleAuthProvider())` (Google と同じポップアップ) | 上と同じ Services ID の Return URL に Firebase の `__/auth/handler` を登録する |

設定は owner の作業で、手順は https://github.com/bannzai/snapmon/issues/375 の「Apple を有効にする」にある。

ソースで確かめたこと:

- Android (firebase_auth 7.0.1 の plugin。firebase_core 5.1.0 が固定する Firebase Android BoM は 35.1.0):
  - plugin の `linkWithProvider` (`FlutterFirebaseAuthUser.kt`) は、Dart の provider の ID (`apple.com`) をそのまま `OAuthProvider.newBuilder(providerId)` に渡し (`buildOAuthProvider`)、`startActivityForLinkWithProvider` を呼ぶ。Apple を断る分岐は無い
  - そのサインインが別のアカウントに連携済みの時、plugin は `FirebaseAuthUserCollisionException.updatedCredential` を保管して (`PigeonParser.parseAuthCredential` が `authCredentials` に置く)、その番号を Dart の `FirebaseAuthException.credential` に渡す (`FlutterFirebaseAuthPluginException.kt`、Dart 側は firebase_auth_platform_interface 9.1.2 の `method_channel/utils/exception.dart`)。`signInWithCredential` は番号から保管した credential を引き直す (`PigeonParser.getCredential`)。上の「別の端末で連携済みの時」の切り替えは、この credential でサインインする
  - FirebaseUI-Android 8.0.2 も、匿名アカウントへの provider での連携 (`startActivityForLinkWithProvider`) が衝突した時に同じ `getUpdatedCredential()` を使っている (`GenericIdpSignInHandler.java` の `handleAnonymousUpgradeFlow`)
- Web (firebase_auth_web 6.3.2。firebase_core_web 4.1.0 が読み込む Firebase JS SDK は 13.1.0):
  - `convertPlatformAuthProvider` (`web_utils.dart`) は `AppleAuthProvider` を JS SDK の `OAuthProvider('apple.com')` にして `linkWithPopup` に渡す
  - 連携が失敗した時、`getFirebaseAuthException` (`web_utils.dart`) は JS SDK の `OAuthProvider.credentialFromError` で credential を取り出し、`FirebaseAuthException.credential` に入れる

Web の Apple が連携済みの時:

- JS SDK がエラーから取り出す credential は `idToken`・`accessToken`・`nonce`・`pendingToken` を持ち (`packages/auth/src/core/providers/oauth.ts` の `oauthCredentialFromTaggedObject`)、サインインの要求は `pendingToken` があればそれだけを送る (`packages/auth/src/core/credentials/oauth.ts` の `buildRequest`)。firebase_auth_web は Dart の credential に移す時に `accessToken`・`secret`・`idToken` だけを写し、`pendingToken` と `nonce` を写さない (`web_utils.dart` の `getFirebaseAuthException`)。そのため、写した credential の `signInWithCredential` は nonce を付けずに ID トークンを送る
- ID トークンに nonce がある時は元の nonce が要る (firebase_auth_platform_interface の `OAuthCredential.rawNonce` の説明 "It is required when an ID token with a nonce field is provided")。この credential でサインインし直すと失敗する
- そこで、エラーの credential が「Apple・ID トークンの payload に `nonce` がある・元の nonce を持たない」の時 (`lib/firebase/account.dart` の `linkedAccountCredentialLacksNonce`) は、切り替えの確認までは同じに進め、端末の匿名アカウントを捨てた後に、credential を使い回さず `signInWithRedirect(AppleAuthProvider())` で Apple のサインインを出し直す。Apple の同じアカウントを選べば、連携済みのアカウントにサインインし直す。戻ってきたページの起動は Firebase のいまのユーザー (連携済みのアカウント) で始まる (`lib/firebase/session.dart`)。ID トークンに `nonce` が無い時は、今までどおり credential でサインインし直す (https://github.com/bannzai/snapmon/issues/380)
- ポップアップ (`signInWithPopup`) ではなく画面の遷移にしたのは、匿名アカウントを捨てる処理 (Functions の deleteAccount) を待った後に開くポップアップは、ボタンを押した直後の操作と扱われずブラウザに止められ得るため。捨てる順を後ろにする (先に入り直す) と、入り直した後は匿名アカウントが今のユーザーでなくなり、deleteAccount (呼び出したユーザー自身だけを消す) で消せない
- 遷移の先で利用者がやめた・失敗した時は、匿名アカウントは捨て済みのため、戻ったページは新しい匿名アカウントで始まる。捨てることは確認で利用者が選んでおり、連携済みの図鑑はサーバーに残るため、もう一度「データを引き継ぐ」で Apple を選べば切り替えられる (捨てた後のサインインの失敗の扱いは credential の時と同じ)。遷移の失敗のエラーは画面に出ない (戻ったページで `getRedirectResult` を読んでいないため)
- Web の Google の切り替え (#17) も同じ写し方を通るが、この判定の対象にしていない (#374 が変えていない経路。Google は ID トークンだけから credential を作る使い方を Firebase が文書にしている。https://firebase.google.com/docs/auth/flutter/federated-auth の `GoogleAuthProvider.credential(idToken: googleAuth.idToken)`、2026-11-19 に確認)
- iOS と Android の credential は ID トークンを持たず、ネイティブ側が持つ credential を番号で引き直すため、この判定に当たらない

確かめていないこと:

- **Web で Apple が連携済みの時に、実際の ID トークンが `nonce` を持つか**。持てば上のとおり Apple のサインインを画面の遷移で出し直し、持たなければ credential でサインインし直す。どちらになるかと、遷移から戻ったページが連携済みのアカウントで始まるか (firebase_auth_web が起動の時に遷移の結果をいまのユーザーに反映するか) は、実際のアカウントと許されたドメインの版 (play.snapmonster.app) でしか分からない
- 実際の Apple のアカウントでの、Android と Web の連携と切り替え。2026-11-19 の時点で snapmon-prod の Firebase Authentication は Apple のサインインを有効にしておらず (上の「iOS の Google の連携」の「確かめていないこと」)、Services ID も無いため、端から端までは動かせない。有効化の後に、上の太字の点を先に確かめる (リリース前の確認の一覧に移した)
- Web で、一覧を挟んだ後に Apple のポップアップが開くこと。動作確認に使う webtunnel は Web 版を `http://localhost:8080/` で開くが、snapmon-prod の Firebase Authentication が OAuth を許すドメインは `snapmon-prod.firebaseapp.com`・`snapmon-prod.web.app`・`play.snapmonster.app` の 3 つで localhost が無い (Identity Toolkit の `GET /admin/v2/projects/snapmon-prod/config` の `authorizedDomains`、2026-11-19)。そのため webtunnel で一覧の Apple を押すと、ポップアップに進む前に `[firebase_auth/unauthorized-domain] This domain is not authorized for OAuth operations for your Firebase project. Edit the list of authorized domains from the Firebase console.` が出る (2026-11-19 に debug ビルドで確かめた。エラーは画面の下にそのまま出て、アプリは落ちず、匿名アカウントのまま)。ポップアップが開くかと、Apple が有効でない時に Web で返るエラーは、許されたドメイン (play.snapmonster.app) に出した版でしか確かめられない。確かめたブラウザは webtunnel の Chromium だけで、Safari では確かめていない
- Android で、Custom Chrome Tab を開いている間にアプリのプロセスが止められた時の再開。plugin は `pendingAuthResult` を読まないため、その時は連携の結果を受け取れない (利用者はもう一度「データを引き継ぐ」を選ぶ)

## Consequences

- iPhone・Android・Web のどれで連携した人も、ほかのどれに移っても同じ Apple か Google を選んで図鑑を引き継げる。Web 版への Apple の引き継ぎで、連携済みのアカウントの ID トークンが nonce を持つ時は、切り替えの確認の後に Apple のサインインの画面がもう一度出る (上の「Web の Apple が連携済みの時」)
- Android のアプリか Web 版で Apple と連携済みのアカウントを削除した時は、Apple の側の記録 (「Apple でサインイン」を使っているアプリの一覧) が残る。利用者が Apple のアカウントの設定から消す (docs/AccountDeletion.md)
- 先に Apple と連携した人は、別の端末で Google と連携した図鑑に後から切り替えられず、逆も同じ (連携済みのアカウントに 2 つ目を足さないため)。アカウントを削除して匿名から始め直せば、もう一方を選べる
- 連携済みのアカウントへの切り替えでは、その端末で作ったモンスターは戻らない
- 削除が終わった後も、その uid の ID トークンは期限 (1 時間) まで通る (同じアカウントでサインインしている別の端末)。`generate` は最初に Auth のユーザーが残っているかを確かめ、消えていれば断ってその uid の `users/{uid}/` の配下のファイルを消す (`functions/src/account.ts` の `rejectDeletedAccount`)。バトルは図鑑のモンスターが無いと始められないため、削除の後にデータを作らない。Storage の Rules は Auth のユーザーの有無を見られないため、削除の後のその期限の間に、別の端末が写真を置いたまま `generate` を呼ばなかった時は、そのファイルを消す経路が無く残る
- 予約の切れた生成の再試行 (`resumeGeneration`) も、削除の印がある時と生成のレコードが消えた時は再開しない
