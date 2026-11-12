import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/audio/game_audio.dart';
import 'package:snapmon/domain/battle/status_condition.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../game_audio_fixture.dart';
import '../../sample_data_fixture.dart';

/// 勝敗の画面の「もう一回対戦する」と、手持ちが上限に満たないまま負けた時の案内 (https://github.com/bannzai/castle/issues/2861 ) のテスト。
void main() {
  final sampleData = loadSampleDataFixture();

  /// 見本のモンスター [monsterID] を、レベルだけ [level] に替えた 1 体。勝ち負けを決めるためにレベルの差を付ける。
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

  /// レベル 1 の弱い手持ちの候補。
  final weakMonsterIDs = [
    'sample-ringora',
    'sample-slippan',
    'sample-petbottler',
  ];

  /// レベル 60 の強い手持ちの候補。60: レベル 1 の相手に技 1 回で倒され続けない差として十分な値
  final strongMonsterIDs = ['sample-mugmon', 'sample-keybon', 'sample-noton'];

  /// [monsterIDs] の見本のモンスターを、どれもレベル [level] にした手持ち。
  List<OwnedMonster> party({
    required List<String> monsterIDs,
    required int level,
  }) => [
    for (final monsterID in monsterIDs)
      sampleMonsterWithLevel(monsterID: monsterID, level: level),
  ];

  /// [playerParty] と [opponentParty] のバトルの画面を home の上に開き、閉じた時の [BattleScreenAction] を残すリストを返す。
  /// [firstBattleBornMonster] は [BattleScreen.firstBattleBornMonster]。
  Future<List<BattleScreenAction?>> pumpBattle({
    required WidgetTester tester,
    required List<OwnedMonster> playerParty,
    required List<OwnedMonster> opponentParty,
    required OwnedMonster? firstBattleBornMonster,
    // 既定は CPU: 今のアプリが開く対戦は CPU トレーナーとだけで、他のユーザーとの対戦を確かめるテストだけが替える
    BattleOpponentKind opponentKind = BattleOpponentKind.cpu,
    // 既定は記録しない対戦 (null): 決着の後の記録がすぐ終わり、記録の途中を確かめるテストだけが替える
    Future<String?> Function()? startBattleRecord,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigatorKey = GlobalKey<NavigatorState>();
    final poppedActions = <BattleScreenAction?>[];
    await tester.pumpWidget(
      GameAudioScope(
        gameAudio: fakeGameAudio(
          calls: RecordedAudioCalls(),
          isBackgroundMusicEnabled: false,
          isSoundEffectsEnabled: false,
          waitsForUserInteractionBeforeBackgroundMusic: false,
        ),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: snapmonThemeData(),
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Text('バトルを開いた画面')),
        ),
      ),
    );
    navigatorKey.currentState!
        .push(
          MaterialPageRoute<BattleScreenAction>(
            builder: (context) => BattleScreen(
              playerParty: playerParty,
              opponentParty: opponentParty,
              opponentKind: opponentKind,
              definitions: sampleData.definitions,
              randomSeed: 1,
              battleRecorder: fakeBattleRecorder(
                calls: RecordedBattleCalls(),
                startBattleRecord: startBattleRecord ?? () async => null,
                recordedLevels: const {},
              ),
              onPlayerLevelsChanged: ({required levelsByMonsterID}) {},
              cardSharer: fakeCardSharer(
                calls: RecordedShareCalls(),
                artImage: null,
                shareResultStatus: ShareResultStatus.success,
              ),
              firstBattleBornMonster: firstBattleBornMonster,
              firstBattleMonsterIsNewlyBorn: true,
              playerProfile: null,
              opponentDisplayName: 'CPU リク',
            ),
          ),
        )
        .then(poppedActions.add);
    // Flame のゲームループがあるため pumpAndSettle は使わない
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    return poppedActions;
  }

  /// 1 番目の技 (使える攻撃技が無ければわるあがき) を選んで、勝敗の画面の [finishedButton] (既定は「もう一回対戦する」) が出るまで進める。
  Future<void> playUntilFinished({
    required WidgetTester tester,
    // null の時は「もう一回対戦する」: CPU トレーナーとの対戦の勝敗の画面には必ず出るため
    Finder? finishedButton,
  }) async {
    final resolvedFinishedButton =
        finishedButton ?? find.byKey(const Key('battle-rematch'));
    // 300 ターン: 3 体ずつの手持ちでも決着する数より十分多く、決着しない不具合でテストが止まらない上限
    for (
      var turn = 0;
      turn < 300 && resolvedFinishedButton.evaluate().isEmpty;
      turn++
    ) {
      final move = find.text('わるあがき').evaluate().isEmpty
          ? find.byKey(const Key('move-slot-0'))
          : find.text('わるあがき');
      await tester.ensureVisible(move);
      await tester.tap(move);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
    }
    expect(resolvedFinishedButton, findsOneWidget);
  }

  /// [finder] を画面に入れてから押し、閉じる演出を進める。
  Future<void> tapAndClose({
    required WidgetTester tester,
    required Finder finder,
  }) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  testWidgets('手持ちが上限に満たないまま負けると、勝敗の画面に案内が出て、遊び方をスクロールできるポップアップで開ける', (
    tester,
  ) async {
    await pumpBattle(
      tester: tester,
      playerParty: party(monsterIDs: weakMonsterIDs.take(1).toList(), level: 1),
      opponentParty: party(
        monsterIDs: strongMonsterIDs.take(1).toList(),
        level: 60,
      ),
      firstBattleBornMonster: null,
    );
    await playUntilFinished(tester: tester);
    expect(find.text('まけた'), findsOneWidget);
    expect(find.byKey(const Key('battle-lost-party-hint')), findsOneWidget);
    expect(find.text('手持ちを増やすと勝ちやすくなる'), findsOneWidget);

    final openHelp = find.byKey(const Key('battle-open-help'));
    await tester.ensureVisible(openHelp);
    await tester.tap(openHelp);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('help-sheet')), findsOneWidget);
    expect(find.text('属性の相性 (弱点)'), findsOneWidget);
    // 状態異常の一覧の末尾までスクロールでたどり着ける
    final lastStatus = find.byKey(
      Key('help-status-${StatusConditionKind.values.last.name}'),
    );
    await tester.scrollUntilVisible(
      lastStatus,
      200,
      scrollable: find.descendant(
        of: find.byKey(const Key('help-sheet')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(lastStatus, findsOneWidget);

    // 閉じると勝敗の画面に戻る
    await tester.tap(find.byKey(const Key('help-sheet-close')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('help-sheet')), findsNothing);
    expect(find.byKey(const Key('battle-rematch')), findsOneWidget);
  });

  testWidgets('勝った時は手持ちが上限に満たなくても案内を出さない', (tester) async {
    await pumpBattle(
      tester: tester,
      playerParty: party(
        monsterIDs: strongMonsterIDs.take(1).toList(),
        level: 60,
      ),
      opponentParty: party(
        monsterIDs: weakMonsterIDs.take(1).toList(),
        level: 1,
      ),
      firstBattleBornMonster: null,
    );
    await playUntilFinished(tester: tester);
    expect(find.text('かった'), findsOneWidget);
    expect(find.byKey(const Key('battle-lost-party-hint')), findsNothing);
  });

  testWidgets('手持ちが上限まで埋まっている時は負けても案内を出さない', (tester) async {
    await pumpBattle(
      tester: tester,
      playerParty: party(monsterIDs: weakMonsterIDs, level: 1),
      opponentParty: party(monsterIDs: strongMonsterIDs, level: 60),
      firstBattleBornMonster: null,
    );
    await playUntilFinished(tester: tester);
    expect(find.text('まけた'), findsOneWidget);
    expect(find.byKey(const Key('battle-lost-party-hint')), findsNothing);
  });

  testWidgets('初回の導線以外の勝敗の画面は「もどる」と「もう一回対戦する」を出し、押した方の値で閉じる', (tester) async {
    for (final (key, expectedAction) in [
      (const Key('battle-rematch'), BattleScreenAction.rematch),
      (null, null),
    ]) {
      final poppedActions = await pumpBattle(
        tester: tester,
        playerParty: party(
          monsterIDs: strongMonsterIDs.take(1).toList(),
          level: 60,
        ),
        opponentParty: party(
          monsterIDs: weakMonsterIDs.take(1).toList(),
          level: 1,
        ),
        firstBattleBornMonster: null,
      );
      await playUntilFinished(tester: tester);
      expect(find.text('もどる'), findsOneWidget);
      expect(find.text('もう一回対戦する'), findsOneWidget);
      // 初回の導線の「手持ちを増やす」は出さない
      expect(find.byKey(const Key('first-battle-capture-again')), findsNothing);
      await tapAndClose(
        tester: tester,
        finder: key == null ? find.text('もどる') : find.byKey(key),
      );
      expect(find.byType(BattleScreen), findsNothing);
      expect(poppedActions, [expectedAction]);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('決着の後の記録が終わるまで「もう一回対戦する」は押せず、終わると押せる', (tester) async {
    final recordStart = Completer<String?>();
    await pumpBattle(
      tester: tester,
      playerParty: party(
        monsterIDs: strongMonsterIDs.take(1).toList(),
        level: 60,
      ),
      opponentParty: party(
        monsterIDs: weakMonsterIDs.take(1).toList(),
        level: 1,
      ),
      firstBattleBornMonster: null,
      startBattleRecord: () => recordStart.future,
    );
    await playUntilFinished(tester: tester);
    final rematch = find.byKey(const Key('battle-rematch'));
    expect(tester.widget<FilledButton>(rematch).onPressed, isNull);

    recordStart.complete('battle-1');
    await tester.pump();
    await tester.pump();
    expect(tester.widget<FilledButton>(rematch).onPressed, isNotNull);
  });

  testWidgets('他のユーザーとの対戦の勝敗の画面は「もどる」だけを出し「もう一回対戦する」を出さない', (tester) async {
    await pumpBattle(
      tester: tester,
      playerParty: party(
        monsterIDs: strongMonsterIDs.take(1).toList(),
        level: 60,
      ),
      opponentParty: party(
        monsterIDs: weakMonsterIDs.take(1).toList(),
        level: 1,
      ),
      firstBattleBornMonster: null,
      opponentKind: BattleOpponentKind.pvp,
    );
    await playUntilFinished(tester: tester, finishedButton: find.text('もどる'));
    expect(find.byKey(const Key('battle-rematch')), findsNothing);
  });

  testWidgets('初回の 1 戦の勝敗の画面は「図鑑を見る」「もう一回対戦する」「手持ちを増やす」を出し、押した方の値で閉じる', (
    tester,
  ) async {
    for (final (finder, expectedAction) in [
      (find.text('図鑑を見る'), BattleScreenAction.openDex),
      (find.text('もう一回対戦する'), BattleScreenAction.rematch),
      (find.text('手持ちを増やす'), null),
    ]) {
      final bornMonster = sampleMonsterWithLevel(
        monsterID: strongMonsterIDs.first,
        level: 60,
      );
      final poppedActions = await pumpBattle(
        tester: tester,
        playerParty: [bornMonster],
        opponentParty: party(
          monsterIDs: weakMonsterIDs.take(1).toList(),
          level: 1,
        ),
        firstBattleBornMonster: bornMonster,
      );
      await playUntilFinished(tester: tester);
      expect(find.text('もどる'), findsNothing);
      await tapAndClose(tester: tester, finder: finder);
      expect(find.byType(BattleScreen), findsNothing);
      expect(poppedActions, [expectedAction]);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
