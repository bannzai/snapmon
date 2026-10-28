import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/domain/master/move.dart';

void main() {
  final master = MasterData.fromJson(
    json:
        jsonDecode(File('assets/master/master.json').readAsStringSync())
            as Map<String, dynamic>,
  );

  test('master は版を持つ', () {
    expect(master.version, greaterThanOrEqualTo(1));
  });

  test('相性表は属性数 × 属性数のすべての組に 0.5 / 1 / 2 の倍率を持つ', () {
    final elementTypeIds = master.elementTypes.map(
      (elementType) => elementType.id,
    );
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

  test('技の特殊効果はアプリが知っている種類で、威力を上げる倍率を持つ', () {
    // 知らない種類は読む時に null になり見落とすため、元の JSON の種類の名前で確かめる
    for (final moveJson
        in (jsonDecode(File('assets/master/master.json').readAsStringSync())
                as Map<String, dynamic>)['moves']
            as List<dynamic>) {
      final specialEffectJson =
          (moveJson as Map<String, dynamic>)['specialEffect']
              as Map<String, dynamic>?;
      if (specialEffectJson == null) {
        continue;
      }
      expect(
        MoveSpecialEffectKind.values.asNameMap().keys,
        contains(specialEffectJson['kind']),
        reason: moveJson['id'] as String,
      );
      expect(
        specialEffectJson['maximumPowerPercent'] as int,
        greaterThan(100),
        reason: moveJson['id'] as String,
      );
    }
  });

  test('Lv.1 で覚えられる技の半分以上に特殊効果が付いている (#65 の完了条件)', () {
    final levelOneMoves = master.moves.where(
      (move) => move.learnableLevelMinimum == 1,
    );
    expect(
      levelOneMoves.where((move) => move.specialEffect != null).length * 2,
      greaterThanOrEqualTo(levelOneMoves.length),
    );
  });

  test('その場で作った定義を同じ形の JSON から読み、master に足すと相性は既存の全属性と等倍になる', () {
    final customDefinitions = MasterData.fromJson(
      json: {
        'version': 1,
        'elementTypes': [
          {'id': 'custom_rubber', 'displayName': 'ゴム'},
        ],
        // その場で作った定義が相性を持っていても取り込まれず、等倍に固定されることを確かめる
        'typeChart': {
          'custom_rubber': {'electric': 2},
          'heat': {'custom_rubber': 2},
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
}
