import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';
import 'package:snapmon/domain/monster/stat_calculation.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/reference/move_detail_screen.dart';
import 'package:snapmon/features/result/monster_detail_card.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/widgets/monster_parts.dart';
import 'package:snapmon/widgets/storage_image.dart';

import '../../card_sharer_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  testWidgets('生まれたカードは元の写真を出さず、モンスターの絵を 1 枚の正方形で出す', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loadedStoragePaths = <String>[];
    final loadedArtPaths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StorageImageLoaderScope(
          loadBytes: ({required storagePath}) {
            loadedStoragePaths.add(storagePath);
            return Completer<Uint8List?>().future;
          },
          child: MonsterArtImageLoaderScope(
            // 読み終わらない画像にする (widget test の偽の時間の中では画像のデコードが終わらないため)
            loadArtImage: ({required artPath}) {
              loadedArtPaths.add(artPath);
              return Completer<ui.Image>().future;
            },
            child: ResultScreen(
              monster: ownedMonsterWithArt(
                monster: sampleData.monsterById(monsterId: 'sample-mugmon'),
                artPath: 'monsters/sample-mugmon/art.png',
                sourcePhotoReference: 'users/uid-1/photos/original-photo',
              ),
              dexStore: DexStore(definitions: sampleData.definitions),
              origin: ResultScreenOrigin.newlyBorn,
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
    await tester.pump();

    expect(find.byType(StorageImage), findsNothing);
    expect(loadedStoragePaths, isEmpty);
    expect(find.text('写真'), findsNothing);
    expect(find.byType(MonsterArt), findsOneWidget);
    expect(loadedArtPaths, ['monsters/sample-mugmon/art.png']);
    final artSize = tester.getSize(find.byType(MonsterArt));
    expect(artSize.width, artSize.height);
    // 絵は左上に固定の一辺で置き、右にステータスの目盛りを並べる (#216)
    expect(artSize.width, monsterDetailArtSize);
  });

  testWidgets('ステータスは目盛りと実際の値で出し、技はバトルと同じ 2 列 × 2 行の枠に並べる', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final monster = sampleData.monsterById(monsterId: 'sample-mugmon');
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResultScreen(
          monster: monster,
          dexStore: DexStore(definitions: sampleData.definitions),
          origin: ResultScreenOrigin.dex,
          cardSharer: fakeCardSharer(
            calls: RecordedShareCalls(),
            artImage: null,
            shareResultStatus: ShareResultStatus.success,
          ),
        ),
      ),
    );

    // ステータスの目盛りは絵の右に、絵の上端から順に 4 本並ぶ
    final artRect = tester.getRect(find.byType(MonsterArt));
    double previousGaugeBottom = artRect.top;
    final stats = calculateStats(
      baseStats: monster.definition.baseStats,
      individualValues: monster.definition.individualValues,
      level: monster.level,
      statCalculationVersion: monster.definition.statCalculationVersion,
    );
    for (final statKind in StatKind.values) {
      final gauge = find.byKey(Key('stat-gauge-${statKind.name}'));
      final gaugeRect = tester.getRect(gauge);
      expect(gaugeRect.left, greaterThan(artRect.right), reason: statKind.name);
      expect(gaugeRect.top, greaterThanOrEqualTo(previousGaugeBottom));
      previousGaugeBottom = gaugeRect.bottom;
      expect(
        find.descendant(
          of: gauge,
          matching: find.text('${stats.valueOf(statKind: statKind)}'),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.descendant(
                of: gauge,
                matching: find.byType(LinearProgressIndicator),
              ),
            )
            .value,
        statStrengthRatio(
          statKind: statKind,
          baseStats: monster.definition.baseStats,
          individualValues: monster.definition.individualValues,
          master: sampleData.definitions,
        ),
      );
    }

    // 技の枠は 4 つで、1 行目の 2 つは同じ高さに横に並び、2 行目はその下に並ぶ
    final slotMoveIds = equippedLearnsetEntries(
      learnset: monster.definition.learnset,
      actionCardMoveIds: monster.actionCardMoveIds,
      level: monster.level,
    );
    expect(slotMoveIds, hasLength(maximumEquippedMoveCount));
    final slotRects = [
      for (final moveId in slotMoveIds)
        tester.getRect(find.byKey(Key('move-chip-$moveId'))),
    ];
    expect(slotRects[0].top, slotRects[1].top);
    expect(slotRects[0].right, lessThanOrEqualTo(slotRects[1].left));
    expect(slotRects[2].top, slotRects[3].top);
    expect(slotRects[2].top, greaterThanOrEqualTo(slotRects[0].bottom));
    expect(slotRects[0].left, slotRects[2].left);
  });

  testWidgets('端末の文字を 2 倍にしてもステータスの目盛りがはみ出さない', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResultScreen(
          monster: sampleData.monsterById(monsterId: 'sample-mugmon'),
          dexStore: DexStore(definitions: sampleData.definitions),
          origin: ResultScreenOrigin.dex,
          cardSharer: fakeCardSharer(
            calls: RecordedShareCalls(),
            artImage: null,
            shareResultStatus: ShareResultStatus.success,
          ),
        ),
      ),
    );
    // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
    expect(tester.takeException(), isNull);
    // 目盛りは絵より高くなってよい (高さを絵に固定しない)
    expect(
      tester.getRect(find.byKey(const Key('stat-gauge-speed'))).bottom,
      greaterThan(tester.getRect(find.byType(MonsterArt)).bottom),
    );
  });

  testWidgets('技が 4 つに満たないモンスターは、空の枠を「—」で埋めて 4 つの枠を保つ', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final sampleMonster = sampleData.monsterById(monsterId: 'sample-mugmon');
    final sampleDefinition = sampleMonster.definition;
    // 覚える技を 1 つだけ残す
    final monster = OwnedMonster(
      definition: MonsterDefinition(
        id: sampleDefinition.id,
        sourcePhotoReference: sampleDefinition.sourcePhotoReference,
        name: sampleDefinition.name,
        encyclopediaText: sampleDefinition.encyclopediaText,
        elementTypeIds: sampleDefinition.elementTypeIds,
        learnset: [sampleDefinition.learnset.first],
        baseStats: sampleDefinition.baseStats,
        individualValues: sampleDefinition.individualValues,
        statCalculationVersion: sampleDefinition.statCalculationVersion,
        masterVersion: sampleDefinition.masterVersion,
      ),
      level: sampleMonster.level,
      actionCardMoveIds: const [],
      artPath: sampleMonster.artPath,
      definitionIds: sampleMonster.definitionIds,
      decoration: sampleMonster.decoration,
      decorationVersion: sampleMonster.decorationVersion,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResultScreen(
          monster: monster,
          dexStore: DexStore(definitions: sampleData.definitions),
          origin: ResultScreenOrigin.dex,
          cardSharer: fakeCardSharer(
            calls: RecordedShareCalls(),
            artImage: null,
            shareResultStatus: ShareResultStatus.success,
          ),
        ),
      ),
    );

    expect(
      find.byKey(Key('move-chip-${monster.definition.learnset.first.moveId}')),
      findsOneWidget,
    );
    for (final slotIndex in [1, 2, 3]) {
      expect(find.byKey(Key('move-chip-empty-$slotIndex')), findsOneWidget);
    }
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('カードの覚えている技の札をタップすると、その技の詳細を開く', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final monster = sampleData.monsterById(monsterId: 'sample-mugmon');
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResultScreen(
          monster: monster,
          dexStore: DexStore(definitions: sampleData.definitions),
          origin: ResultScreenOrigin.dex,
          cardSharer: fakeCardSharer(
            calls: RecordedShareCalls(),
            artImage: null,
            shareResultStatus: ShareResultStatus.success,
          ),
        ),
      ),
    );
    final moveId = monster.definition.learnset.first.moveId;
    final moveChip = find.byKey(Key('move-chip-$moveId'));
    // scrollUntilVisible は行の端が一覧に入った所で止まり、行の中心が一覧の外 (下のボタンの領域) に残るため、
    // 行を一覧の上端まで送ってからタップする
    await tester.ensureVisible(moveChip);
    await tester.pumpAndSettle();

    await tester.tap(moveChip);
    await tester.pumpAndSettle();

    expect(find.byType(MoveDetailScreen), findsOneWidget);
    expect(
      tester.widget<MoveDetailScreen>(find.byType(MoveDetailScreen)).move.id,
      moveId,
    );
    expect(
      find.text(sampleData.definitions.moveById(moveId: moveId).displayName),
      findsOneWidget,
    );
  });
}
