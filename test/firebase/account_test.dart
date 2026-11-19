import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/firebase/account.dart';

void main() {
  group('accountLinkProviderNamesForPlatform', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('iOS は Apple と Google をこの順で選べる', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

      expect(accountLinkProviderNamesForPlatform, ['Apple', 'Google']);
    });

    // Web (kIsWeb) はコンパイル時の定数で、VM のテストでは切り替えられない。Web も iOS 以外と同じ分岐を通る
    for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
      test('iOS 以外 ($platform) は Google だけを選べる', () {
        debugDefaultTargetPlatformOverride = platform;

        expect(accountLinkProviderNamesForPlatform, ['Google']);
      });
    }
  });

  group('accountLinkAuthProviderOnIOS', () {
    test('Apple は Sign in with Apple の provider を返す', () {
      final provider = accountLinkAuthProviderOnIOS(providerName: 'Apple');

      expect(provider, isA<AppleAuthProvider>());
      expect(provider.providerId, 'apple.com');
    });

    test('Google は Google の provider を返す', () {
      final provider = accountLinkAuthProviderOnIOS(providerName: 'Google');

      expect(provider, isA<GoogleAuthProvider>());
      expect(provider.providerId, 'google.com');
    });

    test('iOS で選べる名前は、どれも provider を返す', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      for (final providerName in accountLinkProviderNamesForPlatform) {
        expect(
          accountLinkAuthProviderOnIOS(providerName: providerName),
          isA<AuthProvider>(),
        );
      }
    });

    for (final providerName in ['google', 'google.com', 'Facebook', '']) {
      test('iOS で選べない名前 ("$providerName") は ArgumentError を投げる', () {
        expect(
          () => accountLinkAuthProviderOnIOS(providerName: providerName),
          throwsArgumentError,
        );
      });
    }
  });
}
