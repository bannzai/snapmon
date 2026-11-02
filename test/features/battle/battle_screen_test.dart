import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';
import 'package:snapmon/domain/monster/stat_calculation.dart';
import 'package:snapmon/features/battle/battle_field_game.dart';
import 'package:snapmon/features/battle/battle_recorder.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/reference/move_detail_screen.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/share_cards.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/widgets/app_content_width.dart';
import 'package:snapmon/widgets/monster_parts.dart';

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
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
          playerProfile: (displayName: 'ばんざい', iconPath: null),
          opponentProfile: (displayName: 'CPU リク', iconPath: null),
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
            locale: const Locale('ja'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
              playerProfile: null,
              opponentProfile: (displayName: 'CPU リク', iconPath: null),
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

  testWidgets('相手と自分のトレーナーのアイコン (未登録は既定の印) と名前を、それぞれの情報カードの上に出す', (
    tester,
  ) async {
    await pumpBattleScreen(
      tester: tester,
      battleRecorder: fakeBattleRecorder(
        calls: RecordedBattleCalls(),
        startBattleRecord: () async => null,
        recordedLevels: const {},
      ),
      playerMonster: strongPlayer,
      artImage: null,
    );
    for (final (key, displayName, mark) in [
      ('battle-opponent-trainer', 'CPU リク', 'C'),
      ('battle-player-trainer', 'ばんざい', 'ば'),
    ]) {
      for (final text in [displayName, mark]) {
        expect(
          find.descendant(of: find.byKey(Key(key)), matching: find.text(text)),
          findsOneWidget,
          reason: '$key: $text',
        );
      }
    }
    // 相手の札は上、自分の札は下に出る
    expect(
      tester.getTopLeft(find.byKey(const Key('battle-opponent-trainer'))).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const Key('battle-player-trainer'))).dy,
      ),
    );
  });

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
    // 属性はモンスターの属性と同じ色の札で出し、威力と PP はラベル付きの数値で出す
    expect(
      tester
          .widget<ElementTypeTag>(
            find.descendant(
              of: moveSlot,
              matching: find.byType(ElementTypeTag),
            ),
          )
          .elementTypeId,
      'heat',
    );
    expect(
      find.descendant(
        of: moveSlot,
        matching: find.text('PP 35/35', findRichText: true),
      ),
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

  testWidgets('技のボタンを長押しすると、ターンを進めずにその技の詳細を開く', (tester) async {
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
    final logBeforeLongPress = tester
        .widget<Text>(find.byKey(const Key('battle-log')))
        .data;

    // マグモンの覚える技の一覧の 3 番目が ゆげのもや (heat_1b。先に動くと 1.3 倍)
    await tester.longPress(find.byKey(const Key('move-slot-2')));
    // 画面の遷移の演出を終える (Flame のゲームループがあるため pumpAndSettle は使わない)
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(MoveDetailScreen), findsOneWidget);
    expect(
      tester.widget<MoveDetailScreen>(find.byType(MoveDetailScreen)).move.id,
      'heat_1b',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('move-special-effect-formula')))
          .data,
      'そのターンに相手より先に行動した なら 1.3、それ以外は 1',
    );

    // バトルの画面は戻るボタンの無い AppBar で作られているため、tester.pageBack ではなく Navigator で閉じる
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    // 戻る演出を始める frame・終える frame・route を外す frame を進める (pumpAndSettle は上と同じ理由で使わない)
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(MoveDetailScreen), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(const Key('battle-log'))).data,
      logBeforeLongPress,
    );
    expect(find.text('ターン 1'), findsOneWidget);
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

    // 元の写真のパスは読まず、切り出した画像だけを読む
    // (1・2 回目はバトルのフィールドの自分と相手の見本のモンスター、3 回目は共有のカード)
    expect(shareCalls.loadedArtPaths, [artPath, weakOpponent.artPath, artPath]);
    final rendered = shareCalls.renderedCards.single;
    expect(rendered.format, ShareCardFormat.portrait);
    // カードは画面の木の外で描くため、画面と同じ言語の Localizations で包んで渡す
    final localizedCard = rendered.card as Localizations;
    expect(localizedCard.locale, const Locale('ja'));
    final card = localizedCard.child! as BattleResultShareCard;
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

  testWidgets('両陣営の手持ちの切り出した画像 (見本のモンスターは同梱の画像) を読み、フィールドのモンスターを画像で描く', (
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
    expect(shareCalls.loadedArtPaths, [artPath, weakOpponent.artPath]);
    expect(game.playerMonsterComponent.monster.artPath, artPath);
    expect(game.playerMonsterComponent.artSprite, isNotNull);
    expect(
      game.opponentMonsterComponent.monster.artPath,
      'assets/samples/art/sample-ringora.png',
    );
    expect(game.opponentMonsterComponent.artSprite, isNotNull);
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

  group('情報カードの置き方', () {
    /// 自分を [playerMonster]、相手を [weakOpponent] にしたバトル画面を、[size] の画面で、
    /// 下のセーフエリアを [bottomPadding]、右のセーフエリアを [rightPadding] にして開く。
    /// アプリ (lib/app.dart) と同じく内容の幅の上限 (appContentMaxWidth) に収めて描く。
    Future<void> pumpBattleScreenWithSize({
      required WidgetTester tester,
      required Size size,
      required double bottomPadding,
      required double rightPadding,
      required OwnedMonster playerMonster,
    }) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..padding = FakeViewPadding(right: rightPadding, bottom: bottomPadding);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => constrainToAppContentWidth(
            child: child ?? const SizedBox.shrink(),
          ),
          theme: snapmonThemeData(),
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BattleScreen(
            playerParty: [playerMonster],
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
            firstBattleBornMonster: null,
            firstBattleMonsterIsNewlyBorn: false,
            playerProfile: (displayName: 'ばんざい', iconPath: null),
            opponentProfile: (displayName: 'CPU リク', iconPath: null),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
    }

    /// [strongPlayer] の名前を、生成の名前の上限 9 文字 (functions/src/generation/prompts/describe_subject.ts の NAME_LENGTH_RANGE) にした 1 体。
    final longNamedPlayer = OwnedMonster(
      definition: MonsterDefinition(
        id: strongPlayer.definition.id,
        sourcePhotoReference: strongPlayer.definition.sourcePhotoReference,
        name: 'ゆげたつマグカップ',
        encyclopediaText: strongPlayer.definition.encyclopediaText,
        elementTypeIds: strongPlayer.definition.elementTypeIds,
        learnset: strongPlayer.definition.learnset,
        baseStats: strongPlayer.definition.baseStats,
        individualValues: strongPlayer.definition.individualValues,
        statCalculationVersion: strongPlayer.definition.statCalculationVersion,
        masterVersion: strongPlayer.definition.masterVersion,
      ),
      level: strongPlayer.level,
      artPath: strongPlayer.artPath,
      definitionIds: strongPlayer.definitionIds,
      decoration: strongPlayer.decoration,
      decorationVersion: strongPlayer.decorationVersion,
    );

    /// フィールド (Flame のゲームとその上に重ねる帯・カード) の Stack の矩形。
    Rect fieldRect({required WidgetTester tester}) => tester.getRect(
      find
          .ancestor(
            of: find.byType(GameWidget<BattleFieldGame>),
            matching: find.byType(Stack),
          )
          .first,
    );

    /// 相手の情報カード (相手のモンスターの名前を含む Positioned) の矩形。
    Rect opponentStatusCardRect({required WidgetTester tester}) =>
        tester.getRect(
          find.ancestor(
            of: find.text(weakOpponent.definition.name),
            matching: find.byType(Positioned),
          ),
        );

    /// 自分の情報カード (HP の数値を含む情報カード。HP の数値は自分のカードにだけ出る) の矩形。
    /// 同じ Positioned にトレーナーの札が載るため、Positioned ではなく情報カードの widget を探す
    Rect playerStatusCardRect({required WidgetTester tester}) => tester.getRect(
      find.ancestor(
        of: find.textContaining('HP '),
        matching: find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_MonsterStatusCard',
        ),
      ),
    );

    /// ログの帯 (背景の箱) の矩形。
    Rect battleLogRect({required WidgetTester tester}) => tester.getRect(
      find
          .ancestor(
            of: find.byKey(const Key('battle-log')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );

    /// フィールドに描いた 2 体 (相手・自分) の絵の、画面の座標での矩形。
    List<Rect> monsterArtRects({required WidgetTester tester}) {
      final gameWidget = find.byType(GameWidget<BattleFieldGame>);
      final game = tester.widget<GameWidget<BattleFieldGame>>(gameWidget).game!;
      final gameTopLeft = tester.getTopLeft(gameWidget);
      return [
        game.opponentMonsterComponent.toRect().shift(gameTopLeft),
        game.playerMonsterComponent.toRect().shift(gameTopLeft),
      ];
    }

    /// 2 体の絵がフィールドに収まり、2 枚の情報カードとログの帯に重ならず、見分けられる大きさで描かれていることを確かめる。
    void expectMonsterArtsVisible({required WidgetTester tester}) {
      final field = fieldRect(tester: tester);
      for (final artRect in monsterArtRects(tester: tester)) {
        expect(field.intersect(artRect), artRect);
        for (final coveringRect in [
          opponentStatusCardRect(tester: tester),
          playerStatusCardRect(tester: tester),
          battleLogRect(tester: tester),
        ]) {
          expect(artRect.overlaps(coveringRect), isFalse);
        }
        // 絵の大きさの下限 (フィールドの高さの 0.15。battle_field_game.dart の _layout) に張り付いた絵 (844×390 で 18.6) は
        // 被写体を見分けられないため、フィールドの高さの半分以上を求める
        expect(artRect.height, greaterThanOrEqualTo(field.height / 2));
      }
    }

    /// ログの文が帯の中で切れず、ログの帯が、フィールドに重ねるならフィールドの中に収まり (フィールドの外は切れて見えないため)、
    /// フィールドの外に置くならフィールドに掛からず、どちらでも下のセーフエリア [bottomPadding] より上の画面に収まることを確かめる。
    void expectBattleLogNotCut({
      required WidgetTester tester,
      required double bottomPadding,
    }) {
      // フィールドに重ねた帯は Stack の高さまでに抑えられ、文が収まらない時は帯の矩形ではなく文の段落が帯の中で切れるため、
      // 段落の幅で全文を描くのに要る高さと、実際の段落の高さを比べる
      final logParagraph = tester.renderObject<RenderParagraph>(
        find.byKey(const Key('battle-log')),
      );
      expect(
        logParagraph.size.height,
        greaterThanOrEqualTo(
          logParagraph.getMaxIntrinsicHeight(logParagraph.size.width),
        ),
        reason: 'ログの文が帯の中で切れている',
      );
      final field = fieldRect(tester: tester);
      final log = battleLogRect(tester: tester);
      expect(
        field.intersect(log) == log || !field.overlaps(log),
        isTrue,
        reason: 'ログの帯 $log がフィールド $field の端に掛かって切れている',
      );
      expect(log.top, greaterThanOrEqualTo(0));
      expect(
        log.bottom,
        lessThanOrEqualTo(tester.view.physicalSize.height - bottomPadding),
      );
    }

    // 下のセーフエリア 21: 横向きの iPhone (ホームインジケーターのある機種) の下のインセット
    for (final bottomPadding in [0.0, 21.0]) {
      testWidgets(
        '横向きのスマホ (844×390、下のセーフエリア $bottomPadding) では、相手のカード全体がフィールドに収まり、ログの帯と重ならない',
        (tester) async {
          await pumpBattleScreenWithSize(
            tester: tester,
            size: const Size(844, 390),
            bottomPadding: bottomPadding,
            rightPadding: 0,
            playerMonster: strongPlayer,
          );
          final field = fieldRect(tester: tester);
          final card = opponentStatusCardRect(tester: tester);

          expect(card.top, greaterThanOrEqualTo(field.top));
          expect(card.bottom, lessThanOrEqualTo(field.bottom));
          expect(card.overlaps(battleLogRect(tester: tester)), isFalse);
          // 札を出すとカードかログの帯と重なる低さのため、相手と自分のトレーナーの札は出さない
          expect(
            find.byKey(const Key('battle-opponent-trainer')),
            findsNothing,
          );
          expect(find.byKey(const Key('battle-player-trainer')), findsNothing);
        },
      );

      testWidgets(
        '横向きのスマホ (844×390、下のセーフエリア $bottomPadding) では、自分のカード全体がフィールドに収まり、ログの帯・相手のカードと重ならない',
        (tester) async {
          await pumpBattleScreenWithSize(
            tester: tester,
            size: const Size(844, 390),
            bottomPadding: bottomPadding,
            rightPadding: 0,
            playerMonster: strongPlayer,
          );
          final field = fieldRect(tester: tester);
          final card = playerStatusCardRect(tester: tester);

          expect(card.top, greaterThanOrEqualTo(field.top));
          expect(card.bottom, lessThanOrEqualTo(field.bottom));
          expect(card.right, lessThanOrEqualTo(field.right));
          expect(card.overlaps(battleLogRect(tester: tester)), isFalse);
          expect(
            card.overlaps(opponentStatusCardRect(tester: tester)),
            isFalse,
          );
        },
      );

      testWidgets(
        '横向きのスマホ (844×390、下のセーフエリア $bottomPadding) では、自分のモンスターの名前が 9 文字でもカード全体がフィールドに収まる',
        (tester) async {
          await pumpBattleScreenWithSize(
            tester: tester,
            size: const Size(844, 390),
            bottomPadding: bottomPadding,
            rightPadding: 0,
            playerMonster: longNamedPlayer,
          );

          expect(
            playerStatusCardRect(tester: tester).bottom,
            lessThanOrEqualTo(fieldRect(tester: tester).bottom),
          );
        },
      );

      testWidgets(
        '横向きのスマホ (844×390、下のセーフエリア $bottomPadding) では、バトルの始まりのログの帯が切れずに画面に収まる',
        (tester) async {
          await pumpBattleScreenWithSize(
            tester: tester,
            size: const Size(844, 390),
            bottomPadding: bottomPadding,
            rightPadding: 0,
            playerMonster: strongPlayer,
          );

          expectBattleLogNotCut(tester: tester, bottomPadding: bottomPadding);
        },
      );

      testWidgets(
        '横向きのスマホ (844×390、下のセーフエリア $bottomPadding) では、2 体の絵がフィールドに収まり、2 枚のカードとログの帯に隠れない',
        (tester) async {
          await pumpBattleScreenWithSize(
            tester: tester,
            size: const Size(844, 390),
            bottomPadding: bottomPadding,
            rightPadding: 0,
            playerMonster: strongPlayer,
          );

          expectMonsterArtsVisible(tester: tester);
        },
      );

      testWidgets(
        '横向きのスマホ (844×390、下のセーフエリア $bottomPadding) では、技の特殊効果の説明が付いたログの帯も切れずに画面に収まり、2 体の絵と重ならない',
        (tester) async {
          await pumpBattleScreenWithSize(
            tester: tester,
            size: const Size(844, 390),
            bottomPadding: bottomPadding,
            rightPadding: 0,
            playerMonster: strongPlayer,
          );
          // マグモンの覚える技の一覧の 3 番目が ゆげのもや (heat_1b)。1 ターン目に先に動き、説明と相性の行が続いて 3 行になる
          // (「技の枠に特殊効果の短い説明を出し、効果が働いた技はログに説明文を出す」のテスト)
          final moveSlot = find.byKey(const Key('move-slot-2'));
          await tester.ensureVisible(moveSlot);
          await tester.tap(moveSlot);
          await tester.pump();
          expect(
            tester.widget<Text>(find.byKey(const Key('battle-log'))).data,
            contains('先に行動すると威力が上がる'),
          );

          expectBattleLogNotCut(tester: tester, bottomPadding: bottomPadding);
          expectMonsterArtsVisible(tester: tester);
          // 演出の待ち (Future.delayed) をテストの終わりに残さない
          await tester.pump(const Duration(seconds: 5));
        },
      );
    }

    testWidgets(
      '幅の狭い低い画面 (390×480) では、トレーナーの札を出さず、カード全体がフィールドに収まり、ログの帯と重ならない',
      (tester) async {
        await pumpBattleScreenWithSize(
          tester: tester,
          size: const Size(390, 480),
          bottomPadding: 0,
          rightPadding: 0,
          playerMonster: strongPlayer,
        );
        final field = fieldRect(tester: tester);
        final card = opponentStatusCardRect(tester: tester);

        expect(card.top, greaterThanOrEqualTo(field.top));
        expect(card.bottom, lessThanOrEqualTo(field.bottom));
        expect(card.overlaps(battleLogRect(tester: tester)), isFalse);
        expect(find.byKey(const Key('battle-opponent-trainer')), findsNothing);
        expect(find.byKey(const Key('battle-player-trainer')), findsNothing);
      },
    );

    testWidgets('低くて幅も狭い画面 (390×390) では、自分のカードをログの帯の右に並べず、ログの帯の幅を残す', (
      tester,
    ) async {
      await pumpBattleScreenWithSize(
        tester: tester,
        size: const Size(390, 390),
        bottomPadding: 0,
        rightPadding: 0,
        playerMonster: strongPlayer,
      );

      expect(battleLogRect(tester: tester).width, greaterThan(100));
      expect(
        playerStatusCardRect(tester: tester).bottom,
        fieldRect(tester: tester).bottom - 24,
      );
    });

    // 高さ 375・下のセーフエリア 21 は、下のパネルが上限 (高さの 0.6) まで伸び、フィールド (97) が 2 枚のカードの下端 (102) より低くなる画面
    testWidgets(
      '横向きのスマホでフィールドがカードより低い時 (844×375、下のセーフエリア 21) も、2 体の絵がフィールドに収まる',
      (tester) async {
        await pumpBattleScreenWithSize(
          tester: tester,
          size: const Size(844, 375),
          bottomPadding: 21,
          rightPadding: 0,
          playerMonster: strongPlayer,
        );
        final field = fieldRect(tester: tester);

        for (final artRect in monsterArtRects(tester: tester)) {
          expect(field.inflate(0.001).intersect(artRect), artRect);
        }
      },
    );

    testWidgets('横向きのスマホで文字を 2 倍にしても、ログの帯は高さの 0.3 までに収まり、技のボタンを押せる', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpBattleScreenWithSize(
        tester: tester,
        size: const Size(844, 390),
        bottomPadding: 21,
        rightPadding: 0,
        playerMonster: strongPlayer,
      );
      final moveSlot = find.byKey(const Key('move-slot-2'));
      await tester.ensureVisible(moveSlot);
      await tester.tap(moveSlot);
      await tester.pump();

      // 帯 (DecoratedBox) はスクロールの中で文の高さまで伸びるため、見えている範囲としてスクロールの矩形を測る
      expect(
        tester
            .getRect(
              find
                  .ancestor(
                    of: find.byKey(const Key('battle-log')),
                    matching: find.byType(SingleChildScrollView),
                  )
                  .first,
            )
            .height,
        lessThanOrEqualTo(390 * 0.3),
      );
      final nextMoveSlot = find.byKey(const Key('move-slot-0'));
      await tester.ensureVisible(nextMoveSlot);
      expect(nextMoveSlot.hitTestable(), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    // 幅 600 は内容の幅の上限と同じで、両脇の余白で右のセーフエリアが差し引かれずに残る
    testWidgets('低い画面で右のセーフエリアがある時 (600×390、右 30) は、横に並べた自分のカードをセーフエリアの内側に置く', (
      tester,
    ) async {
      await pumpBattleScreenWithSize(
        tester: tester,
        size: const Size(600, 390),
        bottomPadding: 0,
        rightPadding: 30,
        playerMonster: strongPlayer,
      );
      final field = fieldRect(tester: tester);
      final card = playerStatusCardRect(tester: tester);

      expect(card.right, lessThanOrEqualTo(field.right - 30));
      expect(card.top, greaterThanOrEqualTo(field.top));
      expect(card.overlaps(battleLogRect(tester: tester)), isFalse);
    });

    testWidgets('縦向きのスマホ (390×844) では、ログの帯の下 (上から 96) に相手のトレーナーの札、その下にカードを置く', (
      tester,
    ) async {
      await pumpBattleScreenWithSize(
        tester: tester,
        size: const Size(390, 844),
        bottomPadding: 0,
        rightPadding: 0,
        playerMonster: strongPlayer,
      );

      expect(
        tester.getTopLeft(find.byKey(const Key('battle-opponent-trainer'))),
        const Offset(20, 96),
      );
      // カードは札の下に、札とカードの間 6 を空けて置く
      expect(
        opponentStatusCardRect(tester: tester).topLeft,
        Offset(
          20,
          tester
                  .getBottomLeft(
                    find.byKey(const Key('battle-opponent-trainer')),
                  )
                  .dy +
              6,
        ),
      );
      expect(battleLogRect(tester: tester).left, 20);
      expect(find.byKey(const Key('battle-player-trainer')), findsOneWidget);
    });

    testWidgets('縦向きのスマホ (390×844) では、今までどおりログの帯を左右いっぱいに、自分のカードを右下に置く', (
      tester,
    ) async {
      await pumpBattleScreenWithSize(
        tester: tester,
        size: const Size(390, 844),
        bottomPadding: 0,
        rightPadding: 0,
        playerMonster: strongPlayer,
      );

      expect(battleLogRect(tester: tester).left, 20);
      expect(battleLogRect(tester: tester).right, 370);
      final playerCard = playerStatusCardRect(tester: tester);
      expect(playerCard.right, 370);
      expect(playerCard.width, 190);
      expect(playerCard.bottom, fieldRect(tester: tester).bottom - 24);
    });
  });
}
