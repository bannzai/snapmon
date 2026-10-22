import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/firebase/age_verified_session.dart';

void main() {
  group('startAgeVerifiedSession', () {
    test(
      'App Check → 匿名ログイン → confirmAge → クレームの確認 → 収集の開始の順に進み、uid を返す',
      () async {
        final calledSteps = <String>[];
        final uid = await startAgeVerifiedSession(
          birthYear: 2000,
          birthMonth: 1,
          activateAppCheck: () async => calledSteps.add('activateAppCheck'),
          signInAnonymously: () async {
            calledSteps.add('signInAnonymously');
            return 'uid-1';
          },
          confirmAge: ({required birthYear, required birthMonth}) async =>
              calledSteps.add('confirmAge:$birthYear-$birthMonth'),
          refreshAgeVerifiedClaim: () async {
            calledSteps.add('refreshAgeVerifiedClaim');
            return true;
          },
          enableCollection: () async => calledSteps.add('enableCollection'),
        );

        expect(uid, 'uid-1');
        expect(calledSteps, [
          'activateAppCheck',
          'signInAnonymously',
          'confirmAge:2000-1',
          'refreshAgeVerifiedClaim',
          'enableCollection',
        ]);
      },
    );

    test('confirmAge が失敗 (13 歳未満) したら収集を始めない', () async {
      var collectionEnabled = false;
      await expectLater(
        startAgeVerifiedSession(
          birthYear: 2020,
          birthMonth: 1,
          activateAppCheck: () async {},
          signInAnonymously: () async => 'uid-1',
          confirmAge: ({required birthYear, required birthMonth}) async =>
              throw Exception('13 歳未満の方は利用できません'),
          refreshAgeVerifiedClaim: () async => false,
          enableCollection: () async => collectionEnabled = true,
        ),
        throwsException,
      );
      expect(collectionEnabled, isFalse);
    });

    test('クレームが付かなかったら収集を始めない', () async {
      var collectionEnabled = false;
      await expectLater(
        startAgeVerifiedSession(
          birthYear: 2000,
          birthMonth: 1,
          activateAppCheck: () async {},
          signInAnonymously: () async => 'uid-1',
          confirmAge: ({required birthYear, required birthMonth}) async {},
          refreshAgeVerifiedClaim: () async => false,
          enableCollection: () async => collectionEnabled = true,
        ),
        throwsStateError,
      );
      expect(collectionEnabled, isFalse);
    });
  });
}
