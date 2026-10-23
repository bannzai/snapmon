import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/app.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/features/age_gate/age_confirmation.dart';
import 'package:snapmon/features/age_gate/age_verified_session_store.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/features/settings/account_store.dart';
import 'package:snapmon/features/settings/settings_screen.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/share_cards.dart';
import 'package:snapmon/sample/sample_data.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import 'battle_recorder_fixture.dart';
import 'card_sharer_fixture.dart';
import 'monster_generator_fixture.dart';
import 'pvp_client_fixture.dart';
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

  /// [pumpApp] の PvP の呼び出しと、それが受け取った呼び出し。既定はログインしていない時の振る舞い (見本の対戦相手を出す)。
  /// テストが [pumpApp] の前に変える。
  late RecordedPvpCalls pvpCalls;
  late PvpClient pvpClient;

  /// [pumpApp] の共有シートが返す結果。既定は共有した。テストが [pumpApp] の前に変える。
  late ShareResultStatus shareResultStatus;
  late RecordedShareCalls shareCalls;

  /// [pumpApp] の設定画面のアカウントの連携と削除。呼ばれた操作を [accountCalls] に順に残す。
  /// 連携と削除の振る舞いは、テストが [pumpApp] の前に変える。既定は連携でき、削除できる。
  late AccountStore accountStore;
  late List<String> accountCalls;
  late List<String> linkedProviderNames;
  late Future<Future<String> Function()?> Function() linkAccount;
  late Future<void> Function() deleteAccount;

  setUp(() {
    startBattleRecord = () async => null;
    recordedLevels = const {};
    pvpCalls = RecordedPvpCalls();
    pvpClient = signedOutPvpClient(calls: pvpCalls);
    shareResultStatus = ShareResultStatus.success;
    accountCalls = [];
    linkedProviderNames = [];
    linkAccount = () async {
      linkedProviderNames = ['Google'];
      return null;
    };
    deleteAccount = () async {};
  });

  /// [sessionStore] と [ageConfirmationStore] に繋いだ、Firebase を呼ばない [AccountStore]。
  AccountStore fakeAccountStore({
    required AgeVerifiedSessionStore sessionStore,
    required AgeConfirmationStore ageConfirmationStore,
  }) => AccountStore(
    sessionStore: sessionStore,
    ageConfirmationStore: ageConfirmationStore,
    linkProviderName: 'Google',
    readLinkedProviderNames: () => linkedProviderNames,
    linkAccount: () {
      accountCalls.add('link');
      return linkAccount();
    },
    discardCurrentAccount: () async => accountCalls.add('discard'),
    deleteAccount: () {
      accountCalls.add('delete');
      return deleteAccount();
    },
  );

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
    shareCalls = RecordedShareCalls();
    accountStore = fakeAccountStore(
      sessionStore: ageVerifiedSessionStore,
      ageConfirmationStore: ageConfirmationStore,
    );
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
        pvpClient: pvpClient,
        cardSharer: fakeCardSharer(
          calls: shareCalls,
          artImage: null,
          shareResultStatus: shareResultStatus,
        ),
        accountStore: accountStore,
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
          pvpClient: signedOutPvpClient(calls: RecordedPvpCalls()),
          cardSharer: fakeCardSharer(
            calls: RecordedShareCalls(),
            artImage: null,
            shareResultStatus: ShareResultStatus.success,
          ),
          accountStore: accountStore,
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

    testWidgets('生まれた画面から図鑑のカードを形を選んで共有し、共有イベントを送る', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byTooltip('アルバムから選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('カードを共有'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-format-portrait')));
      await tester.pumpAndSettle();
      // 描いた画像を見せている間は、まだ共有シートを開かない
      expect(shareCalls.renderedCards, hasLength(1));
      expect(shareCalls.sharedImages, isEmpty);
      await tester.tap(find.byKey(const Key('share-confirm')));
      await tester.pumpAndSettle();

      final bornMonster = generatedWaxMonster(
        monsterId: 'generated-request-1',
      ).definition;
      final rendered = shareCalls.renderedCards.single;
      expect(rendered.format, ShareCardFormat.portrait);
      expect(
        (rendered.card as MonsterShareCard).monster.definition.id,
        bornMonster.id,
      );
      // 切り出した画像を持たない見本のモンスターは Storage を読まない
      expect(shareCalls.loadedArtPaths, isEmpty);
      final shared = shareCalls.sharedImages.single;
      expect(shared.fileName, 'snapmon-${bornMonster.id}-portrait.png');
      expect(shared.text, contains(bornMonster.name));
      expect(shared.text, contains(landingPageUri.toString()));
      final logged = shareCalls.loggedEvents.single;
      expect(logged.event, AnalyticsEvent.contentShared);
      expect(logged.parameters, {
        'screen': 'result_newly_born',
        'format': 'portrait',
      });
    });

    testWidgets('図鑑の詳細から共有シートを閉じただけの時は共有イベントを送らない', (tester) async {
      shareResultStatus = ShareResultStatus.dismissed;
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
      // 手持ちにいない (図鑑の一覧にだけ名前が出る) 最後のモンスターを開く
      await tester.tap(find.text(sampleData.monsters.last.definition.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('カードを共有'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-format-landscape')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-confirm')));
      await tester.pumpAndSettle();

      expect(shareCalls.renderedCards.single.format, ShareCardFormat.landscape);
      expect(shareCalls.sharedImages, hasLength(1));
      expect(shareCalls.loggedEvents, isEmpty);
    });

    testWidgets('描いた画像を見せた後に「やめる」を押した時は共有しない', (tester) async {
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
      // 手持ちにいない (図鑑の一覧にだけ名前が出る) 最後のモンスターを開く
      await tester.tap(find.text(sampleData.monsters.last.definition.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('カードを共有'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-format-portrait')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();

      expect(shareCalls.renderedCards, hasLength(1));
      expect(shareCalls.sharedImages, isEmpty);
      expect(shareCalls.loggedEvents, isEmpty);
      // ボタンは再び押せる
      await tester.tap(find.text('カードを共有'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share-format-portrait')), findsOneWidget);
    });

    testWidgets('図鑑の詳細の共有で形を選ばずに閉じた時は共有しない', (tester) async {
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
      // 手持ちにいない (図鑑の一覧にだけ名前が出る) 最後のモンスターを開く
      await tester.tap(find.text(sampleData.monsters.last.definition.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('カードを共有'));
      await tester.pumpAndSettle();
      // 形を選ぶシートの外 (画面の上端) を押して閉じる
      await tester.tapAt(const Offset(195, 20));
      await tester.pumpAndSettle();

      expect(shareCalls.renderedCards, isEmpty);
      expect(shareCalls.sharedImages, isEmpty);
      expect(shareCalls.loggedEvents, isEmpty);
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
      // fakeMonsterGenerator のカメラの一覧は空
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

    testWidgets('サーバーの図鑑では挑む前に定義を読み直し、読み直した定義で戦う', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      final waxMonster = generatedWaxMonster(monsterId: 'm1');
      var refreshCount = 0;
      dexStore
        ..connectServer(
          savePartyMonsterIds: ({required monsterIds}) async {},
          refreshDefinitions: () async {
            refreshCount++;
            dexStore.applyServerSnapshot(
              monsters: null,
              partyMonsterIds: null,
              definitions: definitionsWithWax(base: sampleData.definitions),
            );
          },
        )
        // 読み直す前の定義には、このモンスターの属性・技が無い
        ..applyServerSnapshot(
          monsters: [waxMonster],
          partyMonsterIds: [waxMonster.definition.id],
          definitions: sampleData.definitions,
        );
      await tester.tap(find.byKey(const Key('tab-opponent')));
      await tester.pumpAndSettle();
      final challengeButton = find.byKey(const Key('challenge-$cpuOpponentId'));
      await tester.ensureVisible(challengeButton);
      await tester.pumpAndSettle();
      await tester.tap(challengeButton);
      // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(refreshCount, 1);
      expect(tester.takeException(), isNull);
      expect(
        find.text('${waxMonster.definition.name} の 技をえらぶ'),
        findsOneWidget,
      );
    });

    testWidgets('挑む前の定義の読み直しを待っている間は、挑む操作を受け付けない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      final pendingRefresh = Completer<void>();
      var refreshCount = 0;
      dexStore
        ..replaceAll(monsters: sampleData.monsters)
        ..connectServer(
          savePartyMonsterIds: ({required monsterIds}) async {},
          refreshDefinitions: () {
            refreshCount++;
            return pendingRefresh.future;
          },
        );
      await tester.tap(find.byKey(const Key('tab-opponent')));
      await tester.pumpAndSettle();
      final challengeButton = find.byKey(const Key('challenge-$cpuOpponentId'));
      await tester.ensureVisible(challengeButton);
      await tester.pumpAndSettle();
      await tester.tap(challengeButton);
      await tester.pump();
      await tester.tap(challengeButton, warnIfMissed: false);
      await tester.pump();
      expect(refreshCount, 1);
      pendingRefresh.complete();
      // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BattleScreen), findsOneWidget);
    });

    testWidgets('図鑑の読み込みに失敗した時は、もう一度読み込むで読み直して図鑑を反映する', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      dexStore
        ..connectServer(
          savePartyMonsterIds: ({required monsterIds}) async {},
          refreshDefinitions: () async => dexStore.applyServerSnapshot(
            monsters: sampleData.monsters,
            partyMonsterIds: null,
            definitions: sampleData.definitions,
          ),
        )
        ..reportServerError(error: StateError('通信できません'));
      await tester.tap(find.byKey(const Key('tab-dex')));
      await tester.pumpAndSettle();
      expect(find.text('Bad state: 通信できません'), findsOneWidget);
      await tester.tap(find.text('もう一度読み込む'));
      await tester.pumpAndSettle();
      expect(find.text('Bad state: 通信できません'), findsNothing);
      expect(
        find.text('${sampleData.monsters.length} 体 · 手持ち 0 体'),
        findsOneWidget,
      );
    });

    testWidgets('挑む前の定義の読み直しに失敗したら、エラーをそのまま出してバトルを始めない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      dexStore
        ..replaceAll(monsters: sampleData.monsters)
        ..connectServer(
          savePartyMonsterIds: ({required monsterIds}) async {},
          refreshDefinitions: () async =>
              throw StateError('Firestore に master が投入されていません'),
        );
      await tester.tap(find.byKey(const Key('tab-opponent')));
      await tester.pumpAndSettle();
      final challengeButton = find.byKey(const Key('challenge-$cpuOpponentId'));
      await tester.ensureVisible(challengeButton);
      await tester.pumpAndSettle();
      await tester.tap(challengeButton);
      await tester.pumpAndSettle();
      expect(
        find.text('Bad state: Firestore に master が投入されていません'),
        findsOneWidget,
      );
      expect(find.textContaining('技をえらぶ'), findsNothing);
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
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('challenge-$cpuOpponentId')),
            )
            .onPressed,
        isNull,
      );
      // 他のユーザーの相手は自分の手持ちの平均レベルから選ぶため、手持ちが入るまで探さない
      expect(pvpCalls.fetchOpponentsCount, 0);
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
    expect(battleCalls.loggedEvents.single.parameters?['opponent'], 'cpu');
    // 先頭の手持ちは必ず場に出るため、勝敗に関係なくレベルが 1 上がる
    expect(dexStore.party.first.level, partyBefore.first.level + 1);

    await tester.tap(find.text('もどる'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('相手をえらぶ'), findsOneWidget);
  });

  testWidgets('ログインして記録した対戦は勝敗の画面に記録しましたと出し、Functions が返したレベルを図鑑に反映する', (
    tester,
  ) async {
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

  testWidgets(
    '他のユーザーの手持ちに挑むと、相手のその場で作った定義を読んでから決着まで戦え、計測に opponent: pvp を付ける',
    (tester) async {
      pvpClient = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [
          PvpOpponent(
            opponentUid: 'opponent-uid-1',
            displayName: 'ろうそくや',
            monsters: [generatedWaxMonster(monsterId: 'opponent-wax-1')],
          ),
        ],
        // 相手のモンスターの属性・技 (dynamic-wax) は自分の図鑑の定義に無く、相手の定義を読んで初めて引ける
        extraDefinitions: MasterData.fromJson(json: waxDefinitionJson),
        battleRecord: (wins: 8, losses: 3),
        displayName: 'トレーナー 0001',
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
      );
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      dexStore.replaceAll(monsters: sampleData.monsters);
      expect(
        sampleData.definitions.elementTypes.map((element) => element.id),
        isNot(contains('dynamic-wax')),
      );
      await tester.tap(find.byKey(const Key('tab-opponent')));
      await tester.pumpAndSettle();
      expect(find.text('ろうそくや'), findsOneWidget);
      expect(find.text('平均 Lv. 1'), findsOneWidget);
      expect(find.text('8 勝 3 敗'), findsOneWidget);
      // 見本の対戦相手は、ログインして他のユーザーを読めた時は出さない
      expect(find.text(sampleData.opponents.first.name), findsNothing);

      final challengeButton = find.byKey(const Key('challenge-opponent-uid-1'));
      await tester.ensureVisible(challengeButton);
      await tester.pumpAndSettle();
      await tester.tap(challengeButton);
      // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(pvpCalls.fetchedDefinitionIds, [
        [waxDefinitionId],
      ]);
      expect(find.text('ロウソクン が 勝負をしかけてきた'), findsOneWidget);
      expect(find.text('ろう'), findsOneWidget);

      // 100 ターン: 見本の手持ちとレベル 1 の相手なら数ターンで決着するため、決着しない不具合でテストが止まらない上限として十分な数
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
      expect(tester.takeException(), isNull);
      expect(
        battleCalls.loggedEvents.single.event,
        AnalyticsEvent.battleCompleted,
      );
      expect(battleCalls.loggedEvents.single.parameters?['opponent'], 'pvp');
    },
  );

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
          opponentKind: BattleOpponentKind.cpu,
          definitions: sampleData.definitions,
          randomSeed: 1,
          battleRecorder: fakeBattleRecorder(
            calls: RecordedBattleCalls(),
            startBattleRecord: () async => null,
            recordedLevels: const {},
          ),
          onPlayerLevelsChanged: ({required levelsByMonsterId}) {},
          cardSharer: fakeCardSharer(
            calls: RecordedShareCalls(),
            artImage: null,
            shareResultStatus: ShareResultStatus.success,
          ),
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
        final settingsAgeConfirmationStore = AgeConfirmationStore(
          preferences: preferences,
          today: () => today,
        );
        final settingsSessionStore = fakeAgeVerifiedSessionStore(
          resumedUid: 'uid-resumed',
          failureCount: 0,
        );
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            home: SettingsScreen(
              sampleData: sampleData,
              dexStore: DexStore(definitions: sampleData.definitions),
              ageConfirmationStore: settingsAgeConfirmationStore,
              ageVerifiedSessionStore: settingsSessionStore,
              monsterGenerator: appMonsterGenerator(),
              pvpClient: signedOutPvpClient(calls: RecordedPvpCalls()),
              cardSharer: fakeCardSharer(
                calls: RecordedShareCalls(),
                artImage: null,
                shareResultStatus: ShareResultStatus.success,
              ),
              openUrl: openUrl,
              isDeveloperMenuEnabled: false,
              accountStore: fakeAccountStore(
                sessionStore: settingsSessionStore,
                ageConfirmationStore: settingsAgeConfirmationStore,
              ),
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

    testWidgets('表示名はサーバーが返した名前を出し、変えると保存した名前に変わる', (tester) async {
      pvpClient = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: (wins: 0, losses: 0),
        displayName: 'トレーナー 0042',
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async {
          if (displayName.contains('ピカチュウ')) {
            throw Exception('この表示名は使えません');
          }
          return displayName.trim();
        },
      );
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.text('トレーナー 0042'), findsOneWidget);

      await tester.tap(find.byKey(const Key('display-name')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('display-name-field')),
        'ピカチュウ',
      );
      await tester.tap(find.byKey(const Key('display-name-save')));
      await tester.pumpAndSettle();
      // 使えない名前はダイアログに理由をそのまま出して閉じない
      expect(find.text('Exception: この表示名は使えません'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('display-name-field')),
        ' ばんざい ',
      );
      await tester.tap(find.byKey(const Key('display-name-save')));
      await tester.pumpAndSettle();
      expect(pvpCalls.updatedDisplayNames, ['ピカチュウ', ' ばんざい ']);
      expect(find.byKey(const Key('display-name-field')), findsNothing);
      expect(find.text('ばんざい'), findsOneWidget);
    });

    testWidgets('ログインが無い時は表示名の項目を出さない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('display-name')), findsNothing);
      expect(find.text('お問い合わせ'), findsOneWidget);
    });

    /// 年齢の確認とログインを済ませた状態で起動し、設定画面を開く。
    Future<void> openSettings({required WidgetTester tester}) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'アカウントを削除は、確認ダイアログで「削除する」を選ぶと消してから年齢の確認の画面に戻る (docs/AccountDeletion.md の手順)',
      (tester) async {
        await openSettings(tester: tester);
        final endSessionCallCountBeforeDeletion = endSessionCallCount;
        await tester.tap(find.text('アカウントを削除'));
        await tester.pumpAndSettle();
        expect(find.text('アカウントを削除しますか'), findsOneWidget);

        await tester.tap(find.text('削除する'));
        await tester.pumpAndSettle();

        expect(accountCalls, ['delete']);
        expect(endSessionCallCount, endSessionCallCountBeforeDeletion + 1);
        expect(ageVerifiedSessionStore.uid, isNull);
        expect(ageConfirmationStore.status, AgeConfirmationStatus.unanswered);
        expect(find.text('生まれた年と月を\n入力してください'), findsOneWidget);
      },
    );

    testWidgets('アカウントを削除の確認で「やめる」を選ぶと消さない', (tester) async {
      await openSettings(tester: tester);
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();

      expect(accountCalls, isEmpty);
      expect(ageVerifiedSessionStore.uid, 'uid-resumed');
      expect(find.text('アカウントを削除'), findsOneWidget);
    });

    testWidgets('アカウントの削除に失敗したら理由をそのまま出し、ログインを続ける', (tester) async {
      deleteAccount = () async => throw Exception('deadline-exceeded');
      await openSettings(tester: tester);
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();

      expect(find.text('Exception: deadline-exceeded'), findsOneWidget);
      expect(ageVerifiedSessionStore.uid, 'uid-resumed');
      expect(ageConfirmationStore.status, AgeConfirmationStatus.allowed);
    });

    testWidgets('データを引き継ぐで連携すると、連携済みの表示になり押せなくなる', (tester) async {
      await openSettings(tester: tester);
      expect(find.text('Google でサインインして\n機種変更しても図鑑を残す'), findsOneWidget);

      await tester.tap(find.text('データを引き継ぐ'));
      await tester.pumpAndSettle();

      expect(find.text('Google と連携しました'), findsOneWidget);
      expect(find.text('Google で連携済み'), findsOneWidget);
      expect(ageVerifiedSessionStore.uid, 'uid-resumed');
      await tester.tap(find.text('データを引き継ぐ'));
      await tester.pumpAndSettle();
      expect(accountCalls, ['link']);
    });

    testWidgets('別の端末で連携済みなら、確認してからこの端末の匿名アカウントを捨てて切り替える', (tester) async {
      linkAccount = () async => () async {
        accountCalls.add('signInToLinkedAccount');
        return 'uid-linked';
      };
      await openSettings(tester: tester);
      await tester.tap(find.text('データを引き継ぐ'));
      await tester.pumpAndSettle();
      expect(find.text('連携済みのアカウントに切り替えますか'), findsOneWidget);

      await tester.tap(find.text('切り替える'));
      await tester.pumpAndSettle();

      expect(accountCalls, ['link', 'discard', 'signInToLinkedAccount']);
      expect(ageVerifiedSessionStore.uid, 'uid-linked');
      expect(find.text('連携済みのアカウントに切り替えました'), findsOneWidget);
    });

    testWidgets('別の端末で連携済みの確認で「やめる」を選ぶと、匿名アカウントを捨てない', (tester) async {
      linkAccount = () async =>
          () async => 'uid-linked';
      await openSettings(tester: tester);
      await tester.tap(find.text('データを引き継ぐ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();

      expect(accountCalls, ['link']);
      expect(ageVerifiedSessionStore.uid, 'uid-resumed');
    });

    testWidgets('ログインを飛ばした時 (DEBUG) は、データを引き継ぐとアカウントを削除を押せない', (tester) async {
      await pumpApp(
        tester: tester,
        hasConfirmedAge: true,
        hasStartedSession: false,
        startSessionFailureCount: 1,
        isDeveloperMenuEnabled: true,
      );
      await tester.tap(find.text('ログインせずに進む (DEBUG)'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('データを引き継ぐ'));
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();

      expect(accountCalls, isEmpty);
      expect(find.text('アカウントを削除しますか'), findsNothing);
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
      dexStore.connectServer(
        savePartyMonsterIds: ({required monsterIds}) async {},
        refreshDefinitions: () async {},
      );
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
