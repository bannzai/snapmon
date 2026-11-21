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

/// サインイン・連携の結果の代わり。[user] だけを持つ。
class _FakeUserCredential extends Fake implements UserCredential {
  /// [user] を結果のユーザーとして返す。
  _FakeUserCredential({required this.user});

  @override
  final User? user;
}

/// Firebase のユーザーの代わり。連携の 3 つの呼び出しを [linkCalls] に記録し、[linkError] があればそれを投げる。
class _FakeUser extends Fake implements User {
  /// [uid] のユーザーを作る。[linkError] が null なら連携は成功する。
  _FakeUser({required this.uid, required this.linkError});

  @override
  final String uid;

  /// 連携の呼び出しが投げる失敗。null なら成功する。
  final FirebaseAuthException? linkError;

  /// 呼ばれた連携の関数の名前と、渡された provider か credential。呼ばれた順。
  final List<(String, Object)> linkCalls = [];

  /// 連携の呼び出し 1 回を [linkCalls] に記録し、[linkError] があれば投げ、無ければ自分を結果のユーザーとして返す。
  Future<UserCredential> _link({
    required String method,
    required Object argument,
  }) async {
    linkCalls.add((method, argument));
    if (linkError case final error?) {
      throw error;
    }
    return _FakeUserCredential(user: this);
  }

  @override
  Future<UserCredential> linkWithPopup(AuthProvider provider) =>
      _link(method: 'linkWithPopup', argument: provider);

  @override
  Future<UserCredential> linkWithProvider(AuthProvider provider) =>
      _link(method: 'linkWithProvider', argument: provider);

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) =>
      _link(method: 'linkWithCredential', argument: credential);
}

/// FirebaseAuth の代わり。いまのユーザーが [currentUser] で、credential でのサインインを [signInCredentials] に記録する。
class _FakeAuth extends Fake implements FirebaseAuth {
  /// いまのユーザーが [currentUser] で、credential でサインインすると [linkedAccountUID] のユーザーになる FirebaseAuth を作る。
  _FakeAuth({required this.currentUser, required this.linkedAccountUID});

  @override
  final _FakeUser currentUser;

  /// credential でサインインした時のユーザー (連携済みのアカウント) の uid。
  final String linkedAccountUID;

  /// `signInWithCredential` に渡された credential。呼ばれた順。
  final List<AuthCredential> signInCredentials = [];

  /// `signInWithRedirect` に渡された provider。呼ばれた順。
  final List<AuthProvider> redirectProviders = [];

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    signInCredentials.add(credential);
    return _FakeUserCredential(
      user: _FakeUser(uid: linkedAccountUID, linkError: null),
    );
  }

  @override
  Future<void> signInWithRedirect(AuthProvider provider) async {
    redirectProviders.add(provider);
  }
}

/// いまのユーザーの連携が [linkError] で失敗する (null なら成功する) FirebaseAuth の代わりを作る。
_FakeAuth _auth({required FirebaseAuthException? linkError}) => _FakeAuth(
  currentUser: _FakeUser(uid: 'anonymous-uid', linkError: linkError),
  linkedAccountUID: 'linked-uid',
);

/// 呼ばれたらテストを失敗させる、Android の Google の credential の読み取り。google_sign_in を使わない流れに渡す。
Future<AuthCredential> _failOnGoogleSignIn() async =>
    fail('google_sign_in を使わない流れで Google のアカウントの選択が呼ばれた');

