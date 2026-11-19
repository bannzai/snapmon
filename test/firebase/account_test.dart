import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/firebase/account.dart';

void main() {
  group('accountLinkProviderNames', () {
    // プラットフォームで分けない定数のため、iOS・Android・Web が同じ値を読む
    test('Apple と Google をこの順で選べる', () {
      expect(accountLinkProviderNames, ['Apple', 'Google']);
    });
  });

  group('accountLinkAuthProvider', () {
    test('Apple は Sign in with Apple の provider を返す', () {
      final provider = accountLinkAuthProvider(providerName: 'Apple');

      expect(provider, isA<AppleAuthProvider>());
      expect(provider.providerId, 'apple.com');
    });

    test('Google は Google の provider を返す', () {
      final provider = accountLinkAuthProvider(providerName: 'Google');

      expect(provider, isA<GoogleAuthProvider>());
      expect(provider.providerId, 'google.com');
    });

    test('選べる名前は、どれも provider を返す', () {
      for (final providerName in accountLinkProviderNames) {
        expect(
          accountLinkAuthProvider(providerName: providerName),
          isA<AuthProvider>(),
        );
      }
    });

    for (final providerName in ['google', 'apple.com', 'Facebook', '']) {
      test('選べない名前 ("$providerName") は ArgumentError を投げる', () {
        expect(
          () => accountLinkAuthProvider(providerName: providerName),
          throwsArgumentError,
        );
      });
    }
  });

  group('linksAccountWithGoogleSignIn', () {
    test('Android のアプリの Google は google_sign_in で連携する', () {
      expect(
        linksAccountWithGoogleSignIn(
          providerName: 'Google',
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isTrue,
      );
    });

    test('Android のアプリの Apple は google_sign_in を使わず、provider で連携する', () {
      expect(
        linksAccountWithGoogleSignIn(
          providerName: 'Apple',
          isWeb: false,
          platform: TargetPlatform.android,
        ),
        isFalse,
      );
    });

    for (final providerName in ['Apple', 'Google']) {
      test('iOS のアプリの $providerName は provider で連携する', () {
        expect(
          linksAccountWithGoogleSignIn(
            providerName: providerName,
            isWeb: false,
            platform: TargetPlatform.iOS,
          ),
          isFalse,
        );
      });

      // Android のブラウザで開いた Web 版は platform が Android になる。Web 版はポップアップで連携する
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        test('Web 版 ($platform のブラウザ) の $providerName は provider で連携する', () {
          expect(
            linksAccountWithGoogleSignIn(
              providerName: providerName,
              isWeb: true,
              platform: platform,
            ),
            isFalse,
          );
        });
      }
    }
  });
}
