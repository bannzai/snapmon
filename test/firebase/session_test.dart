import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/firebase/session.dart';

void main() {
  group('startSession', () {
    test('App Check → 匿名ログイン → 収集の開始の順に進み、uid を返す', () async {
      final calledSteps = <String>[];
      final uid = await startSession(
        activateAppCheck: () async => calledSteps.add('activateAppCheck'),
        signInAnonymously: () async {
          calledSteps.add('signInAnonymously');
          return 'uid-1';
        },
        fetchAppCheckTokenError: () async {
          calledSteps.add('fetchAppCheckTokenError');
          return Exception('app-check');
        },
        enableCollection: () async => calledSteps.add('enableCollection'),
      );

      expect(uid, 'uid-1');
      // 匿名ログインが成功する時は、App Check のトークンの取得を 1 回も呼ばない
      expect(calledSteps, [
        'activateAppCheck',
        'signInAnonymously',
        'enableCollection',
      ]);
    });

    test('匿名ログインが失敗したら収集を始めない', () async {
      var collectionEnabled = false;
      await expectLater(
        startSession(
          activateAppCheck: () async {},
          signInAnonymously: () async => throw Exception('network'),
          fetchAppCheckTokenError: () async => null,
          enableCollection: () async => collectionEnabled = true,
        ),
        throwsException,
      );
      expect(collectionEnabled, isFalse);
    });

    test('匿名ログインもトークンの取得も失敗したら、両方のエラーの文を加工せずに持つ例外を投げ、収集を始めない', () async {
      var fetchAppCheckTokenErrorCallCount = 0;
      var collectionEnabled = false;
      Object? thrownError;
      try {
        await startSession(
          activateAppCheck: () async {},
          signInAnonymously: () async => throw FirebaseAuthException(
            code: 'internal-error',
            message: 'An internal error has occurred. [ 401 ]',
          ),
          fetchAppCheckTokenError: () async {
            fetchAppCheckTokenErrorCallCount++;
            return FirebaseException(
              plugin: 'firebase_app_check',
              code: 'unknown',
              message: 'The attestation provider is not supported.',
            );
          },
          enableCollection: () async => collectionEnabled = true,
        );
      } catch (error) {
        thrownError = error;
      }

      expect(thrownError, isA<SessionStartException>());
      expect(
        thrownError.toString(),
        '[firebase_auth/internal-error] An internal error has occurred. [ 401 ]\n\n'
        '[firebase_app_check/unknown] The attestation provider is not supported.',
      );
      expect(fetchAppCheckTokenErrorCallCount, 1);
      expect(collectionEnabled, isFalse);
    });

    test('匿名ログインが失敗してトークンの取得は成功したら、匿名ログインの例外をそのまま投げる', () async {
      final signInError = FirebaseAuthException(
        code: 'network-request-failed',
        message: 'A network error has occurred.',
      );
      // 取得できたトークンの値。取得の関数は成功した時に null だけを返すため、startSession には渡らない
      const appCheckToken = 'app-check-token-value';
      Object? thrownError;
      try {
        await startSession(
          activateAppCheck: () async {},
          signInAnonymously: () async => throw signInError,
          fetchAppCheckTokenError: () async => null,
          enableCollection: () async {},
        );
      } catch (error) {
        thrownError = error;
      }

      expect(thrownError, same(signInError));
      expect(thrownError.toString(), isNot(contains(appCheckToken)));
    });
  });

  group('appCheckDebugToken', () {
    test('DEBUG ビルドで token が渡されていれば、その token を返す', () {
      expect(
        appCheckDebugToken(
          isDebugBuild: true,
          tokenFromEnvironment: 'registered-debug-token',
        ),
        'registered-debug-token',
      );
    });

    test('DEBUG ビルドでも token が渡されていなければ (空文字) null を返す', () {
      expect(
        appCheckDebugToken(isDebugBuild: true, tokenFromEnvironment: ''),
        isNull,
      );
    });

    test('リリースビルドでは token が渡されていても null を返す', () {
      expect(
        appCheckDebugToken(
          isDebugBuild: false,
          tokenFromEnvironment: 'registered-debug-token',
        ),
        isNull,
      );
    });
  });

  group('resumeSession', () {
    /// 前回の起動で [currentUid] がログインしていた端末で、ID トークンの取り直しが [refreshError] で失敗する
    /// (null なら成功する) 時に再開し、呼んだ段の名前を [calledSteps] に残す。
    Future<String?> resume({
      required String? currentUid,
      required FirebaseAuthException? refreshError,
      required List<String> calledSteps,
    }) => resumeSession(
      currentUid: currentUid,
      refreshIDToken: () async {
        calledSteps.add('refreshIDToken');
        if (refreshError != null) {
          throw refreshError;
        }
      },
      signOut: () async => calledSteps.add('signOut'),
      activateAppCheck: () async => calledSteps.add('activateAppCheck'),
      enableCollection: () async => calledSteps.add('enableCollection'),
    );

    test('Auth のユーザーがいない時は何も始めずに null を返す', () async {
      final calledSteps = <String>[];
      expect(
        await resume(
          currentUid: null,
          refreshError: null,
          calledSteps: calledSteps,
        ),
        isNull,
      );
      expect(calledSteps, isEmpty);
    });

    test('ID トークンを取り直せたら App Check と収集を始めて uid を返す', () async {
      final calledSteps = <String>[];
      expect(
        await resume(
          currentUid: 'uid-1',
          refreshError: null,
          calledSteps: calledSteps,
        ),
        'uid-1',
      );
      expect(calledSteps, [
        'refreshIDToken',
        'activateAppCheck',
        'enableCollection',
      ]);
    });

    for (final code in [
      'user-not-found',
      'user-disabled',
      'user-token-expired',
      'invalid-user-token',
    ]) {
      test('認証情報が無効 ($code) ならサインアウトして null を返し、App Check と収集を始めない', () async {
        final calledSteps = <String>[];
        expect(
          await resume(
            currentUid: 'uid-1',
            refreshError: FirebaseAuthException(code: code),
            calledSteps: calledSteps,
          ),
          isNull,
        );
        expect(calledSteps, ['refreshIDToken', 'signOut']);
      });
    }

    test('通信できない時は確かめずに再開する', () async {
      final calledSteps = <String>[];
      expect(
        await resume(
          currentUid: 'uid-1',
          refreshError: FirebaseAuthException(code: 'network-request-failed'),
          calledSteps: calledSteps,
        ),
        'uid-1',
      );
      expect(calledSteps, [
        'refreshIDToken',
        'activateAppCheck',
        'enableCollection',
      ]);
    });

    test('一時的な失敗 (too-many-requests) では投げ、サインアウトしない', () async {
      final calledSteps = <String>[];
      await expectLater(
        resume(
          currentUid: 'uid-1',
          refreshError: FirebaseAuthException(code: 'too-many-requests'),
          calledSteps: calledSteps,
        ),
        throwsA(isA<FirebaseAuthException>()),
      );
      expect(calledSteps, ['refreshIDToken']);
    });
  });
}
