import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/app.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/home/home_shell.dart';
import 'package:snapmon/features/opponent/opponent_safety_actions.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/features/session/session_store.dart';
import 'package:snapmon/features/settings/account_store.dart';
import 'package:snapmon/features/settings/settings_screen.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/share_cards.dart';
import 'package:snapmon/features/title/title_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/sample/sample_data.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import 'battle_recorder_fixture.dart';
import 'card_sharer_fixture.dart';
import 'monster_generator_fixture.dart';
import 'pvp_client_fixture.dart';
import 'sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// 起動した [SnapmonApp] と、テストから覗く状態。
  late DexStore dexStore;
  late SessionStore sessionStore;
  var startSessionCallCount = 0;
  var endSessionCallCount = 0;
  late List<Uri> openedUris;
  late RecordedBattleCalls battleCalls;
  late RecordedGenerationCalls generationCalls;

  /// タイトル画面が Analytics に送ったイベント (呼ばれた順)。
  late List<({AnalyticsEvent event, Map<String, Object>? parameters})>
  titleEvents;

  /// [pumpApp]・[pumpHome] のアルバムが返す写真。既定は選んだ。選ばずに閉じた (null) にするテストは [pumpApp] の前に変える。
  late Uint8List? albumPhoto;

  /// ログインの通信が遅い状態を作る。null 以外なら、ログインは complete するまで終わらない。
  Completer<void>? startSessionGate;

  /// 生成に時間がかかる状態を作る。null 以外なら、[appMonsterGenerator] の生成は complete するまで終わらない。
  Completer<void>? generationGate;

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

  /// [pumpApp]・[pumpHome] の切り出した画像の読み込みが返す画像。見本のモンスターは同梱の画像を持つため、共有のカードを描けるよう読めることにする。
  late ui.Image artImage;

  /// [pumpApp] の設定画面のアカウントの連携と削除。呼ばれた操作を [accountCalls] に順に残す。
  /// 連携と削除の振る舞いは、テストが [pumpApp] の前に変える。既定は連携でき、削除できる。
  late AccountStore accountStore;
  late List<String> accountCalls;
  late List<String> linkedProviderNames;
  late Future<Future<String> Function()?> Function() linkAccount;
  late Future<void> Function() deleteAccount;

  setUp(() {
    albumPhoto = testPhotoBytes;
    startSessionGate = null;
    generationGate = null;
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

  /// [sessionStore] に繋いだ、Firebase を呼ばない [AccountStore]。
  AccountStore fakeAccountStore({required SessionStore sessionStore}) =>
      AccountStore(
        sessionStore: sessionStore,
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
    albumPhoto: albumPhoto,
    uploadError: null,
    requestGeneration: ({required requestId}) async {
      await generationGate?.future;
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

  /// Firebase を呼ばずに [startSessionCallCount] へ呼んだ回数を残すログイン。
  /// 先頭から [failureCount] 回は通信の失敗を投げ、その後は uid を返す。
  SessionStore fakeSessionStore({
    required String? resumedUid,
    required int failureCount,
  }) {
    var remainingFailureCount = failureCount;
    return SessionStore(
      startSession: () async {
        startSessionCallCount++;
        await startSessionGate?.future;
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

  /// [pumpApp]・[pumpHome] が使う状態を、iPhone の画面の大きさ (モックの 390 × 844) で作る。
  /// [hasStartedSession] が true なら、前回の起動で済ませたログインを再開した状態にする。ログインは先頭から [startSessionFailureCount] 回失敗する。
  Future<void> prepareStores({
    required WidgetTester tester,
    required bool hasStartedSession,
    required int startSessionFailureCount,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    dexStore = DexStore(definitions: sampleData.definitions);
    generationCalls = RecordedGenerationCalls();
    titleEvents = [];
    startSessionCallCount = 0;
    sessionStore = fakeSessionStore(
      resumedUid: hasStartedSession ? 'uid-resumed' : null,
      failureCount: startSessionFailureCount,
    );
    openedUris = [];
    battleCalls = RecordedBattleCalls();
    shareCalls = RecordedShareCalls();
    artImage = (await tester.runAsync(
      () => createTestImage(width: 8, height: 8),
    ))!;
    addTearDown(artImage.dispose);
    accountStore = fakeAccountStore(sessionStore: sessionStore);
  }

  /// [prepareStores] の状態で [SnapmonApp] を起動する (最初の画面はタイトル)。
  /// タイトルの浮遊・オーラのアニメーションは繰り返して止まらないため、端末の「視差効果を減らす」を有効にして pumpAndSettle を使えるようにする。
  Future<void> pumpApp({
    required WidgetTester tester,
    required bool hasStartedSession,
    required int startSessionFailureCount,
    required bool isDeveloperMenuEnabled,
  }) async {
    await prepareStores(
      tester: tester,
      hasStartedSession: hasStartedSession,
      startSessionFailureCount: startSessionFailureCount,
    );
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    // SnapmonApp は端末の言語で文言を選ぶ。テストは原文 (日本語) の文言で画面を探すため、端末の言語を日本語にする
    tester.platformDispatcher.localesTestValue = const [Locale('ja')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(
      SnapmonApp(
        sampleData: sampleData,
        dexStore: dexStore,
        sessionStore: sessionStore,
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
          artImage: artImage,
          shareResultStatus: shareResultStatus,
        ),
        accountStore: accountStore,
        logEvent: ({required event, required parameters}) async =>
            titleEvents.add((event: event, parameters: parameters)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// [prepareStores] の状態で、タイトル画面からログインを済ませて入った後の下タブの画面 ([HomeShell]) を撮るタブから開く。
  /// タイトルから入る経路はタイトル画面のテストが固定するため、下タブより先の画面のテストはここから始める。
  Future<void> pumpHome({
    required WidgetTester tester,
    required bool hasStartedSession,
    required int startSessionFailureCount,
    required bool isDeveloperMenuEnabled,
    required bool startsCameraOnCaptureOpen,
  }) async {
    await prepareStores(
      tester: tester,
      hasStartedSession: hasStartedSession,
      startSessionFailureCount: startSessionFailureCount,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeShell(
          initialTab: HomeTab.capture,
          startsCameraOnCaptureOpen: startsCameraOnCaptureOpen,
          sampleData: sampleData,
          dexStore: dexStore,
          sessionStore: sessionStore,
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
            artImage: artImage,
            shareResultStatus: shareResultStatus,
          ),
          accountStore: accountStore,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// タイトル画面の「写真から選んではじめる」を押す。
  Future<void> tapStartFromAlbum({required WidgetTester tester}) async {
    await tester.tap(find.byKey(const Key('title-album')));
    await tester.pumpAndSettle();
  }

  /// 図鑑と手持ちに見本のモンスターを 1 体入れる。写真を選んだ時に手持ちがあるため、初回の導線 (生まれたらそのまま戦う) ではなく
  /// 2 回目以降の導線 (生まれたカードを出す) になる。
  Future<void> seedPartyWithOneMonster({required WidgetTester tester}) async {
    dexStore.replaceAll(monsters: [sampleData.monsters.first]);
    await tester.pumpAndSettle();
  }

  /// 図鑑に見本を入れて、タイトル画面の「つづきから」で下タブの画面に入る。
  Future<void> enterHomeFromTitle({required WidgetTester tester}) async {
    dexStore.replaceAll(monsters: sampleData.monsters);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('title-continue')));
    await tester.pumpAndSettle();
  }

  group('タイトル画面', () {
    testWidgets('起動直後にタイトル画面が出て、年齢などの入力を挟まずに裏で匿名ログインする', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(find.text('snapmon'), findsOneWidget);
      expect(find.text('身の回りの物が\nモンスターになって戦う'), findsOneWidget);
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(find.text('$minimumAge 歳以上が対象 · '), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('tab-dex')), findsNothing);
      // タイトルを見ている間に裏でログインし、ログインより前に溜めたタイトルの表示をログインの後に送る
      expect(startSessionCallCount, 1);
      expect(sessionStore.uid, 'uid-1');
      expect(titleEvents.map((logged) => logged.event), [
        AnalyticsEvent.titleShown,
      ]);
    });

    testWidgets('図鑑が空なら「つづきから」が無く、図鑑に 1 体入ると「つづきから (図鑑 1)」が出る', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(find.byKey(const Key('title-continue')), findsNothing);

      // 図鑑は Firestore から後から届く
      dexStore.applyServerSnapshot(
        monsters: [generatedWaxMonster(monsterId: 'm1')],
        partyMonsterIds: null,
        definitions: definitionsWithWax(base: sampleData.definitions),
      );
      await tester.pumpAndSettle();
      expect(find.text('つづきから (図鑑 1)'), findsOneWidget);
    });

    testWidgets('図鑑の読み込みに失敗した時は数なしの「つづきから」が出て、図鑑の「もう一度読み込む」に行ける', (
      tester,
    ) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(find.byKey(const Key('title-continue')), findsNothing);
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
      await tester.pumpAndSettle();
      expect(find.text('つづきから'), findsOneWidget);

      await tester.tap(find.byKey(const Key('title-continue')));
      await tester.pumpAndSettle();
      expect(find.text('Bad state: 通信できません'), findsOneWidget);
      await tester.tap(find.text('もう一度読み込む'));
      await tester.pumpAndSettle();
      expect(
        find.text('${sampleData.monsters.length} 体 · 手持ち 0 体'),
        findsOneWidget,
      );
    });

    testWidgets('カメラが無い時は「カメラで撮ってはじめる」が無い', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      // fakeMonsterGenerator のカメラの一覧は空
      expect(find.text('カメラで撮ってはじめる'), findsNothing);
      expect(find.byKey(const Key('title-album')), findsOneWidget);
    });

    testWidgets(
      '手持ちがある時は「写真から選んではじめる」で写真を選ぶと生成の画面に進み、生まれたカードが出て、手持ちに入れると図鑑に入る',
      (tester) async {
        await pumpApp(
          tester: tester,
          hasStartedSession: true,
          startSessionFailureCount: 0,
          isDeveloperMenuEnabled: false,
        );
        await seedPartyWithOneMonster(tester: tester);
        await tapStartFromAlbum(tester: tester);
        final bornMonster = generatedWaxMonster(
          monsterId: 'generated-request-1',
        ).definition;
        expect(find.text('あたらしい なかま'), findsOneWidget);
        expect(find.text(bornMonster.name), findsOneWidget);
        expect(generationCalls.uploadedRequestIds, ['request-1']);
        expect(
          generationCalls.loggedEvents.single.event,
          AnalyticsEvent.monsterGenerated,
        );
        expect(titleEvents.map((logged) => logged.event), [
          AnalyticsEvent.titleShown,
          AnalyticsEvent.titleAction,
        ]);
        expect(titleEvents.last.parameters, {'action': 'album'});

        await tester.tap(find.text('手持ちに入れる'));
        await tester.pumpAndSettle();
        expect(find.text('2 体 · 手持ち 2 体'), findsOneWidget);
        expect(find.byKey(const Key('tab-capture')), findsOneWidget);
      },
    );

    testWidgets('生まれた画面の「もう 1 体撮る」でタイトルではなく撮る画面に進む', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await seedPartyWithOneMonster(tester: tester);
      await tapStartFromAlbum(tester: tester);
      await tester.tap(find.text('もう 1 体撮る'));
      await tester.pumpAndSettle();
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
      expect(find.text('図鑑 2'), findsOneWidget);
    });

    testWidgets('「写真から選んではじめる」で選ばずに閉じた時はタイトルに留まる', (tester) async {
      albumPhoto = null;
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await tapStartFromAlbum(tester: tester);
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(find.text('あたらしい なかま'), findsNothing);
      expect(generationCalls.uploadedRequestIds, isEmpty);
      // 押したことは選ばなくても数える (押した数に対する生成の数を見るため)
      expect(titleEvents.last.event, AnalyticsEvent.titleAction);
      expect(titleEvents.last.parameters, {'action': 'album'});
    });

    testWidgets('写真を選んだ後にログインが失敗している時は「つながりませんでした」と再試行が出て、再試行で成功すると生成に進む', (
      tester,
    ) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: false,
        // タイトルの裏のログインと、ボタンを押した時のログイン (閉じて押し直すので 2 回) の計 3 回失敗する
        startSessionFailureCount: 3,
        isDeveloperMenuEnabled: false,
      );
      await seedPartyWithOneMonster(tester: tester);
      // タイトルを見ている間に裏でログインを始める。失敗はタイトルに出さない
      expect(startSessionCallCount, 1);
      expect(find.text('つながりませんでした'), findsNothing);
      expect(find.text('写真から選んではじめる'), findsOneWidget);

      // ボタンを押した時のログインが終わるまで、ログインの画面は前回 (裏のログイン) のエラーではなく「じゅんびしています」を出す
      startSessionGate = Completer<void>();
      await tester.tap(find.byKey(const Key('title-album')));
      await tester.pump();
      await tester.pump();
      expect(startSessionCallCount, 2);
      expect(find.text('じゅんびしています'), findsOneWidget);
      expect(find.text('つながりませんでした'), findsNothing);
      startSessionGate!.complete();
      startSessionGate = null;
      await tester.pumpAndSettle();
      expect(find.text('つながりませんでした'), findsOneWidget);
      expect(find.text('Exception: network-request-failed'), findsOneWidget);
      expect(find.text('ログインせずに進む (DEBUG)'), findsNothing);
      expect(find.text('あたらしい なかま'), findsNothing);
      expect(sessionStore.uid, isNull);

      // 閉じるでタイトルに戻れる (Web には OS の戻る操作が無いため)。写真の選択は無かったことになり、生成には進まない
      await tester.tap(find.byTooltip('閉じる'));
      await tester.pumpAndSettle();
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(find.text('つながりませんでした'), findsNothing);
      expect(generationCalls.uploadedRequestIds, isEmpty);

      await tester.tap(find.byKey(const Key('title-album')));
      await tester.pumpAndSettle();
      expect(find.text('つながりませんでした'), findsOneWidget);
      await tester.tap(find.text('もう一度試す'));
      await tester.pumpAndSettle();
      expect(startSessionCallCount, 4);
      expect(sessionStore.uid, 'uid-1');
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('裏のログインが終わる前に写真を選ぶと「じゅんびしています」を出し、ログインが終わると生成に進む', (
      tester,
    ) async {
      startSessionGate = Completer<void>();
      await pumpApp(
        tester: tester,
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(startSessionCallCount, 1);
      await seedPartyWithOneMonster(tester: tester);
      await tester.tap(find.byKey(const Key('title-album')));
      // ログインの画面の進捗の表示は止まらないため、pumpAndSettle を使わず 1 フレームずつ進める
      await tester.pump();
      await tester.pump();
      expect(find.text('じゅんびしています'), findsOneWidget);
      // 裏のログインが途中なので、ログインの画面が start を呼んでも 2 回目のログインは始まらない
      expect(startSessionCallCount, 1);

      startSessionGate!.complete();
      await tester.pumpAndSettle();
      expect(sessionStore.uid, 'uid-1');
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('「つづきから」を押すと下タブの画面 (撮る・図鑑・対戦のタブ) が図鑑から出る', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await enterHomeFromTitle(tester: tester);
      expect(find.byKey(const Key('tab-dex')), findsOneWidget);
      expect(find.byKey(const Key('tab-capture')), findsOneWidget);
      expect(find.byKey(const Key('tab-opponent')), findsOneWidget);
      expect(
        find.text('${sampleData.monsters.length} 体 · 手持ち 3 体'),
        findsOneWidget,
      );
      expect(titleEvents.last.parameters, {'action': 'continue'});
    });

    testWidgets('図鑑が空でも、タイトルの設定から写真を選ばずにデータの引き継ぎとアカウントの削除に行ける', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(find.byKey(const Key('title-continue')), findsNothing);
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.text('設定'), findsOneWidget);
      expect(find.text('データを引き継ぐ'), findsOneWidget);
      expect(find.text('アカウントを削除'), findsOneWidget);
      expect(generationCalls.uploadedRequestIds, isEmpty);

      // 戻るとタイトルに戻る (下タブには入らない)。pageBack は英語の tooltip (Back) で探すため型で探す
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(find.byKey(const Key('tab-dex')), findsNothing);
    });

    testWidgets('タイトルの設定からアカウントを削除した後は、裏でログインし直して title_shown を送り直す', (
      tester,
    ) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(titleEvents.map((logged) => logged.event), [
        AnalyticsEvent.titleShown,
      ]);
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('削除する'));
      await tester.pumpAndSettle();
      expect(accountCalls, ['delete']);
      // タイトルは作り直されないが、開き直したのと同じく裏でログインし直し、済んだ時に title_shown を送る
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(startSessionCallCount, 1);
      expect(sessionStore.uid, 'uid-1');
      expect(titleEvents.map((logged) => logged.event), [
        AnalyticsEvent.titleShown,
        AnalyticsEvent.titleShown,
      ]);
    });

    testWidgets('利用規約とプライバシーは設定画面と同じ URL を開く', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await tester.tap(find.text('利用規約'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('プライバシー'));
      await tester.pumpAndSettle();
      expect(openedUris, [termsUri, privacyPolicyUri]);
    });

    testWidgets('前回の起動でログインを済ませた時は、タイトルでログインを始めない', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(startSessionCallCount, 0);
      expect(find.text('写真から選んではじめる'), findsOneWidget);
    });

    testWidgets('端末の文字を 2 倍にしてもタイトルのボタンがはみ出さず、写真から選べる', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
      expect(tester.takeException(), isNull);
      expect(find.text('写真から選んではじめる'), findsOneWidget);

      await seedPartyWithOneMonster(tester: tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('title-album')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tapStartFromAlbum(tester: tester);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('高さの低い画面でもタイトルがはみ出さず、スクロールして写真から選べる', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
      expect(tester.takeException(), isNull);

      await seedPartyWithOneMonster(tester: tester);
      await tester.scrollUntilVisible(
        find.byKey(const Key('title-album')),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tapStartFromAlbum(tester: tester);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });
  });

  group('ログイン (タイトルのボタンを押した時)', () {
    testWidgets('開発者メニューが有効な時だけ、ログインに失敗した画面からログインせずに進める', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: false,
        // タイトルの裏のログインと、ボタンを押した時のログインの 2 回失敗する
        startSessionFailureCount: 2,
        isDeveloperMenuEnabled: true,
      );
      await seedPartyWithOneMonster(tester: tester);
      await tapStartFromAlbum(tester: tester);
      expect(find.text('つながりませんでした'), findsOneWidget);
      await tester.tap(find.text('ログインせずに進む (DEBUG)'));
      await tester.pumpAndSettle();
      expect(find.text('あたらしい なかま'), findsOneWidget);

      await tester.tap(find.text('手持ちに入れる'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      expect(find.text('未ログイン (ログインを DEBUG で飛ばした)'), findsOneWidget);
    });

    testWidgets('ログインが済んでいない時は、タイトルを開くと裏でログインを始める', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(startSessionCallCount, 1);
      expect(sessionStore.uid, 'uid-1');
      // ログインが済んでもタイトルに留まり、ボタンを押すまで下タブに入らない
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(find.byKey(const Key('tab-dex')), findsNothing);

      await seedPartyWithOneMonster(tester: tester);
      await tapStartFromAlbum(tester: tester);
      expect(startSessionCallCount, 1);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });
  });

  group('初回の導線 (手持ちが空の時)', () {
    /// 初回のバトルを決着まで進める (初回のバトルの勝敗の画面には「もどる」の代わりに「もう 1 体撮る」が出る)。
    /// バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める。
    Future<void> playFirstBattleUntilFinished({
      required WidgetTester tester,
    }) async {
      // 100 ターン: レベル 1 同士なら数ターンで決着するため、決着しない不具合でテストが止まらない上限として十分な数
      for (
        var turn = 0;
        turn < 100 &&
            find
                .byKey(const Key('first-battle-capture-again'))
                .evaluate()
                .isEmpty;
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
    }

    testWidgets(
      'タイトルで写真を選ぶと生成の完了を待たずに相手を探す画面に進み、生まれると手持ちに入れて PvP の相手とバトルし、決着で生まれたカードと勝敗が同じ画面に出る',
      (tester) async {
        generationGate = Completer<void>();
        pvpClient = fakePvpClient(
          calls: pvpCalls,
          fetchOpponents: () async => [
            PvpOpponent(
              opponentUid: 'opponent-uid-1',
              displayName: 'ろうそくや',
              monsters: [generatedWaxMonster(monsterId: 'opponent-wax-1')],
            ),
          ],
          extraDefinitions: MasterData.fromJson(json: waxDefinitionJson),
          battleRecord: null,
          displayName: null,
          reportMonster: () async {},
          blockUser: () async {},
          updateDisplayName: ({required displayName}) async => displayName,
        );
        await pumpApp(
          tester: tester,
          hasStartedSession: true,
          startSessionFailureCount: 0,
          isDeveloperMenuEnabled: false,
        );
        await tester.tap(find.byKey(const Key('title-album')));
        // 相手を探す表示の進捗は止まらないため、pumpAndSettle を使わず時間を指定して進める
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        // 生成はまだ終わっていない
        expect(generationCalls.requestedRequestIds, ['request-1']);
        expect(find.text('相手を探しています'), findsOneWidget);
        expect(find.text('あたらしい なかま'), findsNothing);
        expect(find.byType(BattleScreen), findsNothing);
        expect(pvpCalls.fetchOpponentsCount, 0);

        generationGate!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        const bornMonsterId = 'generated-request-1';
        expect(dexStore.party.map((monster) => monster.definition.id), [
          bornMonsterId,
        ]);
        expect(find.text('ろうそくや があらわれた'), findsOneWidget);
        expect(pvpCalls.fetchOpponentsCount, 1);
        expect(pvpCalls.fetchedDefinitionIds, [
          [waxDefinitionId],
        ]);

        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(BattleScreen), findsOneWidget);
        expect(find.byKey(const Key('first-battle-hint')), findsOneWidget);
        expect(find.text('ロウソクン が 勝負をしかけてきた'), findsOneWidget);

        // 初回の相手は対戦相手の画面を通らずに当たるため、バトルの画面から通報とブロックができ、した後もバトルは続く
        Future<void> openOpponentSafetyMenu() async {
          await tester.tap(
            find.byKey(const Key('opponent-menu-opponent-uid-1')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        }

        await openOpponentSafetyMenu();
        await tester.tap(find.text('ロウソクン を通報'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byKey(const Key('report-reason-other')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('report-submit')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          [
            for (final report in pvpCalls.reports)
              (report.monsterOwnerUid, report.monsterId),
          ],
          [('opponent-uid-1', 'opponent-wax-1')],
        );
        expect(find.text('通報しました'), findsOneWidget);

        await openOpponentSafetyMenu();
        await tester.tap(find.text('このトレーナーをブロック'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.byKey(const Key('block-confirm')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(pvpCalls.blockedUids, ['opponent-uid-1']);
        expect(find.text('ブロックしました'), findsOneWidget);
        expect(find.byType(BattleScreen), findsOneWidget);
        // 技のボタンを押す前に、ボタンに重なるスナックバーが消えるまで進める
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 1));

        await playFirstBattleUntilFinished(tester: tester);
        // 決着の後も通報・ブロックできる
        expect(
          find.byKey(const Key('opponent-menu-opponent-uid-1')),
          findsOneWidget,
        );
        final bornMonster = generatedWaxMonster(
          monsterId: bornMonsterId,
        ).definition;
        // 生まれたカードと勝敗が同じ画面に出る
        expect(find.text('あたらしい なかま'), findsOneWidget);
        expect(find.text(bornMonster.encyclopediaText), findsOneWidget);
        // AI 生成の開示は利用規約・プライバシーポリシー・ストアの説明文で行い、画面には出さない
        expect(find.textContaining('AI が作りました'), findsNothing);
        expect(
          find.text('かった').evaluate().length +
              find.text('まけた').evaluate().length,
          1,
        );
        expect(find.text('${bornMonster.name}  Lv. 1 → 2'), findsOneWidget);
        expect(find.text('結果を共有'), findsOneWidget);
        expect(find.text('図鑑を見る'), findsOneWidget);
        expect(find.text('もどる'), findsNothing);
        expect(tester.takeException(), isNull);

        expect(
          [
            for (final logged in generationCalls.loggedEvents)
              logged.event == AnalyticsEvent.firstExperience
                  ? logged.parameters!['step']
                  : logged.event.eventName,
          ],
          [
            'photo_selected',
            'monster_generated',
            'matchmaking',
            'battle_started',
          ],
        );
        expect(
          [
            for (final logged in battleCalls.loggedEvents)
              logged.event == AnalyticsEvent.firstExperience
                  ? logged.parameters!['step']
                  : logged.event.eventName,
          ],
          ['battle_completed', 'battle_completed'],
        );
        expect(battleCalls.loggedEvents.first.parameters?['opponent'], 'pvp');
        expect(
          battleCalls.loggedEvents.last.event,
          AnalyticsEvent.firstExperience,
        );

        // 「もう 1 体撮る」で撮るタブに進む。手持ちがあるので、撮るタブの初回の案内はもう出ない
        await tester.tap(find.byKey(const Key('first-battle-capture-again')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(BattleScreen), findsNothing);
        expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
        expect(find.text('図鑑 1'), findsOneWidget);
        expect(find.byKey(const Key('capture-first-hint')), findsNothing);
      },
    );

    testWidgets(
      '撮るタブは手持ちが空の時に案内を出し、アルバムから選ぶと PvP の候補が無い時は CPU トレーナーと戦い、「図鑑を見る」で図鑑に入る',
      (tester) async {
        await pumpHome(
          tester: tester,
          hasStartedSession: true,
          startSessionFailureCount: 0,
          isDeveloperMenuEnabled: false,
          startsCameraOnCaptureOpen: false,
        );
        // テストの環境にはカメラが無いため、選ぶ案内になる
        expect(find.text('身の回りの物の写真を 1 枚選ぼう'), findsOneWidget);

        await tester.tap(find.byTooltip('アルバムから選ぶ'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final cpuOpponent = sampleData.opponents.firstWhere(
          (opponent) => opponent.id == cpuOpponentId,
        );
        expect(find.text('${cpuOpponent.name} があらわれた'), findsOneWidget);
        // ログインが無い時の候補 (null) を読んだ上で CPU トレーナーにする
        expect(pvpCalls.fetchOpponentsCount, 1);

        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(BattleScreen), findsOneWidget);
        // CPU トレーナーは他のユーザーではないため、通報・ブロックのメニューを出さない
        expect(find.byType(OpponentSafetyMenuButton), findsNothing);
        await playFirstBattleUntilFinished(tester: tester);
        expect(battleCalls.loggedEvents.first.parameters?['opponent'], 'cpu');

        await tester.tap(find.text('図鑑を見る'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('1 体 · 手持ち 1 体'), findsOneWidget);
      },
    );
  });

  group('下タブと画面の遷移', () {
    testWidgets('下タブで図鑑・撮る・対戦を切り替える', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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

    testWidgets('手持ちがある時はアルバムから選ぶと生成して生まれた画面が開き、手持ちに入れると図鑑に戻る', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await seedPartyWithOneMonster(tester: tester);
      await tester.tap(find.byTooltip('アルバムから選ぶ'));
      await tester.pumpAndSettle();
      final bornMonster = generatedWaxMonster(
        monsterId: 'generated-request-1',
      ).definition;
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(find.text(bornMonster.name), findsOneWidget);
      // AI 生成の開示は利用規約・プライバシーポリシー・ストアの説明文で行い、画面には出さない
      expect(find.textContaining('AI が作りました'), findsNothing);
      expect(generationCalls.uploadedRequestIds, ['request-1']);
      expect(
        generationCalls.loggedEvents.single.event,
        AnalyticsEvent.monsterGenerated,
      );
      expect(dexStore.monsters.map((monster) => monster.definition.id), [
        sampleData.monsters.first.definition.id,
        bornMonster.id,
      ]);

      await tester.tap(find.text('手持ちに入れる'));
      await tester.pumpAndSettle();
      expect(find.text('2 体 · 手持ち 2 体'), findsOneWidget);
      // 手持ちの枠と「すべて」の両方に出る
      expect(find.text(bornMonster.name), findsNWidgets(2));
    });

    testWidgets('生まれた画面の「もう 1 体撮る」で撮る画面に戻る', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await seedPartyWithOneMonster(tester: tester);
      await tester.tap(find.byTooltip('アルバムから選ぶ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('もう 1 体撮る'));
      await tester.pumpAndSettle();
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
      expect(find.text('図鑑 2'), findsOneWidget);
    });

    testWidgets('生まれた画面から図鑑のカードを形を選んで共有し、共有イベントを送る', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await seedPartyWithOneMonster(tester: tester);
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
        // カードは画面の木の外で描くため、Localizations で包んで渡す
        ((rendered.card as Localizations).child! as MonsterShareCard)
            .monster
            .definition
            .id,
        bornMonster.id,
      );
      // 切り出した画像を持たないモンスターは画像を読まない
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      tester.view.physicalSize = const Size(844, 390);
      await tester.pumpAndSettle();
      // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
      expect(tester.takeException(), isNull);

      await seedPartyWithOneMonster(tester: tester);
      await tester.scrollUntilVisible(
        find.byTooltip('アルバムから選ぶ'),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('アルバムから選ぶ'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, hasLength(2));
    });

    testWidgets('カメラが無い時は、シャッターでカメラを求めた後にファインダーでアルバムへ案内する', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      // 開いただけではカメラを求めない
      expect(find.textContaining('カメラが使えません'), findsNothing);
      expect(find.byKey(const Key('capture-use-camera')), findsOneWidget);
      await tester.tap(find.byTooltip('撮る'));
      await tester.pumpAndSettle();
      // fakeMonsterGenerator のカメラの一覧は空
      expect(find.textContaining('カメラが使えません\nアルバムから選んでください'), findsOneWidget);
      expect(generationCalls.uploadedRequestIds, isEmpty);
    });

    testWidgets(
      'タイトルの「カメラで撮ってはじめる」から来た時は撮るタブですぐカメラを求め、開けないままタブを切り替えて戻ると求め直さない',
      (tester) async {
        await pumpHome(
          tester: tester,
          hasStartedSession: true,
          startSessionFailureCount: 0,
          isDeveloperMenuEnabled: false,
          startsCameraOnCaptureOpen: true,
        );
        // fakeMonsterGenerator のカメラの一覧は空のため、開こうとして開けない
        expect(find.textContaining('カメラが使えません'), findsOneWidget);
        expect(find.byKey(const Key('capture-use-camera')), findsNothing);

        await tester.tap(find.byKey(const Key('tab-dex')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('tab-capture')));
        await tester.pumpAndSettle();
        expect(find.textContaining('カメラが使えません'), findsNothing);
        expect(find.byKey(const Key('capture-use-camera')), findsOneWidget);
      },
    );

    testWidgets('手持ちが 3 体の時に手持ちに入れようとすると、選んだ手持ちと入れ替わる', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
    await pumpHome(
      tester: tester,
      hasStartedSession: true,
      startSessionFailureCount: 0,
      isDeveloperMenuEnabled: false,
      startsCameraOnCaptureOpen: false,
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
    // 技の選び方の案内は初回の導線の 1 戦目だけに出す
    expect(find.byKey(const Key('first-battle-hint')), findsNothing);

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
    await pumpHome(
      tester: tester,
      hasStartedSession: true,
      startSessionFailureCount: 0,
      isDeveloperMenuEnabled: false,
      startsCameraOnCaptureOpen: false,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
    await pumpHome(
      tester: tester,
      hasStartedSession: true,
      startSessionFailureCount: 0,
      isDeveloperMenuEnabled: false,
      startsCameraOnCaptureOpen: false,
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
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
          firstBattleBornMonster: null,
          firstBattleMonsterIsNewlyBorn: false,
          opponentSafetyMenu: null,
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
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
      Future<void> pumpSettings({required OpenUrl openUrl}) async {
        final settingsSessionStore = fakeSessionStore(
          resumedUid: 'uid-resumed',
          failureCount: 0,
        );
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            locale: const Locale('ja'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: SettingsScreen(
              sampleData: sampleData,
              dexStore: DexStore(definitions: sampleData.definitions),
              sessionStore: settingsSessionStore,
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
              ),
              battleRecorder: fakeBattleRecorder(
                calls: RecordedBattleCalls(),
                startBattleRecord: () async => null,
                recordedLevels: const {},
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.text('トレーナー 0042'), findsOneWidget);

      await tester.tap(find.byKey(const Key('display-name')));
      await tester.pumpAndSettle();
      // 外を押しても閉じない (保存の途中に閉じて、保存できた名前を反映しそこねないため)
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('display-name-field')), findsOneWidget);
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
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('display-name')), findsNothing);
      expect(find.text('お問い合わせ'), findsOneWidget);
    });

    /// ログインを済ませた状態で起動し、設定画面を開く。
    Future<void> openSettings({required WidgetTester tester}) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      'アカウントを削除は、確認ダイアログで「削除する」を選ぶと消してからタイトルに戻り、裏で新しい匿名アカウントにログインする (docs/AccountDeletion.md の手順)',
      (tester) async {
        await pumpApp(
          tester: tester,
          hasStartedSession: true,
          startSessionFailureCount: 0,
          isDeveloperMenuEnabled: false,
        );
        await enterHomeFromTitle(tester: tester);
        await tester.tap(find.byTooltip('設定'));
        await tester.pumpAndSettle();
        final endSessionCallCountBeforeDeletion = endSessionCallCount;
        await tester.tap(find.text('アカウントを削除'));
        await tester.pumpAndSettle();
        expect(find.text('アカウントを削除しますか'), findsOneWidget);

        await tester.tap(find.text('削除する'));
        await tester.pumpAndSettle();

        expect(accountCalls, ['delete']);
        expect(endSessionCallCount, endSessionCallCountBeforeDeletion + 1);
        expect(find.text('写真から選んではじめる'), findsOneWidget);
        expect(find.byKey(const Key('tab-dex')), findsNothing);
        expect(startSessionCallCount, 1);
        expect(sessionStore.uid, 'uid-1');
        await tapStartFromAlbum(tester: tester);
        expect(find.text('あたらしい なかま'), findsOneWidget);
      },
    );

    testWidgets('アカウントを削除の確認で「やめる」を選ぶと消さない', (tester) async {
      await openSettings(tester: tester);
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();

      expect(accountCalls, isEmpty);
      expect(sessionStore.uid, 'uid-resumed');
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
      expect(sessionStore.uid, 'uid-resumed');
    });

    testWidgets('データを引き継ぐで連携すると、連携済みの表示になり押せなくなる', (tester) async {
      await openSettings(tester: tester);
      expect(find.text('Google でサインインして\n機種変更しても図鑑を残す'), findsOneWidget);

      await tester.tap(find.text('データを引き継ぐ'));
      await tester.pumpAndSettle();

      expect(find.text('Google と連携しました'), findsOneWidget);
      expect(find.text('Google で連携済み'), findsOneWidget);
      expect(sessionStore.uid, 'uid-resumed');
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
      expect(sessionStore.uid, 'uid-linked');
      expect(find.text('連携済みのアカウントに切り替えました'), findsOneWidget);
    });

    testWidgets('連携済みのアカウントに切り替えると、表示名を切り替え先の名前に読み直す', (tester) async {
      linkAccount = () async =>
          () async => 'uid-linked';
      final signedInPvpClient = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: (wins: 0, losses: 0),
        displayName: null,
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
      );
      pvpClient = PvpClient(
        fetchOpponents: signedInPvpClient.fetchOpponents,
        fetchDefinitions: signedInPvpClient.fetchDefinitions,
        reportMonster: signedInPvpClient.reportMonster,
        blockUser: signedInPvpClient.blockUser,
        fetchBattleRecord: signedInPvpClient.fetchBattleRecord,
        fetchDisplayName: () async => switch (sessionStore.uid) {
          'uid-linked' => '切り替え先の名前',
          _ => '匿名の名前',
        },
        updateDisplayName: signedInPvpClient.updateDisplayName,
      );
      await openSettings(tester: tester);
      expect(find.text('匿名の名前'), findsOneWidget);

      await tester.tap(find.text('データを引き継ぐ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('切り替える'));
      await tester.pumpAndSettle();

      expect(sessionStore.uid, 'uid-linked');
      expect(find.text('匿名の名前'), findsNothing);
      expect(find.text('切り替え先の名前'), findsOneWidget);
    });

    testWidgets('対戦の画面から連携済みのアカウントに切り替えると、戦績を切り替え先の分に読み直す', (tester) async {
      linkAccount = () async =>
          () async => 'uid-linked';
      final signedInPvpClient = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: null,
        displayName: null,
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
      );
      pvpClient = PvpClient(
        fetchOpponents: signedInPvpClient.fetchOpponents,
        fetchDefinitions: signedInPvpClient.fetchDefinitions,
        reportMonster: signedInPvpClient.reportMonster,
        blockUser: signedInPvpClient.blockUser,
        fetchBattleRecord: () async => switch (sessionStore.uid) {
          'uid-linked' => (wins: 9, losses: 1),
          _ => (wins: 1, losses: 2),
        },
        fetchDisplayName: signedInPvpClient.fetchDisplayName,
        updateDisplayName: signedInPvpClient.updateDisplayName,
      );
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await tester.tap(find.byKey(const Key('tab-opponent')));
      await tester.pumpAndSettle();
      expect(find.text('1 勝 2 敗'), findsOneWidget);

      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('データを引き継ぐ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('切り替える'));
      await tester.pumpAndSettle();
      // pageBack は英語の tooltip (Back) で探すため、日本語の画面では戻るボタンを型で探す
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      expect(find.text('1 勝 2 敗'), findsNothing);
      expect(find.text('9 勝 1 敗'), findsOneWidget);
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
      expect(sessionStore.uid, 'uid-resumed');
    });

    testWidgets('ログインを飛ばした時 (DEBUG) は、データを引き継ぐとアカウントを削除を押せない', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
        startsCameraOnCaptureOpen: false,
      );
      // タイトルのログインの失敗の画面で「ログインせずに進む (DEBUG)」を押した状態
      sessionStore.skipForDebug();
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('データを引き継ぐ'));
      await tester.tap(find.text('アカウントを削除'));
      await tester.pumpAndSettle();

      expect(accountCalls, isEmpty);
      expect(find.text('アカウントを削除しますか'), findsNothing);
    });

    testWidgets('開発者メニューは無効の時に出ない', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.text('開発者メニュー'), findsNothing);
    });

    testWidgets('開発者メニューで見本の投入と図鑑のクリアができる', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
        startsCameraOnCaptureOpen: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      expect(find.text('匿名ログイン uid: uid-resumed'), findsOneWidget);

      await tester.tap(find.text('見本モンスターを図鑑に投入'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, hasLength(sampleData.monsters.length));
      expect(dexStore.party, hasLength(3));

      await tester.tap(find.text('図鑑をクリア'));
      await tester.pumpAndSettle();
      expect(dexStore.monsters, isEmpty);
    });

    testWidgets('サーバーの図鑑に繋いでいる時は、開発者メニューの見本の投入と図鑑のクリアを使えない', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
        startsCameraOnCaptureOpen: false,
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

    testWidgets('手持ちがある時は開発者メニューの見本の写真から生成すると、生まれた画面が開く', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
        startsCameraOnCaptureOpen: false,
      );
      await seedPartyWithOneMonster(tester: tester);
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

    testWidgets('開発者メニューで新しいアカウントで始め直すと、ログインを終えてタイトルに戻り、初回起動と同じく裏でログインする', (
      tester,
    ) async {
      endSessionCallCount = 0;
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
      );
      await enterHomeFromTitle(tester: tester);
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('新しいアカウントで始め直す'));
      await tester.pumpAndSettle();
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(endSessionCallCount, 1);
      expect(startSessionCallCount, 1);
      expect(sessionStore.uid, 'uid-1');

      await tapStartFromAlbum(tester: tester);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('開発者メニューでログインせずに使うと、ログインを終えてタイトルに戻り、ログインし直さずに見本の図鑑を使える', (
      tester,
    ) async {
      endSessionCallCount = 0;
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: true,
      );
      await enterHomeFromTitle(tester: tester);
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('開発者メニュー'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ログインせずに使う'));
      await tester.pumpAndSettle();
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(endSessionCallCount, 1);
      expect(startSessionCallCount, 0);
      expect(sessionStore.uid, isNull);
      expect(sessionStore.canEnterApp, isTrue);
    });
  });
}
