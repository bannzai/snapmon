import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/move_selection/move_selection_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  testWidgets('持っている技をタップした順に枠の番号を付け、決定で選んだ順に保存して閉じる (#309)', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final savedSelections = <List<String>>[];
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..connectServer(
        savePartyMonsterIDs: ({required monsterIDs}) async {},
        saveSelectedMoveIDs: ({required monsterID, required moveIDs}) async =>
            savedSelections.add(moveIDs),
        refreshDefinitions: () async {},
      )
      ..applyServerSnapshot(
        monsters: sampleData.monsters,
        partyMonsterIDs: const [],
        definitions: null,
      );
    final monster = dexStore.monsters.first;
    final moveIDs = availableMoveIDs(
      learnset: monster.definition.learnset,
      actionCardMoveIDs: monster.actionCardMoveIDs,
      level: monster.level,
    );
    expect(moveIDs.length, greaterThanOrEqualTo(2));
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) =>
                    MoveSelectionScreen(monster: monster, dexStore: dexStore),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 開いた時は今の技の枠を選んでいる
    final equippedMoveIDs = equippedLearnsetEntries(
      learnset: monster.definition.learnset,
      actionCardMoveIDs: monster.actionCardMoveIDs,
      selectedMoveIDs: monster.selectedMoveIDs,
      level: monster.level,
    );
    for (final (slotIndex, moveID) in equippedMoveIDs.indexed) {
      expect(
        tester
            .widget<Text>(find.byKey(Key('move-selection-slot-$moveID')))
            .data,
        '${slotIndex + 1}',
      );
    }

    await tester.tap(find.byKey(const Key('move-selection-reset')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('move-selection-save')))
          .onPressed,
      isNull,
      reason: '1 つも選んでいない間は決定を押せない',
    );

    final secondMoveID = moveIDs[1];
    final firstMoveID = moveIDs[0];
    await tester.tap(find.byKey(Key('move-selection-$secondMoveID')));
    await tester.tap(find.byKey(Key('move-selection-$firstMoveID')));
    await tester.pump();
    expect(
      tester
          .widget<Text>(find.byKey(Key('move-selection-slot-$secondMoveID')))
          .data,
      '1',
    );
    expect(
      tester
          .widget<Text>(find.byKey(Key('move-selection-slot-$firstMoveID')))
          .data,
      '2',
    );

    await tester.tap(find.byKey(const Key('move-selection-save')));
    await tester.pumpAndSettle();
    expect(savedSelections, [
      [secondMoveID, firstMoveID],
    ]);
    expect(find.byType(MoveSelectionScreen), findsNothing);
    expect(
      dexStore.monsters
          .firstWhere(
            (dexMonster) => dexMonster.definition.id == monster.definition.id,
          )
          .selectedMoveIDs,
      [secondMoveID, firstMoveID],
    );
  });
}
