import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snapmon/features/age_gate/age_confirmation.dart';
import 'package:snapmon/features/age_gate/age_verified_session_store.dart';
import 'package:snapmon/features/settings/account_store.dart';

void main() {
  late List<String> calls;
  late AgeVerifiedSessionStore sessionStore;
  late AgeConfirmationStore ageConfirmationStore;

  setUp(() async {
    calls = [];
    SharedPreferences.setMockInitialValues({});
    ageConfirmationStore = AgeConfirmationStore(
      preferences: await SharedPreferences.getInstance(),
      today: () => DateTime(2026, 10, 22),
    );
    await ageConfirmationStore.answer(birthYear: 2000, birthMonth: 1);
    sessionStore = AgeVerifiedSessionStore(
      startSession: ({required birthYear, required birthMonth}) async =>
          'uid-new',
      endSession: () async => calls.add('endSession'),
      resumedUid: 'uid-anonymous',
    );
  });

  /// 呼ばれた操作を [calls] に順に残す [AccountStore]。
  AccountStore accountStore({
    required Future<Future<String> Function()?> Function() linkAccount,
    required Future<void> Function() deleteAccount,
  }) => AccountStore(
    sessionStore: sessionStore,
    ageConfirmationStore: ageConfirmationStore,
    linkProviderName: 'Apple',
    readLinkedProviderNames: () => const [],
    linkAccount: () {
      calls.add('link');
      return linkAccount();
    },
    discardCurrentAccount: () async => calls.add('discard'),
    deleteAccount: () {
      calls.add('delete');
      return deleteAccount();
    },
  );

  group('switchToLinkedAccount', () {
    test('いまの匿名アカウントを捨ててから連携済みのアカウントにサインインし、uid を差し替える', () async {
      final store = accountStore(
        linkAccount: () async => null,
        deleteAccount: () async {},
      );

      await store.switchToLinkedAccount(
        signInToLinkedAccount: () async {
          calls.add('signIn');
          return 'uid-linked';
        },
      );

      expect(calls, ['discard', 'signIn']);
      expect(sessionStore.uid, 'uid-linked');
      expect(store.isWorking, isFalse);
    });

    test('捨てた後のサインインに失敗したら、ログインを終えてから投げる (新しい匿名アカウントから始め直す)', () async {
      final store = accountStore(
        linkAccount: () async => null,
        deleteAccount: () async {},
      );

      await expectLater(
        store.switchToLinkedAccount(
          signInToLinkedAccount: () async => throw Exception('canceled'),
        ),
        throwsA(isA<Exception>()),
      );

      expect(calls, ['discard', 'endSession']);
      expect(sessionStore.uid, isNull);
      // 生年月は残し、年齢の確認の後のログインから始め直す
      expect(ageConfirmationStore.status, AgeConfirmationStatus.allowed);
      expect(store.isWorking, isFalse);
    });
  });

  group('delete', () {
    test('消した後にログインを終え、保存した生年月を消す', () async {
      final store = accountStore(
        linkAccount: () async => null,
        deleteAccount: () async {},
      );

      await store.delete();

      expect(calls, ['delete', 'endSession']);
      expect(sessionStore.uid, isNull);
      expect(ageConfirmationStore.status, AgeConfirmationStatus.unanswered);
    });

    test('削除に失敗したら、ログインと生年月を残したまま投げる', () async {
      final store = accountStore(
        linkAccount: () async => null,
        deleteAccount: () async => throw Exception('deadline-exceeded'),
      );

      await expectLater(store.delete(), throwsA(isA<Exception>()));

      expect(calls, ['delete']);
      expect(sessionStore.uid, 'uid-anonymous');
      expect(ageConfirmationStore.status, AgeConfirmationStatus.allowed);
      expect(store.isWorking, isFalse);
    });
  });

  test('連携の途中は、ほかの操作を受け付けない', () async {
    final linking = Completer<Future<String> Function()?>();
    final store = accountStore(
      linkAccount: () => linking.future,
      deleteAccount: () async {},
    );

    final link = store.link();
    expect(store.isWorking, isTrue);
    await expectLater(store.delete(), throwsA(isA<StateError>()));
    linking.complete(null);
    expect(await link, isNull);

    expect(calls, ['link']);
    expect(store.isWorking, isFalse);
  });
}
