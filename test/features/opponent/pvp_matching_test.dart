import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/audio/game_audio.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/opponent_screen.dart';
import 'package:snapmon/features/opponent/pvp_battle.dart';
import 'package:snapmon/features/opponent/pvp_matching_screen.dart';
import 'package:snapmon/features/opponent/report_reason.dart';
import 'package:snapmon/features/settings/settings_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../game_audio_fixture.dart';
import '../../pvp_battle_fixture.dart';
import '../../pvp_client_fixture.dart';
import '../../sample_data_fixture.dart';

// 対戦のシーンの「対戦をする」から始める人との対戦 (issue #386)。待つ画面 (やめる・1 分後の「CPU と対戦をする」)、
// 組み合わされた後のバトルの画面 (相手の行動を待つ・通報・ブロック・時間切れ・勝敗なし)、「もう一回対戦する」を確かめる。
void main() {
  final sampleData = loadSampleDataFixture();

  /// 見本のモンスター [monsterID] を、レベルだけ [level] に替えた 1 体。
  OwnedMonster sampleMonsterWithLevel({
    required String monsterID,
    required int level,
  }) {
    final monster = sampleData.monsterByID(monsterID: monsterID);
    return OwnedMonster(
      definition: monster.definition,
      level: level,
      actionCardMoveIDs: monster.actionCardMoveIDs,
      selectedMoveIDs: null,
      artPath: monster.artPath,
      definitionIDs: monster.definitionIDs,
      decoration: monster.decoration,
      decorationVersion: monster.decorationVersion,
    );
  }

  // 自分は先に待つ側。組み合わせた時点の手持ちの写しは、端末の図鑑の手持ち (見本のレベルの 3 体) と違う Lv.60 の 1 体にして、
  // バトルの画面が写しの方を使うことを確かめる
  final player = pvpTrainerFixture(
    uid: 'player-uid',
    displayName: 'じぶん',
    monsters: [sampleMonsterWithLevel(monsterID: 'sample-mugmon', level: 60)],
  );
  final opponent = pvpTrainerFixture(
    uid: 'opponent-uid',
    displayName: 'あいて',
    monsters: [
      sampleMonsterWithLevel(monsterID: 'sample-ringora', level: 1),
      sampleMonsterWithLevel(monsterID: 'sample-slippan', level: 1),
    ],
  );

  late AppLocalizations l10n;
  late FakePvpBattleServer server;
  late RecordedPvpCalls pvpCalls;
  late RecordedBattleCalls battleCalls;
  late DexStore dexStore;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('ja'));
    server = FakePvpBattleServer(
      host: player,
      guest: opponent,
      randomSeed: 1,
      turnSeconds: 60,
    );
    pvpCalls = RecordedPvpCalls();
    battleCalls = RecordedBattleCalls();
    dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters);
  });

  /// 自分 ([player]) の端末の対戦のシーンを、手持ちを 3 体入れて iPhone の画面の大きさで開く。
  /// 相手をブロックした時は [blockUser] を呼ぶ (Functions が進行中の対戦を終えるのを、テストがサーバーの代わりに起こすため)。
  Future<void> pumpOpponentScreen({
    required WidgetTester tester,
    required Future<void> Function() blockUser,
  }) async {
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
          home: Scaffold(
            body: OpponentScreen(
              sampleData: sampleData,
              dexStore: dexStore,
              onSelectScene: ({required scene}) {},
              onOpenSettings: () async {},
              battleRecorder: fakeBattleRecorder(
                calls: battleCalls,
                startBattleRecord: () async => null,
                recordedLevels: const {'sample-mugmon': 61},
              ),
              pvpClient: fakePvpClient(
                calls: pvpCalls,
                battleClient: server.clientOf(uid: player.uid),
                fetchOpponents: () async => [],
                extraDefinitions: null,
                battleRecord: (wins: 0, losses: 0),
                profile: (displayName: 'じぶん', iconPath: null),
                reportMonster: () async {},
                blockUser: blockUser,
                updateDisplayName: ({required displayName}) async =>
                    displayName,
                updateIcon: ({required photo}) async =>
                    'users/player-uid/icons/upload.png',
              ),
              cardSharer: fakeCardSharer(
                calls: RecordedShareCalls(),
                artImage: null,
                shareResultStatus: ShareResultStatus.success,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 「対戦をする」を押して、人との対戦の待つ画面を開く。待つ画面の表示は動き続けるため、時間を指定して進める。
  Future<void> openMatchingScreen({required WidgetTester tester}) async {
    await tester.tap(find.byKey(const Key('pvp-battle')));
    // 開いた画面は最初のフレームでは画面の外の扱い (Offstage) で作られ、次のフレームで表に出る。時間は進めない
    // (待つ画面のタイマーを、開いた時点から数えて確かめるため)
    await tester.pump();
    await tester.pump();
    expect(find.byType(PvpMatchingScreen), findsOneWidget);
  }

  /// 待つ画面から、相手と組み合わされてバトルの画面が開くまで進める。
  Future<void> matchAndOpenBattle({required WidgetTester tester}) async {
    server.match();
    // 次の相手を探す呼び出し (3 秒ごと) が対戦の ID を受け取る
    await tester.pump(const Duration(seconds: 3));
    // 待つ画面を閉じ、対戦を読んでバトルの画面を開く (Flame のゲームループがあるため pumpAndSettle は使わない)
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(BattleScreen), findsOneWidget);
  }

  /// バトルの画面の 1 番目の技を選ぶ。
  Future<void> tapFirstMove({required WidgetTester tester}) async {
    await tester.ensureVisible(find.byKey(const Key('move-slot-0')));
    await tester.tap(find.byKey(const Key('move-slot-0')));
    await tester.pump();
  }

  /// [finder] が見つかるまで 1 秒ずつ進める。[maximumSeconds] 秒進めても見つからなければテストを落とす。
  Future<void> pumpUntilFound({
    required WidgetTester tester,
    required Finder finder,
    required int maximumSeconds,
  }) async {
    for (
      var seconds = 0;
      seconds < maximumSeconds && finder.evaluate().isEmpty;
      seconds++
    ) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(finder, findsOneWidget);
  }

  /// ログの帯に出ている文言。
  String? battleLogText({required WidgetTester tester}) =>
      tester.widget<Text>(find.byKey(const Key('battle-log'))).data;

  group('待つ画面', () {
    testWidgets(
      '「対戦をする」は待つ画面を開いて、対戦の計算の版を付けて相手を探し、1 分の前は「CPU と対戦をする」を出さず、1 分で出して探し続ける',
      (tester) async {
        await pumpOpponentScreen(tester: tester, blockUser: () async {});
        await openMatchingScreen(tester: tester);

        expect(find.text(l10n.opponentSearching), findsOneWidget);
        expect(find.byKey(const Key('pvp-matching-cancel')), findsOneWidget);
        expect(server.joinCalls, [
          (
            uid: 'player-uid',
            rulesVersion: '1.${sampleData.definitions.version}',
            searchID: 'search-1',
          ),
        ]);
        expect(find.byKey(const Key('pvp-matching-cpu-battle')), findsNothing);

        await tester.pump(const Duration(seconds: 59));
        expect(find.byKey(const Key('pvp-matching-cpu-battle')), findsNothing);

        await tester.pump(const Duration(seconds: 1));
        expect(
          find.descendant(
            of: find.byKey(const Key('pvp-matching-cpu-battle')),
            matching: find.text(l10n.opponentCpuBattle),
          ),
          findsOneWidget,
        );
        // ボタンを出した後も探し続ける
        expect(find.text(l10n.opponentSearching), findsOneWidget);
        final joinCountAtOffer = server.joinCalls.length;
        await tester.pump(const Duration(seconds: 3));
        expect(server.joinCalls, hasLength(joinCountAtOffer + 1));

        // 待つ画面を閉じて探すのをやめる (閉じないとテストの終わりにタイマーが残る)
        await tester.tap(find.byKey(const Key('pvp-matching-cancel')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
      },
    );

    testWidgets('待つ画面の「CPU と対戦をする」は、探すのをやめて CPU トレーナーとの対戦に入る', (tester) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await tester.pump(const Duration(seconds: 60));

      await tester.tap(find.byKey(const Key('pvp-matching-cpu-battle')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(server.leaveCalls, [(uid: 'player-uid', searchID: 'search-1')]);
      expect(find.byType(PvpMatchingScreen), findsNothing);
      final battleScreen = tester.widget<BattleScreen>(
        find.byType(BattleScreen),
      );
      expect(battleScreen.opponentKind, BattleOpponentKind.cpu);
      expect(battleScreen.pvpSession, isNull);
      expect(
        sampleData.cpuTrainerNames,
        contains(battleScreen.opponentDisplayName),
      );
      expect(find.byKey(const Key('opponent-safety-menu')), findsNothing);
      final joinCountAtLeave = server.joinCalls.length;
      await tester.pump(const Duration(seconds: 10));
      expect(server.joinCalls, hasLength(joinCountAtLeave));
    });

    testWidgets('「やめる」は探すのをやめて対戦のシーンに戻り、対戦を始めず、もう一度挑める', (tester) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.byKey(const Key('pvp-matching-cancel')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(server.leaveCalls, [(uid: 'player-uid', searchID: 'search-1')]);
      expect(find.byType(PvpMatchingScreen), findsNothing);
      expect(find.byType(BattleScreen), findsNothing);
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('pvp-battle')))
            .onPressed,
        isNotNull,
      );
      final joinCountAtLeave = server.joinCalls.length;
      await tester.pump(const Duration(seconds: 10));
      expect(server.joinCalls, hasLength(joinCountAtLeave));
    });

    testWidgets('5 分組み合わされなければ探すのをやめ、見つからなかったことと「CPU と対戦をする」を出す', (
      tester,
    ) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);

      await tester.pump(const Duration(minutes: 4, seconds: 59));
      expect(find.text(l10n.opponentSearching), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.text(l10n.pvpMatchingNotFound), findsOneWidget);
      expect(find.text(l10n.opponentSearching), findsNothing);
      expect(find.byKey(const Key('pvp-matching-cpu-battle')), findsOneWidget);
      expect(server.leaveCalls, hasLength(1));
      final joinCountAtLimit = server.joinCalls.length;
      await tester.pump(const Duration(seconds: 10));
      expect(server.joinCalls, hasLength(joinCountAtLimit));

      await tester.tap(find.byKey(const Key('pvp-matching-cancel')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('相手を探せなかった時は、エラーをそのまま出して「CPU と対戦をする」をすぐに出す', (tester) async {
      server.joinError = StateError('手持ちを入れてから相手を探してください');
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await tester.pump();

      expect(find.text('Bad state: 手持ちを入れてから相手を探してください'), findsOneWidget);
      expect(find.byKey(const Key('pvp-matching-cpu-battle')), findsOneWidget);

      await tester.tap(find.byKey(const Key('pvp-matching-cancel')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(PvpMatchingScreen), findsNothing);
    });
  });

  group('組み合わされた後のバトルの画面', () {
    testWidgets(
      '組み合わされると待つ画面を閉じ、組み合わせた時点の 2 人の手持ちの写しで、相手の表示名と通報・ブロックのメニューを出したバトルの画面を開く',
      (tester) async {
        await pumpOpponentScreen(tester: tester, blockUser: () async {});
        await openMatchingScreen(tester: tester);
        await matchAndOpenBattle(tester: tester);

        expect(find.byType(PvpMatchingScreen), findsNothing);
        final battleScreen = tester.widget<BattleScreen>(
          find.byType(BattleScreen),
        );
        expect(battleScreen.opponentKind, BattleOpponentKind.pvp);
        expect(battleScreen.pvpSession!.opponent.uid, 'opponent-uid');
        expect(battleScreen.opponentDisplayName, 'あいて');
        expect(battleScreen.randomSeed, 1);
        expect(
          [
            for (final monster in battleScreen.playerParty)
              (monster.definition.id, monster.level),
          ],
          [('sample-mugmon', 60)],
        );
        expect(
          [
            for (final monster in battleScreen.opponentParty)
              (monster.definition.id, monster.level),
          ],
          [('sample-ringora', 1), ('sample-slippan', 1)],
        );
        expect(find.byKey(const Key('opponent-safety-menu')), findsOneWidget);
        // 組み合わされた後は探さない
        final joinCountAtMatch = server.joinCalls.length;
        await tester.pump(const Duration(seconds: 10));
        expect(server.joinCalls, hasLength(joinCountAtMatch));
        expect(server.leaveCalls, isEmpty);
      },
    );

    testWidgets('相手を探している間に図鑑の定義が新しい版に替わっても、相手に版を伝えた時の定義で対戦する', (tester) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      expect(
        server.joinCalls.single.rulesVersion,
        '1.${sampleData.definitions.version}',
      );
      // 探している間に、新しい master の定義が図鑑に届く
      dexStore.applyServerSnapshot(
        monsters: null,
        partyMonsterIDs: null,
        definitions: MasterData(
          version: sampleData.definitions.version + 1,
          elementTypes: sampleData.definitions.elementTypes,
          typeChart: sampleData.definitions.typeChart,
          moves: sampleData.definitions.moves,
          effects: sampleData.definitions.effects,
          statGrades: sampleData.definitions.statGrades,
          elementSelection: sampleData.definitions.elementSelection,
        ),
      );
      await matchAndOpenBattle(tester: tester);

      expect(
        tester
            .widget<BattleScreen>(find.byType(BattleScreen))
            .definitions
            .version,
        sampleData.definitions.version,
      );
    });

    testWidgets('自分の行動を選ぶと相手の行動を待ち、相手が選ぶとラウンドが進み、決着すると勝者を報告してから人との対戦として記録する', (
      tester,
    ) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await matchAndOpenBattle(tester: tester);

      await tapFirstMove(tester: tester);
      expect(battleLogText(tester: tester), l10n.battleLogWaitingForOpponent);
      // 相手が選ぶまでは進まない
      await tester.pump(const Duration(seconds: 10));
      expect(battleLogText(tester: tester), l10n.battleLogWaitingForOpponent);
      expect(server.submitCalls.single.uid, 'player-uid');
      expect(server.submitCalls.single.round, 0);

      // sample-ringora は sweets_1 を Lv.1 で覚える (assets/samples/sample_monsters.json)
      server.submitAction(
        uid: 'opponent-uid',
        round: 0,
        action: const UseMoveAction(moveID: 'sweets_1'),
      );
      await tester.pump();
      expect(
        battleLogText(tester: tester),
        isNot(l10n.battleLogWaitingForOpponent),
      );
      expect(server.battle!.turns, hasLength(1));
      // 演出が終わって次の行動を選べるようになるまで進める
      await tester.pump(const Duration(seconds: 20));
      expect(find.text(l10n.battleWon), findsNothing);

      // 2 ラウンド目に相手の端末が選べない行動を出すと、その場で自分の勝ちになる
      await tapFirstMove(tester: tester);
      server.submitAction(
        uid: 'opponent-uid',
        round: 1,
        action: const UseMoveAction(moveID: 'no-such-move'),
      );
      await pumpUntilFound(
        tester: tester,
        finder: find.text(l10n.battleWon),
        maximumSeconds: 30,
      );
      await tester.pump();

      expect(server.reportCalls, [
        (uid: 'player-uid', winnerUid: 'player-uid'),
      ]);
      expect(battleCalls.startedPartyMonsterIDs, isEmpty);
      expect(battleCalls.completedBattles.single.battleID, 'pvp-battle');
      expect(battleCalls.completedBattles.single.winner, BattleSideID.player);
      expect(battleCalls.completedBattles.single.participantMonsterIDs, [
        'sample-mugmon',
      ]);
      expect(
        [
          for (final logged in battleCalls.loggedEvents)
            if (logged.event == AnalyticsEvent.battleCompleted)
              (logged.parameters?['result'], logged.parameters?['opponent']),
        ],
        [('win', 'pvp')],
      );
    });

    testWidgets('相手が操作をやめた対戦は、サーバーの期限の後に自分の勝ちで終わり、記録する', (tester) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await matchAndOpenBattle(tester: tester);
      await tapFirstMove(tester: tester);

      // 端末の残り時間が切れても、サーバーの期限の前は終わらない
      await tester.pump(const Duration(seconds: 61));
      expect(server.timeoutClaimUids, contains('player-uid'));
      expect(find.text(l10n.battleWon), findsNothing);
      expect(battleLogText(tester: tester), l10n.battleLogWaitingForOpponent);

      server.isTurnDeadlinePassed = true;
      await pumpUntilFound(
        tester: tester,
        finder: find.text(l10n.battleWon),
        maximumSeconds: 10,
      );
      await tester.pump();

      expect(battleLogText(tester: tester), l10n.battleLogOpponentTimedOut);
      expect(server.battle!.finishReason, PvpFinishReason.timeout);
      expect(server.reportCalls, [
        (uid: 'player-uid', winnerUid: 'player-uid'),
      ]);
      expect(battleCalls.completedBattles.single.battleID, 'pvp-battle');
      expect(battleCalls.completedBattles.single.winner, BattleSideID.player);
    });

    testWidgets('行動を選ぶ残り時間が 15 秒になるとログの帯に出し、自分が選ばないまま相手だけが選んだ対戦は自分の負けで終わる', (
      tester,
    ) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await matchAndOpenBattle(tester: tester);
      server.submitAction(
        uid: 'opponent-uid',
        round: 0,
        action: const UseMoveAction(moveID: 'sweets_1'),
      );

      // バトルの画面を開くまでに 1 秒進めているため、あと 43 秒で残り 16 秒
      await tester.pump(const Duration(seconds: 43));
      expect(
        battleLogText(tester: tester),
        isNot(l10n.battleLogTurnTimeRemaining(16)),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(
        battleLogText(tester: tester),
        l10n.battleLogTurnTimeRemaining(15),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(
        battleLogText(tester: tester),
        l10n.battleLogTurnTimeRemaining(10),
      );

      server.isTurnDeadlinePassed = true;
      await pumpUntilFound(
        tester: tester,
        finder: find.text(l10n.battleLost),
        maximumSeconds: 20,
      );
      await tester.pump();

      expect(battleLogText(tester: tester), l10n.battleLogPlayerTimedOut);
      expect(server.battle!.winnerUid, 'opponent-uid');
      expect(server.reportCalls, [
        (uid: 'player-uid', winnerUid: 'opponent-uid'),
      ]);
      expect(battleCalls.completedBattles.single.winner, BattleSideID.opponent);
    });

    testWidgets('2 人とも選ばないまま期限を過ぎた対戦は、勝敗が付かなかったことを知らせて、記録せずに対戦のシーンに戻る', (
      tester,
    ) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await matchAndOpenBattle(tester: tester);

      server.isTurnDeadlinePassed = true;
      await pumpUntilFound(
        tester: tester,
        finder: find.text(l10n.battleNoContestTitle),
        maximumSeconds: 70,
      );
      expect(find.text(l10n.battleNoContestMessage), findsOneWidget);
      expect(server.battle!.status, PvpBattleStatus.noContest);

      await tester.tap(find.byKey(const Key('battle-no-contest-close')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(BattleScreen), findsNothing);
      expect(find.byKey(const Key('pvp-battle')), findsOneWidget);
      expect(server.reportCalls, isEmpty);
      expect(battleCalls.completedBattles, isEmpty);
    });

    testWidgets('メニューから場に出ている相手のモンスターを通報すると、相手の uid とモンスターと選んだ理由で通報する', (
      tester,
    ) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await matchAndOpenBattle(tester: tester);

      await tester.tap(find.byKey(const Key('opponent-safety-menu')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // 通報できるのは場に出たことがあるモンスターだけ (控えの sample-slippan は見せていない)
      expect(find.byKey(const Key('report-sample-ringora')), findsOneWidget);
      expect(find.byKey(const Key('report-sample-slippan')), findsNothing);
      expect(find.byKey(const Key('block-opponent')), findsOneWidget);

      await tester.tap(find.byKey(const Key('report-sample-ringora')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // 理由を選ぶまでは送れない
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('report-submit')))
            .onPressed,
        isNull,
      );
      expect(pvpCalls.reports, isEmpty);
      await tester.tap(
        find.byKey(const Key('report-reason-inappropriate_picture')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('report-submit')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(pvpCalls.reports, [
        (
          monsterOwnerUid: 'opponent-uid',
          monsterID: 'sample-ringora',
          reason: ReportReason.inappropriatePicture,
        ),
      ]);
      expect(find.text(l10n.opponentReported), findsOneWidget);
      expect(find.byKey(const Key('report-submit')), findsNothing);
      // 通報しても進行中の対戦は続く
      expect(find.byType(BattleScreen), findsOneWidget);
      expect(pvpCalls.blocks, isEmpty);
    });

    testWidgets('メニューから相手をブロックすると、確かめた後に相手の uid でブロックし、勝敗が付かずに終わった対戦を閉じる', (
      tester,
    ) async {
      await pumpOpponentScreen(
        tester: tester,
        // Functions の blockUser は、ブロックした相手との進行中の対戦を勝敗を付けずに終える
        blockUser: () async => server.finishByBlock(),
      );
      await openMatchingScreen(tester: tester);
      await matchAndOpenBattle(tester: tester);

      await tester.tap(find.byKey(const Key('opponent-safety-menu')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('block-opponent')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // 確かめるダイアログで決めるまではブロックしない
      expect(find.text(l10n.blockDialogMessage('あいて')), findsOneWidget);
      expect(pvpCalls.blocks, isEmpty);

      await tester.tap(find.byKey(const Key('block-confirm')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // ブロックの操作をした対戦の ID を付けて呼ぶ (Functions がその対戦を終えるため)
      expect(pvpCalls.blocks, [
        (blockedUid: 'opponent-uid', battleID: FakePvpBattleServer.battleID),
      ]);
      expect(find.text(l10n.battleNoContestTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('battle-no-contest-close')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(BattleScreen), findsNothing);
      expect(battleCalls.completedBattles, isEmpty);
    });

    testWidgets('ブロックを確かめるダイアログで「やめる」を選ぶと、ブロックせずに対戦を続ける', (tester) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await matchAndOpenBattle(tester: tester);

      await tester.tap(find.byKey(const Key('opponent-safety-menu')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('block-opponent')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(l10n.commonCancel));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(pvpCalls.blocks, isEmpty);
      expect(find.byType(BattleScreen), findsOneWidget);
      expect(server.battle!.status, PvpBattleStatus.active);
    });

    testWidgets('メニューの「お問い合わせ」は連絡先を開き、開けなかった時はそのことを出す', (tester) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await matchAndOpenBattle(tester: tester);

      await tester.tap(find.byKey(const Key('opponent-safety-menu')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('contact-support')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(pvpCalls.openContactCount, 1);
      expect(
        find.text(l10n.commonCouldNotOpenURL(contactUri.toString())),
        findsNothing,
      );

      pvpCalls.opensContact = false;
      await tester.tap(find.byKey(const Key('opponent-safety-menu')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byKey(const Key('contact-support')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(pvpCalls.openContactCount, 2);
      expect(
        find.text(l10n.commonCouldNotOpenURL(contactUri.toString())),
        findsOneWidget,
      );
      // お問い合わせを開いても対戦は続く
      expect(find.byType(BattleScreen), findsOneWidget);
    });

    testWidgets('人との対戦の後の「もう一回対戦する」は、待つ画面を開いて相手を探し直す', (tester) async {
      await pumpOpponentScreen(tester: tester, blockUser: () async {});
      await openMatchingScreen(tester: tester);
      await matchAndOpenBattle(tester: tester);
      await tapFirstMove(tester: tester);
      server.submitAction(
        uid: 'opponent-uid',
        round: 0,
        action: const UseMoveAction(moveID: 'no-such-move'),
      );
      await pumpUntilFound(
        tester: tester,
        finder: find.text(l10n.battleWon),
        maximumSeconds: 30,
      );
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('battle-rematch')));
      await tester.tap(find.byKey(const Key('battle-rematch')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();

      expect(find.byType(BattleScreen), findsNothing);
      expect(find.byType(PvpMatchingScreen), findsOneWidget);
      // 新しい探す操作の ID で探す (前の対戦を新しい探す操作の結果として受け取らないため)
      expect(server.joinCalls.last.searchID, 'search-2');
    });
  });
}
