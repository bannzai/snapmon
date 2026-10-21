import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:snapmon/analytics/analytics_events.dart';

// 年齢の確認 (#11 の最初の画面) より前に識別子 (uid・Analytics・App Check) を取らないため、
// Firebase のうち識別子を作る機能はこのファイルの関数からだけ始める (documents/adr/0001-tech-stack.md の対象年齢の行)。
// Analytics と Crashlytics の自動収集は ios/Runner/Info.plist と android/app/src/main/AndroidManifest.xml で既定を無効にしている。

/// Functions の confirmAge と同じリージョン (functions/src/index.ts の setGlobalOptions)。
const _functionsRegion = 'asia-northeast1';

/// Web の App Check に使う reCAPTCHA Enterprise のサイトキー。公開値のため `--dart-define` で渡す (deploy-hosting.yml)。
const _recaptchaEnterpriseSiteKey = String.fromEnvironment(
  'RECAPTCHA_ENTERPRISE_SITE_KEY',
);

/// 年齢の確認を通った後の手順を、識別子を取る順に実行する。
///
/// 順序: App Check の開始 → 匿名ログイン → Functions の confirmAge (生年月の検査とクレームの付与) →
/// クレームの付いた ID トークンへの更新 → Analytics・Crashlytics の収集の開始。
/// クレームが付かなかった時は収集を始めずに [StateError] を投げる。13 歳未満は confirmAge が例外を投げ、以降に進まない。
/// 各段の実体は引数で受け取る (Firebase と切り離して順序を単体テストするため)。アプリからは [startAgeVerifiedSessionWithFirebase] を使う。
///
/// 返す値は匿名ログインの uid。
Future<String> startAgeVerifiedSession({
  required int birthYear,
  required int birthMonth,
  required Future<void> Function() activateAppCheck,
  required Future<String> Function() signInAnonymously,
  required Future<void> Function({
    required int birthYear,
    required int birthMonth,
  })
  confirmAge,
  required Future<bool> Function() refreshAgeVerifiedClaim,
  required Future<void> Function() enableCollection,
}) async {
  await activateAppCheck();
  final uid = await signInAnonymously();
  await confirmAge(birthYear: birthYear, birthMonth: birthMonth);
  if (!await refreshAgeVerifiedClaim()) {
    throw StateError('confirmAge の後も ID トークンに ageVerified のクレームがありません');
  }
  await enableCollection();
  return uid;
}

/// [startAgeVerifiedSession] を Firebase の実体で実行する。年齢の確認の画面 (#11) が、13 歳以上と確認した後に呼ぶ。
Future<String> startAgeVerifiedSessionWithFirebase({
  required int birthYear,
  required int birthMonth,
}) {
  return startAgeVerifiedSession(
    birthYear: birthYear,
    birthMonth: birthMonth,
    activateAppCheck: activateAppCheck,
    signInAnonymously: () async =>
        (await FirebaseAuth.instance.signInAnonymously()).user!.uid,
    confirmAge: ({required birthYear, required birthMonth}) =>
        FirebaseFunctions.instanceFor(region: _functionsRegion)
            .httpsCallable('confirmAge')
            .call<Object?>({'birthYear': birthYear, 'birthMonth': birthMonth}),
    refreshAgeVerifiedClaim: () => hasAgeVerifiedClaim(
      user: FirebaseAuth.instance.currentUser!,
      forceRefresh: true,
    ),
    enableCollection: enableAnalyticsAndCrashlyticsCollection,
  );
}

/// 前回の起動で年齢の確認を済ませたユーザーなら、App Check と収集を再開する。アプリの起動時に呼ぶ。
///
/// 端末に保存された Auth のユーザーがいて、ID トークンに ageVerified のクレームがある時だけ再開し、uid を返す。
/// それ以外 (初回起動・確認の途中で終了した) は何も始めずに null を返し、年齢の確認の画面へ進ませる。
Future<String?> resumeAgeVerifiedSession() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null ||
      !await hasAgeVerifiedClaim(user: user, forceRefresh: false)) {
    return null;
  }
  await activateAppCheck();
  await enableAnalyticsAndCrashlyticsCollection();
  return user.uid;
}

/// [user] の ID トークンに、Functions の confirmAge が付けるクレーム `ageVerified: true` があるか。
/// [forceRefresh] が true なら、端末にあるトークンを使わずに取り直す (クレームを付けた直後に使う)。
Future<bool> hasAgeVerifiedClaim({
  required User user,
  required bool forceRefresh,
}) async {
  return (await user.getIdTokenResult(forceRefresh)).claims?['ageVerified'] ==
      true;
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
