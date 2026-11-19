import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/firebase/account.dart';

/// [payload] を載せた JWT の形の文字列 (header.payload.signature) を返す。実際の ID トークンと同じく、
/// base64url の末尾の `=` を付けない。署名は確かめる対象が読まないため、中身の無い文字列にしている。
String _idToken({required Object? payload}) =>
    'eyJhbGciOiJSUzI1NiJ9.'
    '${base64Url.encode(utf8.encode(jsonEncode(payload))).replaceAll('=', '')}'
    '.signature';

/// iOS と Android の plugin が連携の失敗に付けて返す credential と同じ形
/// (ID トークンを持たず、ネイティブ側が持つ credential の番号だけを持つ [AuthCredential])。
class _NativeAppleCredential extends AuthCredential {
  /// 番号 1 の、Apple の credential。
  const _NativeAppleCredential()
    : super(providerId: 'apple.com', signInMethod: 'oauth', token: 1);
}

void main() {
  group('linkedAccountCredentialLacksNonce', () {
    // 'a'・'ab'・'abc' で payload の長さを 1 ずつ変え、base64url の末尾の `=` が 0〜2 個要る形をどれも通す
    for (final nonce in ['a', 'ab', 'abc']) {
      test(
        'ID トークンに nonce ("$nonce") があり、元の nonce を持たない Apple の credential は当たる',
        () {
          expect(
            linkedAccountCredentialLacksNonce(
              credential: OAuthProvider('apple.com').credential(
                idToken: _idToken(payload: {'sub': 'user', 'nonce': nonce}),
                accessToken: 'access-token',
              ),
            ),
            isTrue,
          );
        },
      );
    }

    test('ID トークンに nonce が無い Apple の credential は当たらない', () {
      expect(
        linkedAccountCredentialLacksNonce(
          credential: OAuthProvider(
            'apple.com',
          ).credential(idToken: _idToken(payload: {'sub': 'user'})),
        ),
        isFalse,
      );
    });

    test('ID トークンに nonce があっても、元の nonce を持つ Apple の credential は当たらない', () {
      expect(
        linkedAccountCredentialLacksNonce(
          credential: OAuthProvider('apple.com').credential(
            idToken: _idToken(payload: {'sub': 'user', 'nonce': 'hashed'}),
            rawNonce: 'raw',
          ),
        ),
        isFalse,
      );
    });

    test('ID トークンに nonce がある Google の credential は当たらない (Apple だけを止める)', () {
      expect(
        linkedAccountCredentialLacksNonce(
          credential: OAuthProvider('google.com').credential(
            idToken: _idToken(payload: {'sub': 'user', 'nonce': 'hashed'}),
          ),
        ),
        isFalse,
      );
    });

    test('iOS と Android の plugin が返す、番号だけを持つ Apple の credential は当たらない', () {
      expect(
        linkedAccountCredentialLacksNonce(
          credential: const _NativeAppleCredential(),
        ),
        isFalse,
      );
    });

    for (final (description, idToken) in <(String, String?)>[
      ('無い', null),
      ('空', ''),
      ('JWT の 3 つの区切りが無い', 'not-a-jwt'),
      ('payload が base64url でない', 'header.@@@.signature'),
      (
        'payload が JSON でない',
        'header.${base64Url.encode(utf8.encode('nonce'))}.signature',
      ),
      ('payload が JSON の配列', _idToken(payload: ['nonce'])),
    ]) {
      test('ID トークンが読めない ($description) Apple の credential は当たらない', () {
        expect(
          linkedAccountCredentialLacksNonce(
            credential: OAuthProvider('apple.com').credential(idToken: idToken),
          ),
          isFalse,
        );
      });
    }
  });

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
