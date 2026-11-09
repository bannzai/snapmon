import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/app.dart';
import 'package:snapmon/audio/game_audio.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/capture_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_screen.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/home/home_shell.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/features/profile/profile_screen.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/features/session/session_store.dart';
import 'package:snapmon/features/settings/account_store.dart';
import 'package:snapmon/features/settings/settings_screen.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/share_cards.dart';
import 'package:snapmon/features/title/title_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/common_ui/storage_image.dart';
import 'package:snapmon/monster_ui/trainer_icon.dart';

import 'battle_recorder_fixture.dart';
import 'card_sharer_fixture.dart';
import 'game_audio_fixture.dart';
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

  /// 画面が流した BGM・鳴らした効果音。[pumpApp]・[pumpHome] で作り直す。
  late RecordedAudioCalls audioCalls;

  /// [pumpApp] の BGM が Web のように最初の操作を待つか。既定は待たない (iOS・Android)。待つテストは [pumpApp] の前に変える。
  var audioWaitsForUserInteraction = false;

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
    audioWaitsForUserInteraction = false;
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
        personDetected: false,
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
    audioCalls = RecordedAudioCalls();
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
        gameAudio: fakeGameAudio(
          calls: audioCalls,
          isBackgroundMusicEnabled: true,
          isSoundEffectsEnabled: true,
          waitsForUserInteractionBeforeBackgroundMusic:
              audioWaitsForUserInteraction,
        ),
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

  /// [prepareStores] の状態で、タイトル画面からログインを済ませて入った後のホームの画面 ([HomeShell]) を撮るのシーンから開く。
  /// タイトルから入る経路はタイトル画面のテストが固定するため、ホームの画面より先の画面のテストはここから始める。
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
      // 登録したアイコン (StorageImage) を Firebase を通さずに描く。中身は読めない (null) ものとし、既定の印を描かせる
      StorageImageLoaderScope(
        loadBytes: ({required storagePath}) async => null,
        child: GameAudioScope(
          gameAudio: fakeGameAudio(
            calls: audioCalls,
            isBackgroundMusicEnabled: true,
            isSoundEffectsEnabled: true,
            waitsForUserInteractionBeforeBackgroundMusic: false,
          ),
          child: MaterialApp(
            theme: snapmonThemeData(),
            locale: const Locale('ja'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeShell(
              initialScene: HomeScene.capture,
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

  /// 生成の画面で、OS の切り出しが見つけた被写体 ([fakeMonsterGenerator] の既定) を「切り抜いた絵で作る」と選ぶ
  /// (自動では切り抜かないため。#242)。[settles] が false なら、初回の導線の相手を探す表示が止まらないため時間を指定して進める。
  Future<void> chooseSubjectCutout({
    required WidgetTester tester,
    required bool settles,
  }) async {
    // 高さの低い画面では選ぶボタンが ListView の画面外にあって作られていないため、見える所までスクロールしてから押す
    await tester.scrollUntilVisible(
      find.text('切り抜いた絵で作る'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('切り抜いた絵で作る'));
    if (settles) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  /// 図鑑と手持ちに見本のモンスターを 1 体入れる。写真を選んだ時に手持ちがあるため、初回の導線 (生まれたらそのまま戦う) ではなく
  /// 2 回目以降の導線 (生まれたカードを出す) になる。
  Future<void> seedPartyWithOneMonster({required WidgetTester tester}) async {
    dexStore.replaceAll(monsters: [sampleData.monsters.first]);
    await tester.pumpAndSettle();
  }

  /// 図鑑に見本を入れて、タイトル画面の「つづきから」でホームの画面に入る。
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
      expect(find.byType(HomeShell), findsNothing);
      // タイトルでホームの画面と同じ BGM を流し始める
      expect(audioCalls.playedBackgroundMusicAssetPaths, [
        BackgroundMusic.home.assetPath,
      ]);
      // タイトルを見ている間に裏でログインし、ログインより前に溜めたタイトルの表示をログインの後に送る
      expect(startSessionCallCount, 1);
      expect(sessionStore.uid, 'uid-1');
      expect(titleEvents.map((logged) => logged.event), [
        AnalyticsEvent.titleShown,
      ]);
    });

    testWidgets('Web のように最初の操作を待つ時、タイトルでは BGM を流さず、画面のどこかを押した時に流す', (
      tester,
    ) async {
      audioWaitsForUserInteraction = true;
      await pumpApp(
        tester: tester,
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      expect(audioCalls.playedBackgroundMusicAssetPaths, isEmpty);
      // タッチは指を置いただけではブラウザが操作に数えないため、離すまで流さない
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('snapmon')),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();
      expect(audioCalls.playedBackgroundMusicAssetPaths, isEmpty);
      // ボタンではない場所 (見出し) から指を離しても、最初の操作として BGM が始まる
      await gesture.up();
      await tester.pumpAndSettle();
      expect(audioCalls.playedBackgroundMusicAssetPaths, [
        BackgroundMusic.home.assetPath,
      ]);
    });

    testWidgets('Web のように最初の操作を待つ時、マウスは押した時点で BGM が始まる', (tester) async {
      audioWaitsForUserInteraction = true;
      await pumpApp(
        tester: tester,
        hasStartedSession: false,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('snapmon')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(audioCalls.playedBackgroundMusicAssetPaths, [
        BackgroundMusic.home.assetPath,
      ]);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(audioCalls.playedBackgroundMusicAssetPaths, [
        BackgroundMusic.home.assetPath,
      ]);
    });

    testWidgets(
      'Web のように最初の操作を待つ時、キーボードのキーを押しただけでも BGM が始まる。Esc と修飾キーだけの押下は操作に数えない',
      (tester) async {
        audioWaitsForUserInteraction = true;
        await pumpApp(
          tester: tester,
          hasStartedSession: false,
          startSessionFailureCount: 0,
          isDeveloperMenuEnabled: false,
        );
        expect(audioCalls.playedBackgroundMusicAssetPaths, isEmpty);
        // 数えないキーは 1 つずつ全部送り、どれでも流れないことを確かめる。
        // tester.sendKeyEvent は flutter test の既定の platform (android) のキー表に無いキー (AltGraph 等) で
        // assert に当たるため、HardwareKeyboard に押下・解放のイベントを直接入れる (物理キーは何でもよい)
        for (final key in keysNotCountedAsUserInteraction) {
          HardwareKeyboard.instance.handleKeyEvent(
            KeyDownEvent(
              physicalKey: PhysicalKeyboardKey.keyA,
              logicalKey: key,
              timeStamp: Duration.zero,
            ),
          );
          HardwareKeyboard.instance.handleKeyEvent(
            KeyUpEvent(
              physicalKey: PhysicalKeyboardKey.keyA,
              logicalKey: key,
              timeStamp: Duration.zero,
            ),
          );
          await tester.pumpAndSettle();
          expect(
            audioCalls.playedBackgroundMusicAssetPaths,
            isEmpty,
            reason: '${key.debugName} で BGM が始まった',
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(audioCalls.playedBackgroundMusicAssetPaths, [
          BackgroundMusic.home.assetPath,
        ]);
      },
    );

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
        await chooseSubjectCutout(tester: tester, settles: true);
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
        expect(find.byType(HomeShell), findsOneWidget);
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
      await chooseSubjectCutout(tester: tester, settles: true);
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
      await chooseSubjectCutout(tester: tester, settles: true);
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
      await chooseSubjectCutout(tester: tester, settles: true);
      expect(find.text('あたらしい なかま'), findsOneWidget);
    });

    testWidgets('「つづきから」を押すとホームの画面が図鑑のシーンから出る', (tester) async {
      await pumpApp(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
      );
      await enterHomeFromTitle(tester: tester);
      expect(find.byType(HomeShell), findsOneWidget);
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

      // 戻るとタイトルに戻る (ホームの画面には入らない)。pageBack は英語の tooltip (Back) で探すため型で探す
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
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
      await chooseSubjectCutout(tester: tester, settles: true);
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
      await chooseSubjectCutout(tester: tester, settles: true);
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
      await chooseSubjectCutout(tester: tester, settles: true);
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
      // ログインが済んでもタイトルに留まり、ボタンを押すまでホームの画面に入らない
      expect(find.text('写真から選んではじめる'), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);

      await seedPartyWithOneMonster(tester: tester);
      await tapStartFromAlbum(tester: tester);
      expect(startSessionCallCount, 1);
      await chooseSubjectCutout(tester: tester, settles: true);
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
      'タイトルで写真を選ぶと生成の完了を待たずに相手を探す画面に進み、生まれると手持ちに入れて CPU トレーナーとバトルし、決着で生まれたカードと勝敗が同じ画面に出る',
      (tester) async {
        generationGate = Completer<void>();
        pvpClient = fakePvpClient(
          calls: pvpCalls,
          // 他のユーザーの候補があっても、本人の操作なしに他人の手持ちを相手にしない (issue #130)
          fetchOpponents: () async => [
            for (final index in [1, 2])
              PvpOpponent(
                opponentUid: 'opponent-uid-$index',
                displayName: 'ろうそくや $index',
                iconPath: null,
                monsters: [
                  generatedWaxMonster(monsterId: 'opponent-wax-$index'),
                ],
              ),
          ],
          extraDefinitions: MasterData.fromJson(json: waxDefinitionJson),
          battleRecord: null,
          profile: null,
          reportMonster: () async {},
          blockUser: () async {},
          updateDisplayName: ({required displayName}) async => displayName,
          updateIcon: ({required photo}) async => 'users/uid/icons/upload.png',
        );
        await pumpApp(
          tester: tester,
          hasStartedSession: true,
          startSessionFailureCount: 0,
          isDeveloperMenuEnabled: false,
        );
        await tester.tap(find.byKey(const Key('title-album')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        // 切り抜くかを選ぶまでは、生成を始めず相手も探さない
        expect(generationCalls.requestedRequestIds, isEmpty);
        expect(find.text('相手を探しています'), findsNothing);
        // 相手を探す表示の進捗は止まらないため、pumpAndSettle を使わず時間を指定して進める
        await chooseSubjectCutout(tester: tester, settles: false);
        // 生成はまだ終わっていない
        expect(generationCalls.requestedRequestIds, ['request-1']);
        expect(find.text('相手を探しています'), findsOneWidget);
        expect(find.text('あたらしい なかま'), findsNothing);
        expect(find.byType(BattleScreen), findsNothing);

        generationGate!.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        const bornMonsterId = 'generated-request-1';
        expect(dexStore.party.map((monster) => monster.definition.id), [
          bornMonsterId,
        ]);
        // 相手は CPU トレーナーのどれか (seed で選ぶ)
        expect(find.textContaining(RegExp(r'^CPU .+ があらわれた$')), findsOneWidget);
        expect(pvpCalls.fetchOpponentsCount, 0);
        expect(pvpCalls.fetchedDefinitionIds, isEmpty);

        await tester.pump(const Duration(seconds: 2));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(BattleScreen), findsOneWidget);
        expect(find.byKey(const Key('first-battle-hint')), findsOneWidget);
        // CPU トレーナーは他のユーザーではないため、通報・ブロックのメニューを出さない
        expect(
          find.byKey(const Key('opponent-menu-opponent-uid-1')),
          findsNothing,
        );

        await playFirstBattleUntilFinished(tester: tester);
        final bornMonster = generatedWaxMonster(
          monsterId: bornMonsterId,
        ).definition;
        // 生まれたカードと勝敗が同じ画面に出る
        expect(find.text('あたらしい なかま'), findsOneWidget);
        expect(find.text(bornMonster.encyclopediaText), findsOneWidget);
        // AI 生成の開示は利用規約・プライバシーポリシー・ストアの説明文で行い、画面には出さない
        expect(find.textContaining('AI が'), findsNothing);
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
        expect(battleCalls.loggedEvents.first.parameters?['opponent'], 'cpu');
        expect(
          battleCalls.loggedEvents.last.event,
          AnalyticsEvent.firstExperience,
        );

        // 「もう 1 体撮る」で撮るのシーンに進む。手持ちがあるので、撮るのシーンの初回の案内はもう出ない
        await tester.tap(find.byKey(const Key('first-battle-capture-again')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(find.byType(BattleScreen), findsNothing);
        expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
        expect(find.text('図鑑 1'), findsOneWidget);
        expect(find.byKey(const Key('capture-first-hint')), findsNothing);
      },
    );

    testWidgets('撮るのシーンは手持ちが空の時に案内を出し、アルバムから選ぶと CPU トレーナーと戦い、「図鑑を見る」で図鑑に入る', (
      tester,
    ) async {
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
      await chooseSubjectCutout(tester: tester, settles: false);
      // 相手は CPU トレーナーのどれか (seed で選ぶ)
      expect(find.textContaining(RegExp(r'^CPU .+ があらわれた$')), findsOneWidget);
      expect(pvpCalls.fetchOpponentsCount, 0);

      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BattleScreen), findsOneWidget);
      await playFirstBattleUntilFinished(tester: tester);
      expect(battleCalls.loggedEvents.first.parameters?['opponent'], 'cpu');

      await tester.tap(find.text('図鑑を見る'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1 体 · 手持ち 1 体'), findsOneWidget);
    });
  });

  group('ホームの画面のシーンと画面の遷移', () {
    testWidgets('下タブは無く、撮るのボタンで図鑑・対戦を開き、「もどる」で撮るに戻る', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
      // 下タブ (図鑑・撮る・対戦が並ぶ帯) は無い (#264)
      for (final removedTabKey in const [
        'tab-dex',
        'tab-capture',
        'tab-opponent',
      ]) {
        expect(find.byKey(Key(removedTabKey)), findsNothing);
      }
      // 撮るは起点のシーンのため「もどる」を出さない
      expect(find.byKey(const Key('scene-back-to-capture')), findsNothing);

      await tester.tap(find.byKey(const Key('capture-open-dex')));
      await tester.pumpAndSettle();
      expect(find.text('0 体 · 手持ち 0 体'), findsOneWidget);
      expect(find.text('まだモンスターがいません\n撮る画面から身の回りの物を撮ってみよう'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scene-back-to-capture')));
      await tester.pumpAndSettle();
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);

      await tester.tap(find.byKey(const Key('capture-open-opponent')));
      await tester.pumpAndSettle();
      expect(find.text('ランダムな相手と戦う'), findsOneWidget);

      await tester.tap(find.byKey(const Key('scene-back-to-capture')));
      await tester.pumpAndSettle();
      expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
    });

    testWidgets('図鑑・対戦で端末の戻る操作をすると撮るに戻り、撮るでは戻る操作を止めない', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );

      for (final openKey in const [
        Key('capture-open-dex'),
        Key('capture-open-opponent'),
      ]) {
        await tester.tap(find.byKey(openKey));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('scene-back-to-capture')), findsOneWidget);

        // Android の戻るボタン・戻るジェスチャーと同じ経路 (Navigator の maybePop)
        expect(await tester.binding.handlePopRoute(), isTrue);
        await tester.pumpAndSettle();
        expect(find.text('身の回りの物を撮る\nモンスターが生まれる'), findsOneWidget);
      }

      // 撮るではホームの画面の PopScope が戻る操作を止めない (ホームの画面は最初の route のため、閉じるのはアプリ)
      final popScope = tester.widget<PopScope<Object?>>(
        find
            .descendant(
              of: find.byType(HomeShell),
              matching: find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .first,
      );
      expect(popScope.canPop, isTrue);
    });

    testWidgets('撮る → 図鑑 → 撮る を素早く押しても、撮る画面は同時に 1 つしかない', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );

      await tester.tap(find.byKey(const Key('capture-open-dex')));
      // フェードの途中 (300ms より前) で撮るに戻す
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.byKey(const Key('scene-back-to-capture')));
      for (var frame = 0; frame < 20; frame++) {
        await tester.pump(const Duration(milliseconds: 20));
        expect(
          find.byType(CaptureScreen).evaluate().length,
          lessThanOrEqualTo(1),
        );
        expect(find.byType(DexScreen).evaluate().length, lessThanOrEqualTo(1));
      }
      await tester.pumpAndSettle();
      expect(find.byType(CaptureScreen), findsOneWidget);
      expect(find.byType(DexScreen), findsNothing);
    });

    testWidgets('図鑑から開く画面は横スライドの MaterialPageRoute ではなくフェードの route で開く', (
      tester,
    ) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      dexStore.replaceAll(monsters: sampleData.monsters);
      await tester.tap(find.byKey(const Key('capture-open-dex')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(sampleData.monsters.last.definition.name));
      await tester.pumpAndSettle();

      final route = ModalRoute.of(tester.element(find.byType(ResultScreen)));
      expect(route, isA<PageRouteBuilder<Object?>>());
      expect(route, isNot(isA<MaterialPageRoute<Object?>>()));
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
      await chooseSubjectCutout(tester: tester, settles: true);
      final bornMonster = generatedWaxMonster(
        monsterId: 'generated-request-1',
      ).definition;
      expect(find.text('あたらしい なかま'), findsOneWidget);
      expect(find.text(bornMonster.name), findsOneWidget);
      // AI 生成の開示は利用規約・プライバシーポリシー・ストアの説明文で行い、画面には出さない
      expect(find.textContaining('AI が'), findsNothing);
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
      await chooseSubjectCutout(tester: tester, settles: true);
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
      await chooseSubjectCutout(tester: tester, settles: true);
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
      await tester.tap(find.byKey(const Key('capture-open-dex')));
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
      await tester.tap(find.byKey(const Key('capture-open-dex')));
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
      await tester.tap(find.byKey(const Key('capture-open-dex')));
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
      await tester.tap(find.byKey(const Key('capture-open-dex')));
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
      await tester.tap(find.byKey(const Key('capture-open-dex')));
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
      await chooseSubjectCutout(tester: tester, settles: true);
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
      'タイトルの「カメラで撮ってはじめる」から来た時は撮るのシーンですぐカメラを求め、開けないままシーンを切り替えて戻ると求め直さない',
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

        await tester.tap(find.byKey(const Key('capture-open-dex')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('scene-back-to-capture')));
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
      await tester.tap(find.byKey(const Key('capture-open-dex')));
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
      await tester.tap(find.byKey(const Key('capture-open-opponent')));
      await tester.pumpAndSettle();
      final challengeButton = find.byKey(const Key('random-battle'));
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
      await tester.tap(find.byKey(const Key('capture-open-opponent')));
      await tester.pumpAndSettle();
      final challengeButton = find.byKey(const Key('random-battle'));
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
      await tester.tap(find.byKey(const Key('capture-open-dex')));
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
      await tester.tap(find.byKey(const Key('capture-open-opponent')));
      await tester.pumpAndSettle();
      final challengeButton = find.byKey(const Key('random-battle'));
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
      await tester.tap(find.byKey(const Key('capture-open-dex')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(waxMonster.definition.name).first);
      await tester.pumpAndSettle();
      expect(find.text('ろうアタック'), findsOneWidget);
      await tester.tap(find.byTooltip('戻る'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('scene-back-to-capture')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('capture-open-opponent')));
      await tester.pumpAndSettle();
      final challengeButton = find.byKey(const Key('random-battle'));
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
      await tester.tap(find.byKey(const Key('capture-open-dex')));
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
      await tester.tap(find.byKey(const Key('capture-open-opponent')));
      await tester.pumpAndSettle();
      expect(find.text('手持ちを入れると挑めます'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('random-battle')))
            .onPressed,
        isNull,
      );
      // 他のユーザーの手持ちは相手にしない (issue #130)
      expect(pvpCalls.fetchOpponentsCount, 0);
    });

    testWidgets('挑むとバトル画面が開き、にげるのボタンは無く、交代で手持ちの控えを場に出せる', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      dexStore.replaceAll(monsters: sampleData.monsters);
      await tester.tap(find.byKey(const Key('capture-open-opponent')));
      await tester.pumpAndSettle();
      final challengeButton = find.byKey(const Key('random-battle'));

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
      // 相手は乱数で決まるため、開いたバトル画面に渡った相手の先頭から名前を取る
      final opponentMonster = tester
          .widget<BattleScreen>(find.byType(BattleScreen))
          .opponentParty
          .first
          .definition;
      expect(find.text('${opponentMonster.name} が 勝負をしかけてきた'), findsOneWidget);
      expect(find.text('ターン 1'), findsOneWidget);
      // 決着の前にバトルを抜けるボタンは置かない (issue #263)
      expect(find.text('にげる'), findsNothing);

      await tester.tap(find.text('モンスターを交代'));
      await pumpTransition();
      // 候補は場にいない 2 体目と 3 体目だけ
      expect(find.text('場に出す モンスターを えらぶ'), findsOneWidget);
      expect(find.byKey(const Key('battle-switch-candidate-0')), findsNothing);
      expect(
        find.byKey(const Key('battle-switch-candidate-2')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('battle-switch-candidate-1')));
      // 交代のログは次のログまで 1.5 秒だけ出るため、その間に確かめる
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final party = dexStore.party;
      expect(
        find.text(
          '${party[0].definition.name} を ひっこめて ${party[1].definition.name} を だした',
        ),
        findsOneWidget,
      );
      // バトルを閉じず、図鑑には戻らない
      expect(find.byType(BattleScreen), findsOneWidget);
      // 相手の技の演出を最後まで進め、保留中のタイマーを残さない
      for (var second = 0; second < 10; second++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(find.text('${party[1].definition.name} の 技をえらぶ'), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('capture-open-opponent')));
    await tester.pumpAndSettle();
    final challengeButton = find.byKey(const Key('random-battle'));
    await tester.ensureVisible(challengeButton);
    await tester.pumpAndSettle();
    await tester.tap(challengeButton);
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // CPU の手持ちは自分の手持ちと同じ数で、レベルは自分の手持ちの平均 (lib/features/opponent/cpu_party.dart)
    final opponentParty = tester
        .widget<BattleScreen>(find.byType(BattleScreen))
        .opponentParty;
    expect(opponentParty, hasLength(partyBefore.length));
    for (final opponentMonster in opponentParty) {
      expect(
        opponentMonster.level,
        partyBefore.fold<int>(
              0,
              (sum, playerMonster) => sum + playerMonster.level,
            ) ~/
            partyBefore.length,
      );
    }
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
    expect(find.text('ランダムな相手と戦う'), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('capture-open-opponent')));
    await tester.pumpAndSettle();
    final challengeButton = find.byKey(const Key('random-battle'));
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
    await pumpHome(
      tester: tester,
      hasStartedSession: true,
      startSessionFailureCount: 0,
      isDeveloperMenuEnabled: false,
      startsCameraOnCaptureOpen: false,
    );
    dexStore.replaceAll(monsters: sampleData.monsters);
    await tester.tap(find.byKey(const Key('capture-open-opponent')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('random-battle')));
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('モンスターを交代'), findsOneWidget);
    // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
    expect(tester.takeException(), isNull);
  });

  testWidgets('iOS の最大の文字サイズでも交代のボタンの文字が切れない', (tester) async {
    // iOS のアクセシビリティの最大の文字サイズ (約 3.1 倍) より少し大きくした
    // 文字が大きいと対戦相手の画面の挑むボタンが画面外に出るため、バトル画面を直接開く
    tester.platformDispatcher.textScaleFactorTestValue = 3.2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      GameAudioScope(
        gameAudio: fakeGameAudio(
          calls: RecordedAudioCalls(),
          isBackgroundMusicEnabled: true,
          isSoundEffectsEnabled: true,
          waitsForUserInteractionBeforeBackgroundMusic: false,
        ),
        child: MaterialApp(
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
            playerProfile: (displayName: 'トレーナー 0042', iconPath: null),
            opponentDisplayName: 'CPU リク',
          ),
        ),
      ),
    );
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump(const Duration(seconds: 1));
    // 高さが足りない時、文字は例外を出さずに切れる (描画の大きさが中身の高さより小さくなる) ため、
    // 文字の描画の大きさが中身の高さ以上あることで確かめる
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('モンスターを交代'),
    );
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
        paragraph.getMinIntrinsicHeight(paragraph.size.width),
      ),
    );
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
          GameAudioScope(
            gameAudio: fakeGameAudio(
              calls: RecordedAudioCalls(),
              isBackgroundMusicEnabled: true,
              isSoundEffectsEnabled: true,
              waitsForUserInteractionBeforeBackgroundMusic: false,
            ),
            child: MaterialApp(
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

    testWidgets('設定のプロフィールはサーバーが返した名前を出し、プロフィール画面で変えると保存した名前に変わる', (
      tester,
    ) async {
      pvpClient = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: (wins: 0, losses: 0),
        profile: (displayName: 'トレーナー 0042', iconPath: null),
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async {
          if (displayName.contains('ピカチュウ')) {
            throw Exception('この表示名は使えません');
          }
          return displayName.trim();
        },
        updateIcon: ({required photo}) async => 'users/uid/icons/upload.png',
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
      // 設定の表示名の項目はプロフィール画面への入口に置き換えた
      expect(find.byKey(const Key('display-name')), findsNothing);

      await tester.tap(find.byKey(const Key('profile')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
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

    testWidgets('プロフィール画面でアルバムから写真を選ぶと、送る形にしてアイコンを変え、断られた時は理由をそのまま出す', (
      tester,
    ) async {
      var iconRejected = true;
      pvpClient = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: (wins: 0, losses: 0),
        profile: (displayName: 'トレーナー 0042', iconPath: null),
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
        updateIcon: ({required photo}) async {
          if (iconRejected) {
            throw Exception('人の顔が写っている写真はアイコンにできません');
          }
          return 'users/uid/icons/upload.png';
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
      await tester.tap(find.byKey(const Key('profile')));
      await tester.pumpAndSettle();
      // 未登録の間は既定の印 (表示名の最初の 1 文字) を出す
      expect(
        find.descendant(
          of: find.byKey(const Key('profile-icon')),
          matching: find.text('ト'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('profile-change-icon')));
      await tester.pumpAndSettle();
      expect(find.text('Exception: 人の顔が写っている写真はアイコンにできません'), findsOneWidget);
      expect(
        tester
            .widget<TrainerIcon>(find.byKey(const Key('profile-icon')))
            .iconPath,
        isNull,
      );

      iconRejected = false;
      await tester.tap(find.byKey(const Key('profile-change-icon')));
      await tester.pumpAndSettle();
      expect(pvpCalls.updatedIconPhotos, [testPhotoBytes, testPhotoBytes]);
      expect(find.text('アイコンを変えました'), findsOneWidget);
      expect(
        tester
            .widget<TrainerIcon>(find.byKey(const Key('profile-icon')))
            .iconPath,
        'users/uid/icons/upload.png',
      );
    });

    testWidgets('アイコンを保存し終えるまではプロフィール画面から戻れない', (tester) async {
      final iconSaved = Completer<String>();
      pvpClient = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: (wins: 0, losses: 0),
        profile: (displayName: 'トレーナー 0042', iconPath: null),
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
        updateIcon: ({required photo}) => iconSaved.future,
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
      await tester.tap(find.byKey(const Key('profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-change-icon')));
      await tester.pump();

      await tester.tap(find.byType(BackButton));
      // 保存中の進捗の表示が回り続けるため、pumpAndSettle を使わず画面の遷移の時間だけ進める
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ProfileScreen), findsOneWidget);

      iconSaved.complete('users/uid/icons/upload.png');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsNothing);
    });

    testWidgets('保存の後にプロフィールの読み直しに失敗しても、設定の項目と次に開くプロフィール画面は保存した値を出す', (
      tester,
    ) async {
      var fetchProfileFails = false;
      final base = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: (wins: 0, losses: 0),
        profile: (displayName: 'トレーナー 0042', iconPath: null),
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
        updateIcon: ({required photo}) async => 'users/uid/icons/upload.png',
      );
      pvpClient = PvpClient(
        fetchOpponents: base.fetchOpponents,
        fetchDefinitions: base.fetchDefinitions,
        reportMonster: base.reportMonster,
        blockUser: base.blockUser,
        fetchBattleRecord: base.fetchBattleRecord,
        fetchProfile: () async {
          if (fetchProfileFails) {
            throw Exception('通信に失敗しました');
          }
          return base.fetchProfile();
        },
        updateDisplayName: base.updateDisplayName,
        updateIcon: base.updateIcon,
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
      await tester.tap(find.byKey(const Key('profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('profile-change-icon')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('display-name')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('display-name-field')),
        'ばんざい',
      );
      await tester.tap(find.byKey(const Key('display-name-save')));
      await tester.pumpAndSettle();

      fetchProfileFails = true;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.text('ばんざい'), findsOneWidget);
      expect(find.text('トレーナー 0042'), findsNothing);
      expect(
        tester
            .widget<TrainerIcon>(
              find.descendant(
                of: find.byKey(const Key('profile')),
                matching: find.byType(TrainerIcon),
              ),
            )
            .iconPath,
        'users/uid/icons/upload.png',
      );

      await tester.tap(find.byKey(const Key('profile')));
      await tester.pumpAndSettle();
      expect(find.text('ばんざい'), findsOneWidget);
      expect(
        tester
            .widget<TrainerIcon>(find.byKey(const Key('profile-icon')))
            .iconPath,
        'users/uid/icons/upload.png',
      );
    });

    testWidgets('保存の前に始めた読み直しが保存の後に返っても、保存した値を保存前の値に戻さない', (tester) async {
      Completer<PlayerProfile>? heldFetchProfile;
      var fetchProfileFails = false;
      final base = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: (wins: 0, losses: 0),
        profile: (displayName: 'トレーナー 0042', iconPath: null),
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
        updateIcon: ({required photo}) async => 'users/uid/icons/upload.png',
      );
      pvpClient = PvpClient(
        fetchOpponents: base.fetchOpponents,
        fetchDefinitions: base.fetchDefinitions,
        reportMonster: base.reportMonster,
        blockUser: base.blockUser,
        fetchBattleRecord: base.fetchBattleRecord,
        fetchProfile: () async {
          if (fetchProfileFails) {
            throw Exception('通信に失敗しました');
          }
          return heldFetchProfile?.future ?? base.fetchProfile();
        },
        updateDisplayName: base.updateDisplayName,
        updateIcon: base.updateIcon,
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

      final staleFetchProfile = Completer<PlayerProfile>();
      heldFetchProfile = staleFetchProfile;
      await tester.tap(find.byKey(const Key('profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      heldFetchProfile = null;

      await tester.tap(find.byKey(const Key('profile')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('display-name')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('display-name-field')),
        'ばんざい',
      );
      await tester.tap(find.byKey(const Key('display-name-save')));
      await tester.pumpAndSettle();
      staleFetchProfile.complete((displayName: 'トレーナー 0042', iconPath: null));
      await tester.pumpAndSettle();

      fetchProfileFails = true;
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('ばんざい'), findsOneWidget);
      expect(find.text('トレーナー 0042'), findsNothing);
    });

    testWidgets('アカウントの切り替えの間はプロフィール画面を開けず、切り替えの後は開ける', (tester) async {
      final linkedAccountSignIn = Completer<String>();
      linkAccount = () async =>
          () => linkedAccountSignIn.future;
      pvpClient = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: (wins: 0, losses: 0),
        profile: (displayName: 'トレーナー 0042', iconPath: null),
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
        updateIcon: ({required photo}) async => 'users/uid/icons/upload.png',
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
      await tester.tap(find.text('データを引き継ぐ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('切り替える'));
      // 1 秒: ダイアログと画面の遷移 (Material の既定で 300ms 前後) が終わる長さ。切り替えの待ちの表示が動いていても pumpAndSettle のように止まらないため固定の時間にする
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('profile')));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ProfileScreen), findsNothing);

      linkedAccountSignIn.complete('uid-linked');
      await tester.pumpAndSettle();
      expect(sessionStore.uid, 'uid-linked');
      await tester.tap(find.byKey(const Key('profile')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('ログインが無い時はプロフィールの項目を出さない', (tester) async {
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await tester.tap(find.byTooltip('設定'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('profile')), findsNothing);
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
        expect(find.byType(HomeShell), findsNothing);
        expect(startSessionCallCount, 1);
        expect(sessionStore.uid, 'uid-1');
        await tapStartFromAlbum(tester: tester);
        await chooseSubjectCutout(tester: tester, settles: true);
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

    testWidgets('連携済みのアカウントに切り替えると、プロフィールを切り替え先の名前に読み直す', (tester) async {
      linkAccount = () async =>
          () async => 'uid-linked';
      final signedInPvpClient = fakePvpClient(
        calls: pvpCalls,
        fetchOpponents: () async => [],
        extraDefinitions: null,
        battleRecord: (wins: 0, losses: 0),
        profile: null,
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
        updateIcon: ({required photo}) async => 'users/uid/icons/upload.png',
      );
      pvpClient = PvpClient(
        fetchOpponents: signedInPvpClient.fetchOpponents,
        fetchDefinitions: signedInPvpClient.fetchDefinitions,
        reportMonster: signedInPvpClient.reportMonster,
        blockUser: signedInPvpClient.blockUser,
        fetchBattleRecord: signedInPvpClient.fetchBattleRecord,
        fetchProfile: () async => (
          displayName: switch (sessionStore.uid) {
            'uid-linked' => '切り替え先の名前',
            _ => '匿名の名前',
          },
          iconPath: null,
        ),
        updateDisplayName: signedInPvpClient.updateDisplayName,
        updateIcon: signedInPvpClient.updateIcon,
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
        profile: null,
        reportMonster: () async {},
        blockUser: () async {},
        updateDisplayName: ({required displayName}) async => displayName,
        updateIcon: ({required photo}) async => 'users/uid/icons/upload.png',
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
        fetchProfile: signedInPvpClient.fetchProfile,
        updateDisplayName: signedInPvpClient.updateDisplayName,
        updateIcon: signedInPvpClient.updateIcon,
      );
      await pumpHome(
        tester: tester,
        hasStartedSession: true,
        startSessionFailureCount: 0,
        isDeveloperMenuEnabled: false,
        startsCameraOnCaptureOpen: false,
      );
      await tester.tap(find.byKey(const Key('capture-open-opponent')));
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

    testWidgets('ホームの画面は BGM を流し、設定の「BGM」「効果音」を切ると止めて保存し、戻すと流し直す', (
      tester,
    ) async {
      await openSettings(tester: tester);
      expect(audioCalls.playedBackgroundMusicAssetPaths, [
        BackgroundMusic.home.assetPath,
      ]);
      expect(find.text('サウンド'), findsOneWidget);

      await tester.tap(find.byKey(const Key('settings-background-music')));
      await tester.pumpAndSettle();
      expect(audioCalls.stopBackgroundMusicCount, 1);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('settings-background-music')),
            )
            .value,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('settings-sound-effects')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const Key('settings-sound-effects')),
            )
            .value,
        isFalse,
      );

      await tester.tap(find.byKey(const Key('settings-background-music')));
      await tester.pumpAndSettle();
      expect(audioCalls.playedBackgroundMusicAssetPaths, [
        BackgroundMusic.home.assetPath,
        BackgroundMusic.home.assetPath,
      ]);
      expect(audioCalls.savedSettings, [
        (key: AudioSettingKey.backgroundMusic, value: false),
        (key: AudioSettingKey.soundEffects, value: false),
        (key: AudioSettingKey.backgroundMusic, value: true),
      ]);
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

    testWidgets(
      '開発者メニューの見本の写真から切り抜くかを選んで生成すると、中央の正方形を被写体として選ぶ画面を出し、切り抜いた絵で ios_subject を送る',
      (tester) async {
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
        await tester.scrollUntilVisible(
          find.text('見本の写真から切り抜くかを選んで生成: マグカップ'),
          100,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.text('見本の写真から切り抜くかを選んで生成: マグカップ'));
        await tester.pumpAndSettle();
        expect(find.text('被写体を切り抜きました'), findsOneWidget);
        expect(generationCalls.squareMaskCrops, hasLength(1));
        expect(generationCalls.requestedMaskSources, isEmpty);
        await chooseSubjectCutout(tester: tester, settles: true);
        expect(find.text('あたらしい なかま'), findsOneWidget);
        expect(generationCalls.requestedMaskSources, [
          GenerationMaskSource.iosSubject,
        ]);
      },
    );

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
      await chooseSubjectCutout(tester: tester, settles: true);
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
