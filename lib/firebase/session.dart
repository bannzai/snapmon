import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:snapmon/analytics/analytics_events.dart';

// Firebase のうち識別子を作る機能 (App Check・匿名ログイン・Analytics・Crashlytics) は、このファイルの関数からだけ始める
// (ログインと計測を同じ時に始め、ログインせずに入った DEBUG ビルドでは計測しないため)。
// Analytics と Crashlytics の自動収集は ios/Runner/Info.plist と android/app/src/main/AndroidManifest.xml で既定を無効にしている。

/// Functions のリージョン (functions/src/index.ts の setGlobalOptions)。
const functionsRegion = 'asia-northeast1';

/// Web の App Check に使う reCAPTCHA Enterprise のサイトキー。公開値のため `--dart-define` で渡す (deploy-hosting.yml)。
const _recaptchaEnterpriseSiteKey = String.fromEnvironment(
  'RECAPTCHA_ENTERPRISE_SITE_KEY',
);

/// ログインの手順を、識別子を取る順に実行する。
///
/// 順序: App Check の開始 → 匿名ログイン → Analytics・Crashlytics の収集の開始。ログインに失敗した時は収集を始めない。
/// 各段の実体は引数で受け取る (Firebase と切り離して順序を単体テストするため)。アプリからは [startSessionWithFirebase] を使う。
///
/// 返す値は匿名ログインの uid。
Future<String> startSession({
  required Future<void> Function() activateAppCheck,
  required Future<String> Function() signInAnonymously,
  required Future<void> Function() enableCollection,
}) async {
  await activateAppCheck();
  final uid = await signInAnonymously();
  await enableCollection();
  return uid;
}

/// [startSession] を Firebase の実体で実行する。タイトル画面の裏のログインと、ログインの画面 (lib/features/session/session_screen.dart) が呼ぶ。
/// Auth のユーザーが残っている時 (起動時の [resumeSession] が App Check や収集の開始で失敗した時) は、そのユーザーを使い続ける
/// (匿名ログインし直すと、Apple / Google と連携したユーザーがサインアウトされて図鑑に届かなくなるため)。
Future<String> startSessionWithFirebase() {
  return startSession(
    activateAppCheck: activateAppCheck,
    signInAnonymously: () async =>
        FirebaseAuth.instance.currentUser?.uid ??
        (await FirebaseAuth.instance.signInAnonymously()).user!.uid,
    enableCollection: enableAnalyticsAndCrashlyticsCollection,
  );
}

/// 収集を止めて匿名ログインからサインアウトし、ログインより前の状態に戻す。
/// アカウントの削除の後と、開発者メニュー (DEBUG ビルド) の「新しいアカウントで始め直す」が使う。
/// 何度呼んでも同じ (冪等)。App Check は止める API が無いため、トークンの自動更新だけを止める。
Future<void> endSessionWithFirebase() async {
  // activateAppCheck が始めなかった時 (Web でサイトキーが無い) は止めるものが無い
  if (!kIsWeb || _recaptchaEnterpriseSiteKey.isNotEmpty) {
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(false);
  }
  markAnalyticsCollectionStopped();
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
  if (!kIsWeb) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  }
  await FirebaseAuth.instance.signOut();
}

/// ID トークンの取り直しで、認証情報が無効になった (ユーザーが削除・無効化された、トークンが失効した) ことを示す
/// FirebaseAuthException の code。FlutterFire の firebase_auth が返す code のうち、再試行しても直らないもの。
const _invalidCredentialErrorCodes = {
  'user-not-found',
  'user-disabled',
  'user-token-expired',
  'invalid-user-token',
};

/// 前回の起動でログインしたユーザー ([currentUid]) なら、App Check と収集を再開して uid を返す。
/// Auth のユーザーがいない時 (初回起動) は何も始めずに null を返し、ログインの画面へ進ませる。
/// 認証情報が無効な時 (別の端末でアカウントを削除した等) はサインアウトして null を返し、新しい匿名アカウントでログインさせる。
/// 確かめるのが一時的な失敗で済まなかった時 (通信できない時を除く) は投げる。
/// 各段の実体は引数で受け取る (Firebase と切り離して分岐を単体テストするため)。アプリからは [resumeSessionWithFirebase] を使う。
Future<String?> resumeSession({
  required String? currentUid,
  required Future<void> Function() refreshIdToken,
  required Future<void> Function() signOut,
  required Future<void> Function() activateAppCheck,
  required Future<void> Function() enableCollection,
}) async {
  if (currentUid == null) {
    return null;
  }
  try {
    // 期限の切れた ID トークンを取り直し、別の端末でアカウントを削除した後などの無効な認証情報を見つける
    await refreshIdToken();
  } on FirebaseAuthException catch (error) {
    // 認証情報が無効だと分かるエラーだけでサインアウトする。無効な認証情報で再開すると、Firebase との通信がすべて失敗するのに
    // ログインし直せないため。通信できない・混み合っている等の一時的な失敗でサインアウトすると、連携していない匿名の
    // ユーザーが図鑑に戻れなくなるため、再開はせずに投げる (タイトル画面のログインが残っている Auth のユーザーで始め直す)
    if (_invalidCredentialErrorCodes.contains(error.code)) {
      await signOut();
      return null;
    }
    // 通信できない時は確かめられないだけなので再開する (ログイン済みの人がオフラインで使えなくならないように)
    if (error.code != 'network-request-failed') {
      rethrow;
    }
  }
  await activateAppCheck();
  await enableCollection();
  return currentUid;
}

/// [resumeSession] を Firebase の実体で実行する。アプリの起動時に呼ぶ。
Future<String?> resumeSessionWithFirebase() {
  final user = FirebaseAuth.instance.currentUser;
  return resumeSession(
    currentUid: user?.uid,
    refreshIdToken: () async => await user!.getIdToken(),
    signOut: FirebaseAuth.instance.signOut,
    activateAppCheck: activateAppCheck,
    enableCollection: enableAnalyticsAndCrashlyticsCollection,
  );
}

/// App Check を始める。リリースビルドは各プラットフォームの証明 (iOS: App Attest、Android: Play Integrity、Web: reCAPTCHA Enterprise)、
/// デバッグビルドは debug provider を使う (simulator・emulator では証明が通らないため。debug token は Firebase コンソールに登録する)。
/// Web でサイトキーが渡されていない時は始めない (App Check を必須にした Functions の呼び出しは失敗する)。
Future<void> activateAppCheck() async {
  if (kIsWeb && _recaptchaEnterpriseSiteKey.isEmpty) {
    debugPrint('RECAPTCHA_ENTERPRISE_SITE_KEY が未設定のため Web の App Check を始めません');
    return;
  }
  await FirebaseAppCheck.instance.activate(
    providerWeb: ReCaptchaEnterpriseProvider(_recaptchaEnterpriseSiteKey),
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
    providerApple: kDebugMode
        ? const AppleDebugProvider()
        : const AppleAppAttestWithDeviceCheckFallbackProvider(),
  );
  // iOS は Info.plist の FirebaseAppCheckTokenAutoRefreshEnabled で自動取得を止めているため、ここで有効にする。
  await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
}

/// Analytics と Crashlytics の収集を始め、未捕捉の例外を Crashlytics に送る。Crashlytics は Web 非対応のため Web では Analytics だけ。
Future<void> enableAnalyticsAndCrashlyticsCollection() async {
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);
  markAnalyticsCollectionStarted();
  if (kIsWeb) {
    return;
  }
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(true);
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    unawaited(
      FirebaseCrashlytics.instance.recordError(error, stackTrace, fatal: true),
    );
    return true;
  };
}
