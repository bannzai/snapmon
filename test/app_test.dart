import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snapmon/app.dart';
import 'package:snapmon/features/age_gate/age_confirmation.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/settings/settings_screen.dart';

import 'sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// テストの「今日」。年齢の確認の境界を固定するため。
  final today = DateTime(2026, 10, 21);

  /// 起動した [SnapmonApp] と、テストから覗く状態。
  late DexStore dexStore;
  late AgeConfirmationStore ageConfirmationStore;
  late List<Uri> openedUris;

  /// iPhone の画面の大きさ (モックの 390 × 844) で [SnapmonApp] を起動する。
  /// [hasConfirmedAge] が true なら年齢の確認を済ませた状態で起動する。
  Future<void> pumpApp({
    required WidgetTester tester,
    required bool hasConfirmedAge,
    required bool isDeveloperMenuEnabled,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    dexStore = DexStore();
    ageConfirmationStore = AgeConfirmationStore(
      preferences: await SharedPreferences.getInstance(),
      today: () => today,
    );
    if (hasConfirmedAge) {
      await ageConfirmationStore.answer(birthYear: 2000, birthMonth: 1);
    }
    openedUris = [];
    await tester.pumpWidget(
      SnapmonApp(
        sampleData: sampleData,
        dexStore: dexStore,
        ageConfirmationStore: ageConfirmationStore,
        openUrl: ({required uri}) async {
          openedUris.add(uri);
          return true;
        },
        isDeveloperMenuEnabled: isDeveloperMenuEnabled,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> enterBirth({
    required WidgetTester tester,
    required String year,
    required String month,
  }) async {
    await tester.enterText(find.byKey(const Key('birthYearField')), year);
    await tester.enterText(find.byKey(const Key('birthMonthField')), month);
    await tester.tap(find.text('つぎへ'));
    await tester.pumpAndSettle();
  }

  group('年齢の確認', () {
    testWidgets('最初の画面で、入力の前に使える年齢を示さない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: false,
        isDeveloperMenuEnabled: false,
      );
      expect(find.text('生まれた年と月を\n入力してください'), findsOneWidget);
      expect(find.textContaining('13'), findsNothing);
      expect(find.byKey(const Key('tab-dex')), findsNothing);
    });

    testWidgets('不正な年月は保存しない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: false,
        isDeveloperMenuEnabled: false,
      );
      for (final (year, month) in [('2000', '13'), ('2030', '1'), ('', '')]) {
        await enterBirth(tester: tester, year: year, month: month);
        expect(find.text('正しい年と月を入力してください'), findsOneWidget);
        expect(ageConfirmationStore.status, AgeConfirmationStatus.unanswered);
      }
    });

    testWidgets('13 歳未満は使えず、起動し直しても入力に戻れない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: false,
        isDeveloperMenuEnabled: false,
      );
      await enterBirth(tester: tester, year: '2015', month: '3');
      expect(find.text('ごめんなさい\nsnapmon は使えません'), findsOneWidget);

      await tester.pumpWidget(
        SnapmonApp(
          key: UniqueKey(),
          sampleData: sampleData,
          dexStore: DexStore(),
          ageConfirmationStore: AgeConfirmationStore(
            preferences: ageConfirmationStore.preferences,
            today: () => today,
          ),
          openUrl: ({required uri}) async => true,
          isDeveloperMenuEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ごめんなさい\nsnapmon は使えません'), findsOneWidget);
      expect(find.byKey(const Key('birthYearField')), findsNothing);
    });

    testWidgets('13 歳以上は撮る画面に進む', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: false,
        isDeveloperMenuEnabled: false,
      );
      await enterBirth(tester: tester, year: '2000', month: '1');
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
    });
  });

  group('下タブと画面の遷移', () {
    testWidgets('下タブで図鑑・撮る・対戦を切り替える', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-dex')));
      await tester.pumpAndSettle();
      expect(find.text('0 体 · 手持ち 0 体'), findsOneWidget);
      expect(find.text('まだモンスターがいません\n撮る画面から身の回りの物を撮ってみよう'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-opponent')));
      await tester.pumpAndSettle();
      expect(find.text('相手をえらぶ'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tab-capture')));
      await tester.pumpAndSettle();
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
    });

    testWidgets('撮ると生まれた画面が開き、手持ちに入れると図鑑に戻る', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byTooltip('撮る'));
      await tester.pumpAndSettle();
      final bornMonster = sampleData.monsters.first.definition;
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(find.text(bornMonster.name), findsOneWidget);
      expect(find.text('名前と図鑑の文章は AI が作りました'), findsOneWidget);
      expect(dexStore.monsters.map((monster) => monster.definition.id), [
        bornMonster.id,
      ]);

      await tester.tap(find.text('手持ちに入れる'));
      await tester.pumpAndSettle();
      expect(find.text('1 体 · 手持ち 1 体'), findsOneWidget);
      // 手持ちの枠と「すべて」の両方に出る
      expect(find.text(bornMonster.name), findsNWidgets(2));
    });

    testWidgets('生まれた画面の「もう 1 体撮る」で撮る画面に戻る', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byTooltip('アルバムから選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('もう 1 体撮る'));
      await tester.pumpAndSettle();
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
      expect(find.text('図鑑 1'), findsOneWidget);
    });

    testWidgets('図鑑のモンスターを押すとカードが開く', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      dexStore.replaceAll(monsters: sampleData.monsters);
      await tester.tap(find.byKey(const Key('tab-dex')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(sampleData.monsters.last.definition.name));
      await tester.pumpAndSettle();
      expect(find.text('図鑑'), findsOneWidget);
      expect(
        find.text(sampleData.monsters.last.definition.encyclopediaText),
        findsOneWidget,
      );
    });

    testWidgets('端末の文字を 2 倍にしても図鑑のカードがはみ出さない', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      dexStore.replaceAll(monsters: sampleData.monsters);
      await tester.tap(find.byKey(const Key('tab-dex')));
      await tester.pumpAndSettle();
      // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
      expect(tester.takeException(), isNull);
      expect(
        find.text(sampleData.monsters.last.definition.name),
        findsOneWidget,
      );
    });

    testWidgets('高さの低い画面でも撮る画面がはみ出さず、スクロールしてシャッターを押せる', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.byTooltip('撮る'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('撮る'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, hasLength(1));
    });

    testWidgets('手持ちが 3 体の時も、カードから外して別のモンスターを入れられる', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      dexStore.replaceAll(monsters: sampleData.monsters);
      await tester.tap(find.byKey(const Key('tab-dex')));
      await tester.pumpAndSettle();
      final partyMonsterName = sampleData.monsters.first.definition.name;
      await tester.tap(find.text(partyMonsterName).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('手持ちから外す'));
      await tester.pumpAndSettle();
      expect(find.text('手持ちに入れる'), findsOneWidget);
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();

      final benchMonster = sampleData.monsters.last.definition;
      await tester.tap(find.text(benchMonster.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手持ちに入れる'));
      await tester.pumpAndSettle();
      expect(dexStore.isInParty(monsterId: benchMonster.id), isTrue);
      expect(dexStore.party, hasLength(3));
    });

    testWidgets('手持ちがいない時は挑めない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byKey(const Key('tab-opponent')));
      await tester.pumpAndSettle();
      expect(find.text('手持ちを入れると挑めます'), findsOneWidget);
      final opponentId = sampleData.opponents.first.id;
      expect(
        tester
            .widget<FilledButton>(find.byKey(Key('challenge-$opponentId')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('挑むとバトル画面が開き、にげると対戦相手の画面、交代で図鑑に戻る', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      dexStore.replaceAll(monsters: sampleData.monsters);
      await tester.tap(find.byKey(const Key('tab-opponent')));
      await tester.pumpAndSettle();
      final opponent = sampleData.opponents.first;
      final challengeButton = find.byKey(Key('challenge-${opponent.id}'));

      // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める。
      // 押した直後のフレームは新しい画面が offstage で作られる (Hero の計測のため) ので、もう 1 フレーム進めてから遷移を終わらせる
      Future<void> pumpTransition() async {
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      }

      await tester.tap(challengeButton);
      await pumpTransition();
      final playerMonster = dexStore.party.first.definition;
      expect(find.text('${playerMonster.name} の 技をえらぶ'), findsOneWidget);
      expect(
        find.text(
          '${sampleData.monsterById(monsterId: opponent.monsterIds.first).definition.name} が 勝負をしかけてきた',
        ),
        findsOneWidget,
      );
      expect(find.text('ターン 1'), findsOneWidget);

      await tester.tap(find.text('にげる'));
      await pumpTransition();
      expect(find.text('相手をえらぶ'), findsOneWidget);

      await tester.tap(challengeButton);
      await pumpTransition();
      await tester.tap(find.text('モンスターを交代'));
      await pumpTransition();
      expect(
        find.text('${sampleData.monsters.length} 体 · 手持ち 3 体'),
        findsOneWidget,
      );
    });
  });

  testWidgets('端末の文字を 2 倍にしてもバトル画面の技のボタンがはみ出さない', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(
      tester: tester,
      hasConfirmedAge: true,
      isDeveloperMenuEnabled: false,
    );
    dexStore.replaceAll(monsters: sampleData.monsters);
    await tester.tap(find.byKey(const Key('tab-opponent')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('challenge-${sampleData.opponents.first.id}')),
    );
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('にげる'), findsOneWidget);
    // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
    expect(tester.takeException(), isNull);
  });

  group('設定画面', () {
    testWidgets('お問い合わせと法務ドキュメントのリンクを開く', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      for (final title in ['お問い合わせ', '利用規約', 'プライバシーポリシー', 'アカウントの削除について']) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
      }
      expect(openedUris, [
        contactUri,
        termsUri,
        privacyPolicyUri,
        accountDeletionUri,
      ]);
      expect(contactUri.toString(), 'mailto:bannzai.app@gmail.com');
      expect(find.text('アカウントを削除'), findsOneWidget);
    });

    testWidgets('リンクを開けない時と開く時に例外になった時は、そのことを出す', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      Future<void> pumpSettings({required OpenUrl openUrl}) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: SettingsScreen(
              sampleData: sampleData,
              dexStore: DexStore(),
              ageConfirmationStore: AgeConfirmationStore(
                preferences: preferences,
                today: () => today,
              ),
              openUrl: openUrl,
              isDeveloperMenuEnabled: false,
            ),
          ),
        );
        await tester.tap(find.text('お問い合わせ'));
        await tester.pumpAndSettle();
      }

      await pumpSettings(openUrl: ({required uri}) async => false);
      expect(find.text('$contactUri を開けませんでした'), findsOneWidget);

      await pumpSettings(
        openUrl: ({required uri}) async =>
            throw Exception('ACTIVITY_NOT_FOUND'),
      );
      expect(find.text('Exception: ACTIVITY_NOT_FOUND'), findsOneWidget);
    });

    testWidgets('開発者メニューは無効の時に出ない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.text('開発者メニュー'), findsNothing);
    });

    testWidgets('開発者メニューで見本の投入と図鑑のクリアができる', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: true,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      expect(find.text('未ログイン (Firebase Authentication は未接続)'), findsOneWidget);

      await tester.tap(find.text('見本モンスターを図鑑に投入'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, hasLength(sampleData.monsters.length));
      expect(dexStore.party, hasLength(3));

      await tester.tap(find.text('図鑑をクリア'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, isEmpty);
    });

    testWidgets('開発者メニューで年齢の確認をやり直せる', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        isDeveloperMenuEnabled: true,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('年齢の確認をやり直す'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('birthYearField')), findsOneWidget);
    });
  });
}
