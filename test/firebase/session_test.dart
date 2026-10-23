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
        enableCollection: () async => calledSteps.add('enableCollection'),
      );

      expect(uid, 'uid-1');
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
          enableCollection: () async => collectionEnabled = true,
        ),
        throwsException,
      );
      expect(collectionEnabled, isFalse);
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
      refreshIdToken: () async {
        calledSteps.add('refreshIdToken');
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
        'refreshIdToken',
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
        expect(calledSteps, ['refreshIdToken', 'signOut']);
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
        'refreshIdToken',
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
      expect(calledSteps, ['refreshIdToken']);
    });
  });
}
