import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/master/load_master_data.dart';

void main() {
  final master = MasterData.fromJson(
    json:
        jsonDecode(File(masterDataAssetPath).readAsStringSync())
            as Map<String, dynamic>,
  );

  test('master は版を持つ', () {
    expect(master.version, greaterThanOrEqualTo(1));
  });

  test('相性表は属性数 × 属性数のすべての組に 0.5 / 1 / 2 の倍率を持つ', () {
    final elementTypeIds = master.elementTypes.map((elementType) => elementType.id);
    expect(master.typeChart.keys.toSet(), elementTypeIds.toSet());
    for (final attackerElementTypeId in elementTypeIds) {
      final row = master.typeChart[attackerElementTypeId]!;
      expect(
        row.keys.toSet(),
        elementTypeIds.toSet(),
        reason: '$attackerElementTypeId の行に抜けか余分な列がある',
      );
      for (final multiplier in row.values) {
        expect([0.5, 1.0, 2.0], contains(multiplier));
      }
    }
  });

  test('属性・技・エフェクト・段階の ID は重複しない', () {
    for (final ids in [
      master.elementTypes.map((elementType) => elementType.id),
      master.moves.map((move) => move.id),
      master.effects.map((effect) => effect.id),
      master.statGrades.map((statGrade) => statGrade.id),
    ]) {
      expect(ids.toSet().length, ids.length);
    }
  });

  test('技は master にある属性とエフェクトを参照し、値域に収まる', () {
    final elementTypeIds = {
      for (final elementType in master.elementTypes) elementType.id,
    };
    final effectIds = {for (final effect in master.effects) effect.id};
    for (final move in master.moves) {
      expect(elementTypeIds, contains(move.elementTypeId), reason: move.id);
      expect(effectIds, contains(move.effectId), reason: move.id);
      expect(move.power, greaterThan(0), reason: move.id);
      expect(move.powerPoints, greaterThan(0), reason: move.id);
      expect(
        move.learnableLevelMinimum,
        lessThanOrEqualTo(move.learnableLevelMaximum),
        reason: move.id,
      );
    }
  });

  test('その場で作った定義を同じ形の JSON から読み、master に足すと相性は既存の全属性と等倍になる', () {
    final customDefinitions = MasterData.fromJson(
      json: {
        'version': 1,
        'elementTypes': [
          {'id': 'custom_rubber', 'displayName': 'ゴム'},
        ],
        'typeChart': {
          'custom_rubber': {'electric': 2},
        },
        'moves': [
          {
            'id': 'custom_rubber_1',
            'displayName': 'ゴムだまはじき',
            'elementTypeId': 'custom_rubber',
            'power': 40,
            'powerPoints': 30,
            'category': 'attack',
            'effectId': 'plastic_particle',
            'learnableLevelMinimum': 1,
            'learnableLevelMaximum': 30,
          },
        ],
      },
    );
    final merged = mergeMasterData(base: master, additional: customDefinitions);

    expect(merged.version, master.version);
    expect(merged.moveById(moveId: 'custom_rubber_1').power, 40);
    expect(
      merged.typeMultiplier(
        attackerElementTypeId: 'custom_rubber',
        defenderElementTypeId: 'electric',
      ),
      2,
    );
    expect(
      merged.typeMultiplier(
        attackerElementTypeId: 'custom_rubber',
        defenderElementTypeId: 'metal',
      ),
      1,
    );
    expect(
      merged.typeMultiplier(
        attackerElementTypeId: 'heat',
        defenderElementTypeId: 'custom_rubber',
      ),
      1,
    );
  });

  test('同梱の asset から master を読める', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final loaded = await loadMasterData(assetBundle: rootBundle);
    expect(loaded.version, master.version);
    expect(loaded.moves.length, master.moves.length);
  });
}