void main() {
  group('linkAccountWithAuth', () {
    // Android のブラウザで開いた Web 版は platform が Android になる。Web 版はどの OS でもポップアップで連携する
    for (final (description, isWeb, platform, providerName, method, providerID)
        in <(String, bool, TargetPlatform, String, String, String)>[
          (
            'Web 版の Apple',
            true,
            TargetPlatform.macOS,
            'Apple',
            'linkWithPopup',
            'apple.com',
          ),
          (
            'Web 版の Google',
            true,
            TargetPlatform.macOS,
            'Google',
            'linkWithPopup',
            'google.com',
          ),
          (
            'Android のブラウザの Web 版の Google',
            true,
            TargetPlatform.android,
            'Google',
            'linkWithPopup',
            'google.com',
          ),
          (
            'iOS のアプリの Apple',
            false,
            TargetPlatform.iOS,
            'Apple',
            'linkWithProvider',
            'apple.com',
          ),
          (
            'iOS のアプリの Google',
            false,
            TargetPlatform.iOS,
            'Google',
            'linkWithProvider',
            'google.com',
          ),
          (
            'Android のアプリの Apple',
            false,
            TargetPlatform.android,
            'Apple',
            'linkWithProvider',
            'apple.com',
          ),
        ]) {
      test(
        '$description は $method に $providerID の provider を渡して連携する',
        () async {
          final auth = _auth(linkError: null);

          expect(
            await linkAccountWithAuth(
              auth: auth,
              isWeb: isWeb,
              platform: platform,
              readGoogleCredentialOnAndroid: _failOnGoogleSignIn,
              providerName: providerName,
            ),
            isNull,
          );
          expect(auth.currentUser.linkCalls, hasLength(1));
          expect(auth.currentUser.linkCalls.single.$1, method);
          expect(
            auth.currentUser.linkCalls.single.$2,
            isA<AuthProvider>().having(
              (provider) => provider.providerId,
              'providerId',
              providerID,
            ),
          );
          expect(auth.signInCredentials, isEmpty);
        },
      );
    }

    test(
      'Android のアプリの Google は、選んでもらったアカウントの credential を linkWithCredential に渡して連携する',
      () async {
        final auth = _auth(linkError: null);
        final googleCredential = GoogleAuthProvider.credential(
          idToken: 'google-id-token',
        );
        var googleSignInCount = 0;

        expect(
          await linkAccountWithAuth(
            auth: auth,
            isWeb: false,
            platform: TargetPlatform.android,
            readGoogleCredentialOnAndroid: () async {
              googleSignInCount += 1;
              return googleCredential;
            },
            providerName: 'Google',
          ),
          isNull,
        );
        expect(googleSignInCount, 1);
        expect(auth.currentUser.linkCalls, [
          ('linkWithCredential', googleCredential),
        ]);
      },
    );

    test(
      '連携済みの時は、返した関数を呼ぶまでサインインせず、呼ぶとエラーの credential でサインインして連携済みの uid を返す',
      () async {
        const credential = _NativeAppleCredential();
        final auth = _auth(
          linkError: FirebaseAuthException(
            code: 'credential-already-in-use',
            credential: credential,
          ),
        );

        final signInToLinkedAccount = await linkAccountWithAuth(
          auth: auth,
          isWeb: false,
          platform: TargetPlatform.android,
          readGoogleCredentialOnAndroid: _failOnGoogleSignIn,
          providerName: 'Apple',
        );

        expect(signInToLinkedAccount, isNotNull);
        expect(auth.signInCredentials, isEmpty);
        expect(await signInToLinkedAccount!(), 'linked-uid');
        expect(auth.signInCredentials, [credential]);
      },
    );

    test(
      'Web 版の Apple が連携済みで、ID トークンに nonce が無い credential の時は切り替えに進める',
      () async {
        final credential = OAuthProvider(
          'apple.com',
        ).credential(idToken: _idToken(payload: {'sub': 'user'}));
        final auth = _auth(
          linkError: FirebaseAuthException(
            code: 'credential-already-in-use',
            credential: credential,
          ),
        );

        expect(
          await (await linkAccountWithAuth(
            auth: auth,
            isWeb: true,
            platform: TargetPlatform.macOS,
            readGoogleCredentialOnAndroid: _failOnGoogleSignIn,
            providerName: 'Apple',
          ))!(),
          'linked-uid',
        );
        expect(auth.signInCredentials, [credential]);
      },
    );

    test(
      'Web 版の Apple が連携済みで、ID トークンに nonce があり元の nonce が無い credential の時は、'
      '返した関数を呼ぶまで何もせず、呼ぶと credential を使わずに Apple のサインインを画面の遷移で出し直す',
      () async {
        final auth = _auth(
          linkError: FirebaseAuthException(
            code: 'credential-already-in-use',
            credential: OAuthProvider('apple.com').credential(
              idToken: _idToken(payload: {'sub': 'user', 'nonce': 'hashed'}),
            ),
          ),
        );

        final signInToLinkedAccount = await linkAccountWithAuth(
          auth: auth,
          isWeb: true,
          platform: TargetPlatform.macOS,
          readGoogleCredentialOnAndroid: _failOnGoogleSignIn,
          providerName: 'Apple',
        );

        expect(signInToLinkedAccount, isNotNull);
        expect(auth.redirectProviders, isEmpty);
        // 遷移が始まればページを離れて戻らないため、遷移の呼び出しが戻った時 (Fake) は失敗として投げる
        await expectLater(signInToLinkedAccount!(), throwsStateError);
        expect(auth.redirectProviders, hasLength(1));
        expect(auth.redirectProviders.single.providerId, 'apple.com');
        expect(auth.signInCredentials, isEmpty);
      },
    );

    test('連携済みのエラーに credential が無い時は、切り替えに進めず元のエラーを投げる', () async {
      final error = FirebaseAuthException(code: 'credential-already-in-use');
      final auth = _auth(linkError: error);

      await expectLater(
        linkAccountWithAuth(
          auth: auth,
          isWeb: true,
          platform: TargetPlatform.macOS,
          readGoogleCredentialOnAndroid: _failOnGoogleSignIn,
          providerName: 'Google',
        ),
        throwsA(same(error)),
      );
      expect(auth.signInCredentials, isEmpty);
    });

    test('Android のアプリの Google が連携済みで、エラーに credential が無い時は、'
        '選んでもらったアカウントの credential で切り替えに進める', () async {
      final googleCredential = GoogleAuthProvider.credential(
        idToken: 'google-id-token',
      );
      final auth = _auth(
        linkError: FirebaseAuthException(code: 'credential-already-in-use'),
      );

      expect(
        await (await linkAccountWithAuth(
          auth: auth,
          isWeb: false,
          platform: TargetPlatform.android,
          readGoogleCredentialOnAndroid: () async => googleCredential,
          providerName: 'Google',
        ))!(),
        'linked-uid',
      );
      expect(auth.signInCredentials, [googleCredential]);
    });

    test('連携済み以外の失敗は、credential が付いていても切り替えに進めず元のエラーを投げる', () async {
      final error = FirebaseAuthException(
        code: 'operation-not-allowed',
        credential: const _NativeAppleCredential(),
      );
      final auth = _auth(linkError: error);

      await expectLater(
        linkAccountWithAuth(
          auth: auth,
          isWeb: false,
          platform: TargetPlatform.iOS,
          readGoogleCredentialOnAndroid: _failOnGoogleSignIn,
          providerName: 'Apple',
        ),
        throwsA(same(error)),
      );
      expect(auth.signInCredentials, isEmpty);
    });

    test('選べない名前は、連携の呼び出しをせずに ArgumentError を投げる', () async {
      final auth = _auth(linkError: null);

      await expectLater(
        linkAccountWithAuth(
          auth: auth,
          isWeb: true,
          platform: TargetPlatform.macOS,
          readGoogleCredentialOnAndroid: _failOnGoogleSignIn,
          providerName: 'Facebook',
        ),
        throwsArgumentError,
      );
      expect(auth.currentUser.linkCalls, isEmpty);
    });
  });

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
