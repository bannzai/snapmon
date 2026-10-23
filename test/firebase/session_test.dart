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
}
