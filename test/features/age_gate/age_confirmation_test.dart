import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snapmon/features/age_gate/age_confirmation.dart';

void main() {
  group('isOldEnough', () {
    test('13 歳の誕生日がある月はまだ使えない', () {
      expect(
        isOldEnough(
          birthYear: 2013,
          birthMonth: 10,
          today: DateTime(2026, 10, 31),
        ),
        isFalse,
      );
    });

    test('13 歳の誕生日がある月の翌月から使える', () {
      expect(
        isOldEnough(
          birthYear: 2013,
          birthMonth: 10,
          today: DateTime(2026, 11, 1),
        ),
        isTrue,
      );
    });

    test('年をまたぐ境界: 12 月生まれは 13 年後の翌年 1 月から使える', () {
      expect(
        isOldEnough(
          birthYear: 2012,
          birthMonth: 12,
          today: DateTime(2025, 12, 31),
        ),
        isFalse,
      );
      expect(
        isOldEnough(
          birthYear: 2012,
          birthMonth: 12,
          today: DateTime(2026, 1, 1),
        ),
        isTrue,
      );
    });

    test('12 歳は使えず、大人は使える', () {
      final today = DateTime(2026, 10, 21);
      expect(
        isOldEnough(birthYear: 2014, birthMonth: 1, today: today),
        isFalse,
      );
      expect(isOldEnough(birthYear: 1990, birthMonth: 5, today: today), isTrue);
    });
  });

  group('AgeConfirmationStore', () {
    var today = DateTime(2026, 10, 21);

    Future<AgeConfirmationStore> createStore() async {
      SharedPreferences.setMockInitialValues({});
      return AgeConfirmationStore(
        preferences: await SharedPreferences.getInstance(),
        today: () => today,
      );
    }

    setUp(() => today = DateTime(2026, 10, 21));

    test('入力前は未回答', () async {
      expect((await createStore()).status, AgeConfirmationStatus.unanswered);
    });

    test('13 歳以上の生年月を入力すると使える', () async {
      final store = await createStore();
      await store.answer(birthYear: 2000, birthMonth: 1);
      expect(store.status, AgeConfirmationStatus.allowed);
    });

    test('13 歳未満は使えず、13 歳の誕生日の翌月になると使える', () async {
      final store = await createStore();
      await store.answer(birthYear: 2013, birthMonth: 10);
      expect(store.status, AgeConfirmationStatus.restricted);
      today = DateTime(2026, 11, 1);
      expect(store.status, AgeConfirmationStatus.allowed);
    });

    test('保存した生年月は作り直したストアにも残る', () async {
      final store = await createStore();
      await store.answer(birthYear: 2015, birthMonth: 3);
      final reopened = AgeConfirmationStore(
        preferences: store.preferences,
        today: () => today,
      );
      expect(reopened.status, AgeConfirmationStatus.restricted);
    });

    test('reset で未回答に戻る', () async {
      final store = await createStore();
      await store.answer(birthYear: 2000, birthMonth: 1);
      await store.reset();
      expect(store.status, AgeConfirmationStatus.unanswered);
    });
  });
}
