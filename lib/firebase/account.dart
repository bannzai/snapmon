import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'session.dart';

// 匿名アカウントへの Apple / Google の連携 (引き継ぎ) と、アカウントの削除の Firebase の実体。
// 連携先はプラットフォームごとに 1 つ (iOS は Sign in with Apple、Android と Web は Google)。
// 別の端末で連携済みの時の扱いは documents/adr/0003-account-link-and-deletion.md。

/// このプラットフォームで連携に使うサインインの名前 (iOS は Apple、Android と Web は Google)。
String get accountLinkProviderNameForPlatform => _isIOS ? 'Apple' : 'Google';

bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Firebase の provider の ID ごとの、画面に出す名前。
const Map<String, String> _providerNamesById = {
  'apple.com': 'Apple',
  'google.com': 'Google',
};

/// いまのユーザーが連携済みのサインインの名前。匿名のままなら空。
List<String> linkedProviderNamesWithFirebase() => [
  for (final provider
      in FirebaseAuth.instance.currentUser?.providerData ?? <UserInfo>[])
    _providerNamesById[provider.providerId] ?? provider.providerId,
];

/// google_sign_in の初期化。アプリの中で 1 回だけ行う (google_sign_in の `initialize` の契約)。失敗したら次の呼び出しでやり直す。
Future<void>? _googleSignInInitialization;

/// Android で Google のアカウントを選んでもらい、Firebase の credential を返す。
Future<AuthCredential> _googleCredentialOnAndroid() async {
  try {
    await (_googleSignInInitialization ??= GoogleSignIn.instance.initialize());
  } catch (_) {
    _googleSignInInitialization = null;
    rethrow;
  }
  final account = await GoogleSignIn.instance.authenticate();
  return GoogleAuthProvider.credential(idToken: account.authentication.idToken);
}

/// いまの匿名アカウントに、このプラットフォームのサインイン ([accountLinkProviderNameForPlatform]) を連携する。uid は変わらない。
///
/// 連携できた時は null を返す。そのサインインが別の端末で連携済み (`credential-already-in-use`) の時は、連携済みのアカウントに
/// サインインする関数を返す (呼ぶ前に、いまの匿名アカウントを捨ててよいかを利用者に確かめるため、ここではサインインしない)。
/// 連携済みのアカウントの credential を受け取れなかった時と、それ以外の失敗は投げる。
Future<Future<String> Function()?> linkAccountWithFirebase() async {
  final user = FirebaseAuth.instance.currentUser!;
  AuthCredential? googleCredential;
  try {
    if (kIsWeb) {
      await user.linkWithPopup(GoogleAuthProvider());
    } else if (_isIOS) {
      await user.linkWithProvider(AppleAuthProvider());
    } else {
      googleCredential = await _googleCredentialOnAndroid();
      await user.linkWithCredential(googleCredential);
    }
    return null;
  } on FirebaseAuthException catch (error) {
    final credential = error.credential ?? googleCredential;
    if (error.code != 'credential-already-in-use' || credential == null) {
      rethrow;
    }
    return () => _signInToLinkedAccount(credential: credential);
  }
}

/// [credential] で連携済みのアカウントにサインインし、その uid を返す。
Future<String> _signInToLinkedAccount({
  required AuthCredential credential,
}) async =>
    (await FirebaseAuth.instance.signInWithCredential(credential)).user!.uid;

/// Functions の deleteAccount で、いまのアカウントのサーバーのデータと Auth のユーザーを消す。
/// 呼び出しが失敗しても、サーバーで消し終えていた (応答を受け取れなかった) 時は成功として返す
/// (削除済みの uid のまま残ると、連携・削除をやり直しても失敗し続けるため)。
Future<void> deleteCurrentAccountOnServerWithFirebase() async {
  try {
    await FirebaseFunctions.instanceFor(
      region: functionsRegion,
    ).httpsCallable('deleteAccount').call<Object?>();
  } catch (_) {
    if (await _isCurrentUserDeletedOnServer()) {
      return;
    }
    rethrow;
  }
}

/// いまのアカウントを消す (設定画面の「アカウントを削除」)。
///
/// iOS で Sign in with Apple を連携している時は、先に Apple のサインインをもう一度求め、受け取った認可コードで Apple のトークンを
/// 取り消す (Apple の要件。認可コードは再認証の結果にだけ入る。https://firebase.google.com/docs/auth/flutter/federated-auth の
/// "Apple sign-in on Apple platforms returns an authorization code that can be used to revoke the Apple auth token")。
/// その後に [deleteCurrentAccountOnServerWithFirebase] を呼ぶ。サインアウトは呼び出し側が行う。
///
/// 前の削除がサーバーで終わっていた (応答を受け取れなかった) 時は、何もせずに返す。再認証は消えたユーザーでは失敗し、
/// 削除をやり直してもログインの画面に戻れなくなるため。
Future<void> deleteAccountWithFirebase() async {
  if (await _isCurrentUserDeletedOnServer()) {
    return;
  }
  final user = FirebaseAuth.instance.currentUser!;
  if (_isIOS &&
      user.providerData.any((provider) => provider.providerId == 'apple.com')) {
    final authorizationCode = (await user.reauthenticateWithProvider(
      AppleAuthProvider(),
    )).additionalUserInfo?.authorizationCode;
    if (authorizationCode == null) {
      throw StateError('Apple の連携を取り消すための認可コードを受け取れませんでした');
    }
    await FirebaseAuth.instance.revokeTokenWithAuthorizationCode(
      authorizationCode,
    );
  }
  await deleteCurrentAccountOnServerWithFirebase();
}

/// いまのユーザーがこの端末から使えなくなったか (Auth から消えた)。ユーザーを読み直し、ユーザーが無い時のエラー
/// (`user-not-found`) か、読み直しの失敗で SDK がサインアウトした時 (Web の SDK はユーザーが無い時のエラーを
/// `user-token-expired` に変えてサインアウトする。firebase-js-sdk の packages/auth/src/api/errors.ts の
/// `[ServerError.USER_NOT_FOUND]: AuthErrorCode.TOKEN_EXPIRED`) だけを使えなくなったと扱う。通信の失敗などで読み直せず、サインインが
/// 続いている時は、ユーザーが残っていることがあるため使えると扱う。
Future<bool> _isCurrentUserDeletedOnServer() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return true;
  }
  try {
    await user.reload();
    return false;
  } on FirebaseAuthException catch (error) {
    return error.code == 'user-not-found' ||
        FirebaseAuth.instance.currentUser == null;
  }
}
