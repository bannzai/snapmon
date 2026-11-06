import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/move_expression.dart';
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

  test('master と見本のモンスターの全ての特殊効果は、式が文法どおりで一覧の変数だけを使い、説明を持つ', () {
    // 式 (power) を持たない形は読む時に null になり見落とすため、元の JSON で確かめる
    for (final path in [
      'assets/master/master.json',
      'assets/samples/sample_monsters.json',
    ]) {
      final specialEffectJsons = <Map<String, dynamic>>[];
      void collect(Object? node) {
        if (node is Map<String, dynamic>) {
          if (node['specialEffect'] case final Map<String, dynamic> json) {
            specialEffectJsons.add(json);
          }
          node.values.forEach(collect);
        } else if (node is List<dynamic>) {
          node.forEach(collect);
        }
      }

      collect(jsonDecode(File(path).readAsStringSync()));
      expect(specialEffectJsons, isNotEmpty, reason: path);
      for (final json in specialEffectJsons) {
        expect(json['power'], isA<String>(), reason: '$path: $json');
        expect(
          moveExpressionViolation(source: json['power'] as String),
          isNull,
          reason: '$path: $json',
        );
        expect(json['summary'], isA<String>(), reason: '$path: $json');
        expect(json.containsKey('kind'), isFalse, reason: '$path: $json');
      }
    }
  });

  test('全ての技と特殊効果に根拠 (rationale) が書いてある (#124 の完了条件)', () {
    // 根拠はアプリが読まない値のため、元の JSON で確かめる
    for (final moveJson
        in (jsonDecode(File('assets/master/master.json').readAsStringSync())
                as Map<String, dynamic>)['moves']
            as List<dynamic>) {
      final move = moveJson as Map<String, dynamic>;
      expect(move['rationale'], isA<String>(), reason: move['id'] as String);
      expect(
        move['rationale'] as String,
        isNotEmpty,
        reason: move['id'] as String,
      );
      final specialEffectJson = move['specialEffect'] as Map<String, dynamic>?;
      if (specialEffectJson != null) {
        expect(
          specialEffectJson['rationale'],
          isA<String>(),
          reason: move['id'] as String,
        );
        expect(
          specialEffectJson['rationale'] as String,
          isNotEmpty,
          reason: move['id'] as String,
        );
      }
    }
  });

  test('根拠 (rationale) を持つ技の JSON も読め、根拠は技と特殊効果の値に入らない', () {
    final move = Move.fromJson(
      json: {
        'id': 'custom_rubber_1',
        'displayName': 'ゴムだまはじき',
        'elementTypeId': 'custom_rubber',
        'power': 40,
        'powerPoints': 30,
        'category': 'attack',
        'effectId': 'plastic_particle',
        'learnableLevelMinimum': 1,
        'learnableLevelMaximum': 30,
        'rationale': 'ゴムの玉をはじく技',
        'specialEffect': {
          'power': 'if(not movesFirst, 140, 100)',
          'summary': '後に動くと強い',
          'rationale': 'ゴムは引き絞ってから放つため',
        },
      },
    );
    expect(move.power, 40);
    expect(move.specialEffect?.power, 'if(not movesFirst, 140, 100)');
    expect(move.specialEffect?.summary, '後に動くと強い');
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
