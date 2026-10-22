import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/app.dart';
import 'package:snapmon/features/age_gate/age_confirmation.dart';
import 'package:snapmon/features/age_gate/age_verified_session_store.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/settings/settings_screen.dart';
import 'package:snapmon/sample/sample_data.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import 'battle_recorder_fixture.dart';
import 'monster_generator_fixture.dart';
import 'sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// テストの「今日」。年齢の確認の境界を固定するため。
  final today = DateTime(2026, 10, 21);

  /// 起動した [SnapmonApp] と、テストから覗く状態。
  late DexStore dexStore;
  late AgeConfirmationStore ageConfirmationStore;
  late AgeVerifiedSessionStore ageVerifiedSessionStore;
  late List<({int birthYear, int birthMonth})> startSessionCalls;
  var endSessionCallCount = 0;
  late List<Uri> openedUris;
  late RecordedBattleCalls battleCalls;
  late RecordedGenerationCalls generationCalls;

  /// [pumpApp] のバトルの記録の開始が返す battleId と、記録の完了が返すレベル。
  /// 既定はログインしていない時の振る舞い (記録しない)。テストが [pumpApp] の前に変える。
  late Future<String?> Function() startBattleRecord;
  late Map<String, int> recordedLevels;

  setUp(() {
    startBattleRecord = () async => null;
    recordedLevels = const {};
  });

  /// アルバムから選ぶと、要求 ID ごとに見本のモンスター ([generatedWaxMonster]) をサーバーが保存して図鑑に届けたことにする生成。
  MonsterGenerator appMonsterGenerator() => fakeMonsterGenerator(
    calls: generationCalls,
    albumPhoto: testPhotoBytes,
    uploadError: null,
    requestGeneration: ({required requestId}) async {
      dexStore.applyServerSnapshot(
        monsters: [
          ...dexStore.monsters,
          generatedWaxMonster(monsterId: 'generated-$requestId'),
        ],
        partyMonsterIds: null,
        definitions: definitionsWithWax(base: sampleData.definitions),
      );
      return GenerationResult(
        requestId: requestId,
        status: GenerationStatus.saved,
        monsterId: 'generated-$requestId',
        rejectionReason: null,
      );
    },
    fetchGeneration: ({required requestId}) =>
        throw StateError('fetchGeneration は呼ばない'),
  );

  /// Firebase を呼ばずに [startSessionCalls] へ呼び出しを残すログイン。
  /// 先頭から [failureCount] 回は通信の失敗を投げ、その後は uid を返す。
  AgeVerifiedSessionStore fakeAgeVerifiedSessionStore({
    required String? resumedUid,
    required int failureCount,
  }) {
    var remainingFailureCount = failureCount;
    return AgeVerifiedSessionStore(
      startSession: ({required birthYear, required birthMonth}) async {
        startSessionCalls.add((birthYear: birthYear, birthMonth: birthMonth));
        if (remainingFailureCount > 0) {
          remainingFailureCount--;
          throw Exception('network-request-failed');
        }
        return 'uid-1';
      },
      endSession: () async => endSessionCallCount++,
      resumedUid: resumedUid,
    );
  }

  /// iPhone の画面の大きさ (モックの 390 × 844) で [SnapmonApp] を起動する。
  /// [hasConfirmedAge] が true なら年齢の確認を済ませた状態で起動する。[hasStartedSession] が true なら、
  /// 前回の起動で済ませたログインを再開した状態で起動する。ログインは先頭から [startSessionFailureCount] 回失敗する。
  Future<void> pumpApp({
    required WidgetTester tester,
    required bool hasConfirmedAge,
    required bool hasStartedSession,
    required int startSessionFailureCount,
    required bool isDeveloperMenuEnabled,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    dexStore = DexStore(definitions: sampleData.definitions);
    generationCalls = RecordedGenerationCalls();
    ageConfirmationStore = AgeConfirmationStore(
      preferences: await SharedPreferences.getInstance(),
      today: () => today,
    );
    if (hasConfirmedAge) {
      await ageConfirmationStore.answer(birthYear: 2000, birthMonth: 1);
    }
    startSessionCalls = [];
    ageVerifiedSessionStore = fakeAgeVerifiedSessionStore(
      resumedUid: hasStartedSession ? 'uid-resumed' : null,
      failureCount: startSessionFailureCount,
    );
    openedUris = [];
    battleCalls = RecordedBattleCalls();
    await tester.pumpWidget(
      SnapmonApp(
        sampleData: sampleData,
        dexStore: dexStore,
        ageConfirmationStore: ageConfirmationStore,
        ageVerifiedSessionStore: ageVerifiedSessionStore,
        openUrl: ({required uri}) async {
          openedUris.add(uri);
          return true;
        },
        isDeveloperMenuEnabled: isDeveloperMenuEnabled,
        battleRecorder: fakeBattleRecorder(
          calls: battleCalls,
          startBattleRecord: startBattleRecord,
          recordedLevels: recordedLevels,
        ),
        monsterGenerator: appMonsterGenerator(),
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
        hasStartedSession: false,
        startSessionFailureCount: 0,
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
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      for (final (year, month) in [('2000', '13'), ('2030', '1'), ('', '')]) {
        await enterBirth(tester: tester, year: year, month: month);
        expect(find.text('正しい年と月を入力してください'), findsOneWidget);
        expect(ageConfirmationStore.status, AgeConfirmationStatus.unanswered);
      }
      expect(startSessionCalls, isEmpty);
    });

    testWidgets('13 歳未満は使えず、起動し直しても入力に戻れない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: false,
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await enterBirth(tester: tester, year: '2015', month: '3');
      expect(find.text('ごめんなさい\nsnapmon は使えません'), findsOneWidget);
      // 13 歳未満からは識別子を取らないため、ログインを始めない
      expect(startSessionCalls, isEmpty);

      await tester.pumpWidget(
        SnapmonApp(
          key: UniqueKey(),
          sampleData: sampleData,
          dexStore: DexStore(definitions: sampleData.definitions),
          ageConfirmationStore: AgeConfirmationStore(
            preferences: ageConfirmationStore.preferences,
            today: () => today,
          ),
          ageVerifiedSessionStore: ageVerifiedSessionStore,
          openUrl: ({required uri}) async => true,
          isDeveloperMenuEnabled: false,
          battleRecorder: fakeBattleRecorder(
            calls: RecordedBattleCalls(),
            startBattleRecord: () async => null,
            recordedLevels: const {},
          ),
          monsterGenerator: appMonsterGenerator(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ごめんなさい\nsnapmon は使えません'), findsOneWidget);
      expect(find.byKey(const Key('birthYearField')), findsNothing);
    });

    testWidgets('13 歳以上は入力した生年月でログインしてから撮る画面に進む', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: false,
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await enterBirth(tester: tester, year: '2000', month: '1');
      expect(startSessionCalls, [(birthYear: 2000, birthMonth: 1)]);
      expect(ageVerifiedSessionStore.uid, 'uid-1');
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
    });

    testWidgets('ログインに失敗したらエラーと「もう一度試す」を出して止まり、やり直して成功したら撮る画面に進む', (
      tester,
    ) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: false,
        hasStartedSession: false,
        startSessionFailureCount: 1,
        isDeveloperMenuEnabled: false,
      );
      await enterBirth(tester: tester, year: '2000', month: '1');
      expect(find.text('つながりませんでした'), findsOneWidget);
      expect(find.text('Exception: network-request-failed'), findsOneWidget);
      expect(find.byKey(const Key('tab-capture')), findsNothing);
      expect(find.text('ログインせずに進む (DEBUG)'), findsNothing);
      expect(ageVerifiedSessionStore.uid, isNull);

      await tester.tap(find.text('もう一度試す'));
      await tester.pumpAndSettle();
      expect(startSessionCalls, [
        (birthYear: 2000, birthMonth: 1),
        (birthYear: 2000, birthMonth: 1),
      ]);
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
    });

    testWidgets('開発者メニューが有効な時だけ、ログインに失敗した画面からログインせずに進める', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: false,
        startSessionFailureCount: 1,
        isDeveloperMenuEnabled: true,
      );
      expect(find.text('つながりませんでした'), findsOneWidget);
      await tester.tap(find.text('ログインせずに進む (DEBUG)'));
      await tester.pumpAndSettle();
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);

      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      expect(find.text('未ログイン (年齢の確認の後のログインを DEBUG で飛ばした)'), findsOneWidget);
    });

    testWidgets('生年月を入力済みでログインが済んでいない時は、起動するとログインを始める', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(startSessionCalls, [(birthYear: 2000, birthMonth: 1)]);
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
    });

    testWidgets('前回の起動でログインを済ませた時は、ログインせずに撮る画面から始まる', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(startSessionCalls, isEmpty);
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
    });
  });

  group('下タブと画面の遷移', () {
    testWidgets('下タブで図鑑・撮る・対戦を切り替える', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
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

    testWidgets('アルバムから選ぶと生成して生まれた画面が開き、手持ちに入れると図鑑に戻る', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byTooltip('アルバムから選ぶ'));
      await tester.pumpAndSettle();
      final bornMonster = generatedWaxMonster(
        monsterId: 'generated-request-1',
      ).definition;
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(find.text(bornMonster.name), findsOneWidget);
      expect(find.text('名前と図鑑の文章は AI が作りました'), findsOneWidget);
      expect(generationCalls.uploadedRequestIds, ['request-1']);
      expect(
        generationCalls.loggedEvents.single.event,
        AnalyticsEvent.monsterGenerated,
      );
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
        hasStartedSession: true,
        startSessionFailureCount: 0,
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
        hasStartedSession: true,
        startSessionFailureCount: 0,
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
        hasStartedSession: true,
        startSessionFailureCount: 0,
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

    testWidgets('高さの低い画面でも撮る画面がはみ出さず、スクロールしてアルバムから選べる', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.byTooltip('アルバムから選ぶ'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('アルバムから選ぶ'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, hasLength(1));
    });

    testWidgets('カメラが無い時はファインダーにそのことを出し、シャッターはアルバムへ案内する', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      // テストの環境にはカメラのプラグインが無く、カメラを開けない
      expect(find.textContaining('カメラが使えません'), findsOneWidget);
      await tester.tap(find.byTooltip('撮る'));
      await tester.pump();
      expect(find.text('カメラが使えません\nアルバムから選んでください'), findsOneWidget);
      expect(generationCalls.uploadedRequestIds, isEmpty);
    });

    testWidgets('手持ちが 3 体の時に手持ちに入れようとすると、選んだ手持ちと入れ替わる', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      dexStore.replaceAll(monsters: sampleData.monsters);
      final partyBefore = dexStore.party;
      await tester.tap(find.byKey(const Key('tab-dex')));
      await tester.pumpAndSettle();
      final benchMonster = sampleData.monsters.last.definition;
      await tester.tap(find.text(benchMonster.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('手持ちと入れ替える'));
      await tester.pumpAndSettle();
      expect(find.text('${benchMonster.name} と入れ替える'), findsOneWidget);
      await tester.tap(
        find.byKey(Key('replace-${partyBefore[1].definition.id}')),
      );
      await tester.pumpAndSettle();
      expect(dexStore.party.map((monster) => monster.definition.id), [
        partyBefore[0].definition.id,
        benchMonster.id,
        partyBefore[2].definition.id,
      ]);
      // 入れ替えた後は図鑑に戻る
      expect(
        find.text('${sampleData.monsters.length} 体 · 手持ち 3 体'),
        findsOneWidget,
      );
    });

    testWidgets('見本の定義に無い属性・技を持つ生成したモンスターも、カードを開けて CPU と戦える', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      final waxMonster = generatedWaxMonster(monsterId: 'm1');
      dexStore.applyServerSnapshot(
        monsters: [waxMonster, ...sampleData.monsters],
        partyMonsterIds: [waxMonster.definition.id],
        definitions: definitionsWithWax(base: sampleData.definitions),
      );
      await tester.tap(find.byKey(const Key('tab-dex')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(waxMonster.definition.name).first);
      await tester.pumpAndSettle();
      expect(find.text('ろうアタック PP 30'), findsOneWidget);
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('tab-opponent')));
      await tester.pumpAndSettle();
      final challengeButton = find.byKey(const Key('challenge-$cpuOpponentId'));
      await tester.ensureVisible(challengeButton);
      await tester.pumpAndSettle();
      await tester.tap(challengeButton);
      // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.text('${waxMonster.definition.name} の 技をえらぶ'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('move-slot-0')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    });

    testWidgets('手持ちが 3 体の時も、カードから外して別のモンスターを入れられる', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
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
        hasStartedSession: true,
        startSessionFailureCount: 0,
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
        hasStartedSession: true,
        startSessionFailureCount: 0,
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

  testWidgets('CPU トレーナーに挑むと技を選んで決着まで戦え、戦ったモンスターのレベルが上がる', (tester) async {
    await pumpApp(
      tester: tester,
      hasConfirmedAge: true,
      hasStartedSession: true,
      startSessionFailureCount: 0,
      isDeveloperMenuEnabled: false,
    );
    dexStore.replaceAll(monsters: sampleData.monsters);
    final partyBefore = dexStore.party;
    await tester.tap(find.byKey(const Key('tab-opponent')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        '平均 Lv. ${partyBefore.fold<int>(0, (sum, monster) => sum + monster.level) ~/ partyBefore.length} 前後',
      ),
      findsOneWidget,
    );
    final challengeButton = find.byKey(const Key('challenge-$cpuOpponentId'));
    await tester.ensureVisible(challengeButton);
    await tester.pumpAndSettle();
    await tester.tap(challengeButton);
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 100 ターン: 見本の手持ち同士なら十数ターンで決着するため、決着しない不具合でテストが止まらない上限として十分な数
    for (
      var turn = 0;
      turn < 100 && find.text('もどる').evaluate().isEmpty;
      turn++
    ) {
      await tester.tap(
        find.text('わるあがき').evaluate().isEmpty
            ? find.byKey(const Key('move-slot-0'))
            : find.text('わるあがき'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
    }
    expect(find.text('もどる'), findsOneWidget);
    expect(
      find.text('かった').evaluate().length + find.text('まけた').evaluate().length,
      1,
    );
    expect(find.text('ログインしていないため記録していません'), findsOneWidget);
    expect(battleCalls.startedPartyMonsterIds, [
      [for (final monster in partyBefore) monster.definition.id],
    ]);
    expect(battleCalls.loggedEvents.single.event.eventName, 'battle_completed');
    // 先頭の手持ちは必ず場に出るため、勝敗に関係なくレベルが 1 上がる
    expect(dexStore.party.first.level, partyBefore.first.level + 1);

    await tester.tap(find.text('もどる'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('相手をえらぶ'), findsOneWidget);
  });

  testWidgets('ログインして記録した対戦は勝敗の画面に記録しましたと出し、Functions が返したレベルを図鑑に反映する', (tester) async {
    startBattleRecord = () async => 'battle-1';
    recordedLevels = {
      for (final monster in sampleData.monsters.take(3))
        monster.definition.id: 50,
    };
    await pumpApp(
      tester: tester,
      hasConfirmedAge: true,
      hasStartedSession: true,
      startSessionFailureCount: 0,
      isDeveloperMenuEnabled: false,
    );
    dexStore.replaceAll(monsters: sampleData.monsters);
    await tester.tap(find.byKey(const Key('tab-opponent')));
    await tester.pumpAndSettle();
    final challengeButton = find.byKey(const Key('challenge-$cpuOpponentId'));
    await tester.ensureVisible(challengeButton);
    await tester.pumpAndSettle();
    await tester.tap(challengeButton);
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // 100 ターン: 見本の手持ち同士なら十数ターンで決着するため、決着しない不具合でテストが止まらない上限として十分な数
    for (
      var turn = 0;
      turn < 100 && find.text('もどる').evaluate().isEmpty;
      turn++
    ) {
      await tester.tap(
        find.text('わるあがき').evaluate().isEmpty
            ? find.byKey(const Key('move-slot-0'))
            : find.text('わるあがき'),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
    }
    expect(find.text('記録しました'), findsOneWidget);
    expect(battleCalls.completedBattles.single.battleId, 'battle-1');
    expect(dexStore.party.first.level, 50);
  });

  testWidgets('端末の文字を 2 倍にしてもバトル画面の技のボタンがはみ出さない', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(
      tester: tester,
      hasConfirmedAge: true,
      hasStartedSession: true,
      startSessionFailureCount: 0,
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

  testWidgets('iOS の最大の文字サイズでも交代・にげるのボタンの文字が切れない', (tester) async {
    // iOS のアクセシビリティの最大の文字サイズ (約 3.1 倍) より少し大きくした
    // 文字が大きいと対戦相手の画面の挑むボタンが画面外に出るため、バトル画面を直接開く
    tester.platformDispatcher.textScaleFactorTestValue = 3.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        home: BattleScreen(
          playerParty: sampleData.monsters.take(3).toList(),
          opponentParty: sampleData.monsters.skip(3).toList(),
          definitions: sampleData.definitions,
          randomSeed: 1,
          battleRecorder: fakeBattleRecorder(
            calls: RecordedBattleCalls(),
            startBattleRecord: () async => null,
            recordedLevels: const {},
          ),
          onPlayerLevelsChanged: ({required levelsByMonsterId}) {},
        ),
      ),
    );
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump(const Duration(seconds: 1));
    // 高さが足りない時、文字は例外を出さずに切れる (描画の大きさが中身の高さより小さくなる) ため、
    // 文字の描画の大きさが中身の高さ以上あることで確かめる
    for (final label in ['にげる', 'モンスターを交代']) {
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      expect(
        paragraph.size.height,
        greaterThanOrEqualTo(
          paragraph.getMinIntrinsicHeight(paragraph.size.width),
        ),
        reason: label,
      );
    }
  });

  group('設定画面', () {
    testWidgets('お問い合わせと法務ドキュメントのリンクを開く', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
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
              dexStore: DexStore(definitions: sampleData.definitions),
              ageConfirmationStore: AgeConfirmationStore(
                preferences: preferences,
                today: () => today,
              ),
              ageVerifiedSessionStore: fakeAgeVerifiedSessionStore(
                resumedUid: 'uid-resumed',
                failureCount: 0,
              ),
              monsterGenerator: appMonsterGenerator(),
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
        hasStartedSession: true,
        startSessionFailureCount: 0,
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
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      expect(find.text('匿名ログイン (年齢の確認済み) uid: uid-resumed'), findsOneWidget);

      await tester.tap(find.text('見本モンスターを図鑑に投入'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, hasLength(sampleData.monsters.length));
      expect(dexStore.party, hasLength(3));

      await tester.tap(find.text('図鑑をクリア'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, isEmpty);
    });

    testWidgets('サーバーの図鑑に繋いでいる時は、開発者メニューの見本の投入と図鑑のクリアを使えない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
      );
      dexStore.connectServer(savePartyMonsterIds: ({required monsterIds}) async {});
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      expect(find.text('ログイン中は使えない (サーバーの図鑑と混ざるため)'), findsOneWidget);
      await tester.tap(find.text('見本モンスターを図鑑に投入'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, isEmpty);
    });

    testWidgets('開発者メニューの見本の写真から生成すると、生まれた画面が開く', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('見本の写真から生成: マグカップ'));
      await tester.pumpAndSettle();
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(generationCalls.loggedEvents.single.parameters, {
        'source': 'sample',
      });
    });

    testWidgets('開発者メニューで年齢の確認をやり直すと、ログインを終えて初回起動と同じくログインからやり直す', (
      tester,
    ) async {
      endSessionCallCount = 0;
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('年齢の確認をやり直す'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('birthYearField')), findsOneWidget);
      expect(endSessionCallCount, 1);
      expect(ageVerifiedSessionStore.uid, isNull);

      await enterBirth(tester: tester, year: '2000', month: '1');
      expect(startSessionCalls, [(birthYear: 2000, birthMonth: 1)]);
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
    });
  });
}
