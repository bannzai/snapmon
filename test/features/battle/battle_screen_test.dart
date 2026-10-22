import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/features/battle/battle_field_game.dart';
import 'package:snapmon/features/battle/battle_recorder.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// レベル 7 のマグモン。相手 ([weakOpponent]) より十分強く、1〜2 ターンで勝つ。
  final strongPlayer = sampleData.monsterById(monsterId: 'sample-mugmon');

  /// レベル 1 のリンゴラ。
  final weakOpponent = sampleData.monsterById(monsterId: 'sample-ringora');

  late List<Map<String, int>> levelChanges;

  /// [battleRecorder] を使うバトル画面を、iPhone の画面の大きさ (モックの 390 × 844) で開く。
  Future<void> pumpBattleScreen({
    required WidgetTester tester,
    required BattleRecorder battleRecorder,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    levelChanges = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        home: BattleScreen(
          playerParty: [strongPlayer],
          opponentParty: [weakOpponent],
          definitions: sampleData.definitions,
          randomSeed: 1,
          battleRecorder: battleRecorder,
          onPlayerLevelsChanged: ({required levelsByMonsterId}) =>
              levelChanges.add(levelsByMonsterId),
        ),
      ),
    );
    // バトル画面の Flame のゲームループは止まらないため、pumpAndSettle を使わず時間を指定して進める
    await tester.pump(const Duration(seconds: 1));
  }

  /// 1 番目の技 (使える攻撃技が無ければわるあがき) を選んで決着まで進める。
  Future<void> playUntilFinished({required WidgetTester tester}) async {
    // 100 ターン: 見本の手持ち同士なら数ターンで決着するため、決着しない不具合でテストが止まらない上限として十分な数
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
      // 1 ターンの演出 (技 2 回・倒れる・交代) が終わるまで進める
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
    }
  }

  testWidgets('技を選ぶと決着まで進み、勝敗とレベルの上がり方を出して記録と計測をする', (tester) async {
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      battleRecorder: fakeBattleRecorder(
        calls: calls,
        startBattleRecord: () async => 'battle-1',
        recordedLevels: {strongPlayer.definition.id: 9},
      ),
    );
    expect(calls.startedPartyMonsterIds, [
      [strongPlayer.definition.id],
    ]);

    await playUntilFinished(tester: tester);
    expect(find.text('かった'), findsOneWidget);
    expect(
      // 端末の計算 (8) ではなく Functions が返したレベル (9) を出す
      find.text('${strongPlayer.definition.name}  Lv. 7 → 9'),
      findsOneWidget,
    );
    expect(find.text('記録しました'), findsOneWidget);

    final completed = calls.completedBattles.single;
    expect(completed.battleId, 'battle-1');
    expect(completed.participantMonsterIds, [strongPlayer.definition.id]);
    expect(completed.winner, BattleSideId.player);
    // 記録する対戦では端末の計算 (8) ではなく、Functions が返したレベルだけを反映する
    expect(levelChanges, [
      {strongPlayer.definition.id: 9},
    ]);

    final logged = calls.loggedEvents.single;
    expect(logged.event, AnalyticsEvent.battleCompleted);
    expect(logged.parameters, {
      'result': 'win',
      'turn_count': completed.turnCount,
    });
  });

  testWidgets('年齢の確認を通ったログインが無い時は記録せず、そのことを出す', (tester) async {
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      battleRecorder: fakeBattleRecorder(
        calls: calls,
        startBattleRecord: () async => null,
        recordedLevels: const {},
      ),
    );
    await playUntilFinished(tester: tester);
    expect(find.text('ログインしていないため記録していません'), findsOneWidget);
    expect(calls.completedBattles, isEmpty);
    expect(levelChanges, [
      {strongPlayer.definition.id: 8},
    ]);
    expect(
      find.text('${strongPlayer.definition.name}  Lv. 7 → 8'),
      findsOneWidget,
    );
    expect(calls.loggedEvents, hasLength(1));
  });

  testWidgets('バトルの開始の記録に失敗しても最後まで戦え、エラーをそのまま出す', (tester) async {
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      battleRecorder: fakeBattleRecorder(
        calls: calls,
        startBattleRecord: () async => throw Exception('unavailable'),
        recordedLevels: const {},
      ),
    );
    await playUntilFinished(tester: tester);
    expect(find.text('かった'), findsOneWidget);
    expect(find.text('Exception: unavailable'), findsOneWidget);
    expect(calls.completedBattles, isEmpty);
    // 記録に失敗した対戦はサーバーと食い違わないよう、図鑑のレベルを変えない
    expect(levelChanges, isEmpty);
    expect(find.textContaining('Lv. 7 →'), findsNothing);
  });

  testWidgets('技を使うと被弾した側に属性のパーティクルが出て、演出の間は技を選べない', (tester) async {
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      battleRecorder: fakeBattleRecorder(
        calls: calls,
        startBattleRecord: () async => 'battle-1',
        recordedLevels: const {},
      ),
    );
    final game = tester
        .widget<GameWidget<BattleFieldGame>>(
          find.byType(GameWidget<BattleFieldGame>),
        )
        .game!;
    await tester.tap(find.byKey(const Key('move-slot-0')));
    await tester.pump();
    // 攻撃の前進の往復 (0.3 秒) が終わり、被弾の演出 (0.5 秒) の途中まで進める
    await tester.pump(const Duration(milliseconds: 400));
    expect(game.children.whereType<ParticleSystemComponent>(), isNotEmpty);
    expect(
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(const Key('move-slot-0')),
              matching: find.byType(InkWell),
            ),
          )
          .onTap,
      isNull,
    );
    await playUntilFinished(tester: tester);
  });
}
