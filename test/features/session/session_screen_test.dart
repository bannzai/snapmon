import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/features/session/session_screen.dart';
import 'package:snapmon/features/session/session_store.dart';
import 'package:snapmon/firebase/session.dart';
import 'package:snapmon/l10n/l10n.dart';

void main() {
  const locale = Locale('ja');

  /// 匿名ログインが [signInError] で失敗し、App Check のトークンの取得が [appCheckTokenError] を返す
  /// (null なら取得に成功する) 端末で、ログインの画面を開いてログインが終わるまで進める。
  Future<void> pumpSessionScreen({
    required WidgetTester tester,
    required Object signInError,
    required Object? appCheckTokenError,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SessionScreen(
          sessionStore: SessionStore(
            startSession: () => startSession(
              activateAppCheck: () async {},
              signInAnonymously: () async => throw signInError,
              fetchAppCheckTokenError: () async => appCheckTokenError,
              enableCollection: () async {},
            ),
            endSession: () async {},
            resumedUid: null,
          ),
          isDebugSkipEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('匿名ログインもトークンの取得も失敗したら、失敗の画面に両方のエラーの文をそのまま出す', (tester) async {
    await pumpSessionScreen(
      tester: tester,
      signInError: FirebaseAuthException(
        code: 'internal-error',
        message: 'An internal error has occurred. [ 401 ]',
      ),
      appCheckTokenError: FirebaseException(
        plugin: 'firebase_app_check',
        code: 'unknown',
        message: 'The attestation provider is not supported.',
      ),
    );

    expect(
      find.text(lookupAppLocalizations(locale).sessionConnectionFailed),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '[firebase_auth/internal-error] An internal error has occurred. [ 401 ]',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '[firebase_app_check/unknown] The attestation provider is not supported.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('匿名ログインだけが失敗したら、失敗の画面に匿名ログインのエラーの文だけを出す', (tester) async {
    await pumpSessionScreen(
      tester: tester,
      signInError: FirebaseAuthException(
        code: 'network-request-failed',
        message: 'A network error has occurred.',
      ),
      appCheckTokenError: null,
    );

    expect(
      find.text(
        '[firebase_auth/network-request-failed] A network error has occurred.',
      ),
      findsOneWidget,
    );
  });
}
