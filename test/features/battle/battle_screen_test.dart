import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';
import 'package:snapmon/domain/monster/stat_calculation.dart';
import 'package:snapmon/features/battle/battle_field_game.dart';
import 'package:snapmon/features/battle/battle_recorder.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/share_cards.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// レベル 7 のマグモン。相手 ([weakOpponent]) より十分強く、1〜2 ターンで勝つ。
  final strongPlayer = sampleData.monsterById(monsterId: 'sample-mugmon');

  /// レベル 1 のリンゴラ。
  final weakOpponent = sampleData.monsterById(monsterId: 'sample-ringora');

  late List<Map<String, int>> levelChanges;
  late RecordedShareCalls shareCalls;

  /// [battleRecorder] を使い、自分の手持ちを [playerMonster] 1 体にしたバトル画面を、iPhone の画面の大きさ (モックの 390 × 844) で開く。
  /// 共有は [shareCalls] に残し、切り出した画像の読み込みには [artImage] を返す。
  Future<void> pumpBattleScreen({
    required WidgetTester tester,
    required BattleRecorder battleRecorder,
    required OwnedMonster playerMonster,
    required ui.Image? artImage,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    levelChanges = [];
    shareCalls = RecordedShareCalls();
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        home: BattleScreen(
          playerParty: [playerMonster],
          opponentParty: [weakOpponent],
          opponentKind: BattleOpponentKind.pvp,
          definitions: sampleData.definitions,
          randomSeed: 1,
          battleRecorder: battleRecorder,
          onPlayerLevelsChanged: ({required levelsByMonsterId}) =>
              levelChanges.add(levelsByMonsterId),
          cardSharer: fakeCardSharer(
            calls: shareCalls,
            artImage: artImage,
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

  for (final (isNewlyBorn, label) in [
    (true, 'あたらしい なかま'),
    (false, 'きみの なかま'),
  ]) {
    testWidgets(
      '初回の 1 戦の勝敗の画面のカードは、新しく生まれた時だけ「あたらしい なかま」と出す (isNewlyBorn: $isNewlyBorn)',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            theme: snapmonThemeData(),
            home: BattleScreen(
              playerParty: [strongPlayer],
              opponentParty: [weakOpponent],
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
              firstBattleBornMonster: strongPlayer,
              firstBattleMonsterIsNewlyBorn: isNewlyBorn,
              opponentSafetyMenu: null,
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        // 100 ターン: playUntilFinished と同じ上限。初回の 1 戦の勝敗の画面には「もどる」の代わりに「図鑑を見る」が出る
        for (
          var turn = 0;
          turn < 100 && find.text('図鑑を見る').evaluate().isEmpty;
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
        expect(find.text(label), findsOneWidget);
      },
    );
  }

  testWidgets('技の枠に特殊効果の短い説明を出し、効果が働いた技はログに説明文を出す', (tester) async {
    MonsterStats statsOf({required OwnedMonster monster}) => calculateStats(
      baseStats: monster.definition.baseStats,
      individualValues: monster.definition.individualValues,
      level: monster.level,
      statCalculationVersion: monster.definition.statCalculationVersion,
    );
    // 「先に動くと強い」(ゆげのもや) が 1 ターン目に働く前提: マグモンの方が速く、同速の乱数に頼らない
    expect(
      statsOf(monster: strongPlayer).speed,
      greaterThan(statsOf(monster: weakOpponent).speed),
    );
    await pumpBattleScreen(
      tester: tester,
      playerMonster: strongPlayer,
      artImage: null,
      battleRecorder: fakeBattleRecorder(
        calls: RecordedBattleCalls(),
        startBattleRecord: () async => null,
        recordedLevels: const {},
      ),
    );
    // マグモンの覚える技の一覧の 3 番目が ゆげのもや (heat_1b。先に動くと 1.3 倍)
    final moveSlot = find.byKey(const Key('move-slot-2'));
    expect(
      find.descendant(of: moveSlot, matching: find.text('ゆげのもや')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: moveSlot, matching: find.text('先に動くと強い')),
      findsOneWidget,
    );

    await tester.tap(moveSlot);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('battle-log'))).data,
      // 熱はリンゴラの食べ物・植物の両方に 2 倍のため、相性の行も続く
      '${strongPlayer.definition.name} の ゆげのもや\n先に行動すると威力が上がる (今回は 1.3 倍)\nこうかは ばつぐんだ',
    );
    // 演出の待ち (Future.delayed) をテストの終わりに残さない
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('技を選ぶと決着まで進み、勝敗とレベルの上がり方を出して記録と計測をする', (tester) async {
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      playerMonster: strongPlayer,
      artImage: null,
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
      'opponent': 'pvp',
    });
  });

  testWidgets('記録しない時は端末の計算のレベルを反映し、記録していないことを出す', (tester) async {
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      playerMonster: strongPlayer,
      artImage: null,
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
      playerMonster: strongPlayer,
      artImage: null,
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
    expect(find.text('勝ち負けに関係なく 戦ったモンスターのレベルが上がる'), findsNothing);
    // 場のカードも確定していない上がった後のレベル (8) を出さない
    expect(find.text('Lv. 7'), findsOneWidget);
    expect(find.text('Lv. 8'), findsNothing);
  });

  testWidgets('計測の送信に失敗してもバトルの記録は続く', (tester) async {
    final calls = RecordedBattleCalls();
    final recorder = fakeBattleRecorder(
      calls: calls,
      startBattleRecord: () async => 'battle-1',
      recordedLevels: {strongPlayer.definition.id: 8},
    );
    await pumpBattleScreen(
      tester: tester,
      playerMonster: strongPlayer,
      artImage: null,
      battleRecorder: BattleRecorder(
        startBattleRecord: recorder.startBattleRecord,
        completeBattleRecord: recorder.completeBattleRecord,
        logEvent: ({required event, required parameters}) async =>
            throw Exception('analytics unavailable'),
      ),
    );
    await playUntilFinished(tester: tester);
    expect(find.text('記録しました'), findsOneWidget);
    expect(calls.completedBattles, hasLength(1));
  });

  testWidgets('勝敗の画面から結果を共有すると、切り出した画像だけを読んでカードを描き、共有イベントを送る', (tester) async {
    final artImage = (await tester.runAsync(
      () => createTestImage(width: 8, height: 8),
    ))!;
    addTearDown(artImage.dispose);
    const artPath = 'monsters/sample-mugmon/art.png';
    const sourcePhotoReference = 'users/uid-1/photos/original-photo';
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      playerMonster: ownedMonsterWithArt(
        monster: strongPlayer,
        artPath: artPath,
        sourcePhotoReference: sourcePhotoReference,
      ),
      artImage: artImage,
      battleRecorder: fakeBattleRecorder(
        calls: calls,
        startBattleRecord: () async => 'battle-1',
        recordedLevels: {strongPlayer.definition.id: 9},
      ),
    );
    await playUntilFinished(tester: tester);
    await tester.tap(find.text('結果を共有'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('share-format-portrait')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('share-confirm')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // 元の写真のパスは読まず、切り出した画像だけを読む (1 回目はバトルのフィールド、2 回目は共有のカード)
    expect(shareCalls.loadedArtPaths, [artPath, artPath]);
    final rendered = shareCalls.renderedCards.single;
    expect(rendered.format, ShareCardFormat.portrait);
    final card = rendered.card as BattleResultShareCard;
    expect(card.winner, BattleSideId.player);
    // 勝敗の画面と同じく、Functions が返した確定したレベルを描く
    expect(card.appliedLevels, {strongPlayer.definition.id: 9});
    expect(card.artImagesByPath.keys, [artPath]);
    final shared = shareCalls.sharedImages.single;
    expect(shared.fileName, 'snapmon-battle-portrait.png');
    expect(shared.text, contains('かった'));
    final logged = shareCalls.loggedEvents.single;
    expect(logged.event, AnalyticsEvent.contentShared);
    expect(logged.parameters, {
      'screen': 'battle_result',
      'format': 'portrait',
    });
  });

  testWidgets('切り出した画像を読めない時は共有せず、エラーをそのまま出す', (tester) async {
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      playerMonster: ownedMonsterWithArt(
        monster: strongPlayer,
        artPath: 'monsters/sample-mugmon/art.png',
        sourcePhotoReference: 'users/uid-1/photos/original-photo',
      ),
      artImage: null,
      battleRecorder: fakeBattleRecorder(
        calls: calls,
        startBattleRecord: () async => null,
        recordedLevels: const {},
      ),
    );
    await playUntilFinished(tester: tester);
    await tester.tap(find.text('結果を共有'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byKey(const Key('share-format-landscape')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(
      find.text('Bad state: monsters/sample-mugmon/art.png を読めない'),
      findsOneWidget,
    );
    expect(shareCalls.renderedCards, isEmpty);
    expect(shareCalls.sharedImages, isEmpty);
    expect(shareCalls.loggedEvents, isEmpty);
  });

  testWidgets('技を使うと被弾した側に属性のパーティクルが出て、演出の間は技を選べない', (tester) async {
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      playerMonster: strongPlayer,
      artImage: null,
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

  testWidgets('自分の手持ちの切り出した画像を読み、フィールドのモンスターを画像で描く (画像の無い相手は仮の絵のまま)', (
    tester,
  ) async {
    final artImage = (await tester.runAsync(
      () => createTestImage(width: 8, height: 8),
    ))!;
    addTearDown(artImage.dispose);
    const artPath = 'monsters/sample-mugmon/art.png';
    await pumpBattleScreen(
      tester: tester,
      playerMonster: ownedMonsterWithArt(
        monster: strongPlayer,
        artPath: artPath,
        sourcePhotoReference: 'users/uid-1/photos/original-photo',
      ),
      artImage: artImage,
      battleRecorder: fakeBattleRecorder(
        calls: RecordedBattleCalls(),
        startBattleRecord: () async => null,
        recordedLevels: const {},
      ),
    );
    final game = tester
        .widget<GameWidget<BattleFieldGame>>(
          find.byType(GameWidget<BattleFieldGame>),
        )
        .game!;

    // 元の写真は読まず、切り出した画像だけを読む
    expect(shareCalls.loadedArtPaths, [artPath]);
    expect(game.playerMonsterComponent.monster.artPath, artPath);
    expect(game.playerMonsterComponent.artSprite, isNotNull);
    expect(game.opponentMonsterComponent.artSprite, isNull);
    await playUntilFinished(tester: tester);
  });

  testWidgets('切り出した画像を読めない時は仮の絵のまま、エラーを出さずに最後まで戦える', (tester) async {
    final calls = RecordedBattleCalls();
    await pumpBattleScreen(
      tester: tester,
      playerMonster: ownedMonsterWithArt(
        monster: strongPlayer,
        artPath: 'monsters/sample-mugmon/art.png',
        sourcePhotoReference: 'users/uid-1/photos/original-photo',
      ),
      artImage: null,
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

    expect(game.playerMonsterComponent.artSprite, isNull);
    expect(find.byType(SnackBar), findsNothing);
    await playUntilFinished(tester: tester);
    expect(find.text('もどる'), findsOneWidget);
    expect(calls.completedBattles, hasLength(1));
  });
}
