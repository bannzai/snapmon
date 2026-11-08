import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/move_expression.dart';
import 'package:snapmon/domain/battle/status_condition.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/domain/master/move.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';

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
      switch (move.category) {
        case MoveCategory.attack:
          expect(move.power, greaterThan(0), reason: move.id);
        case MoveCategory.support:
          expect(move.power, 0, reason: move.id);
          expect(move.specialEffect?.power, isNull, reason: move.id);
          // 補助技はステータスの変化・回復か、状態・解除・フィールドの効果を 1 つ以上持つ
          expect(
            [
              ...?move.specialEffect?.selfStatChanges.keys,
              ...?move.specialEffect?.opponentStatChanges.keys,
              if (move.specialEffect?.selfHitPointsRecovery != null)
                StatKind.hitPoints,
              if (!(move.specialEffect?.hasNoValueEffect ?? true)) 'value',
            ],
            isNotEmpty,
            reason: move.id,
          );
          expect(
            move.specialEffect?.selfDestructs ?? false,
            isFalse,
            reason: '${move.id}: 補助技は自爆しない',
          );
          expect(
            move.specialEffect?.isOneHitKnockout ?? false,
            isFalse,
            reason: '${move.id}: 補助技は一撃必殺にしない',
          );
      }
      expect(move.accuracy, inInclusiveRange(1, 100), reason: move.id);
      if (move.specialEffect?.isOneHitKnockout ?? false) {
        // 一撃必殺は 1 回しか使えず命中率が低い (#224)
        expect(move.powerPoints, 1, reason: move.id);
        expect(move.accuracy, lessThanOrEqualTo(30), reason: move.id);
      }
      expect(move.powerPoints, greaterThan(0), reason: move.id);
      expect(
        move.learnableLevelMinimum,
        lessThanOrEqualTo(move.learnableLevelMaximum),
        reason: move.id,
      );
    }
  });

  test('master と見本のモンスターの全ての特殊効果は、式が文法どおりで一覧の変数だけを使い、説明と規則を持つ', () {
    // 式を持たない形・変えられないステータスのキーは読む時に null や空になり見落とすため、元の JSON で確かめる
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
        final expressions = <Object?>[
          if (json.containsKey('power')) json['power'],
          if (json.containsKey('selfHitPointsRecovery'))
            json['selfHitPointsRecovery'],
          for (final key in ['selfStatChanges', 'opponentStatChanges'])
            if (json[key] case final Map<String, dynamic> statChanges) ...[
              for (final MapEntry(key: statName, value: expression)
                  in statChanges.entries) ...[
                expression,
                // 変えられないステータスのキーは読む時に捨てられ、効果が黙って消えるため
                if (!modifiableStatKinds.any(
                  (statKind) => statKind.name == statName,
                ))
                  'unknown stat: $statName',
              ],
            ],
        ];
        final statusConditionNames = {
          for (final kind in StatusConditionKind.values) kind.name,
        };
        final valueEffectKeys = [
          'selfStatusConditions',
          'opponentStatusConditions',
          'curesSelfStatusConditions',
          'fieldEffect',
          'selfDestructs',
          'oneHitKnockout',
          'sureHit',
        ];
        // 状態の名前の誤りは読む時に捨てられ、効果が黙って消えるため元の JSON で確かめる
        for (final key in [
          'selfStatusConditions',
          'opponentStatusConditions',
        ]) {
          if (json[key] case final List<dynamic> inflictions) {
            for (final infliction in inflictions) {
              expect(
                statusConditionNames,
                contains((infliction as Map<String, dynamic>)['kind']),
                reason: '$path: $json',
              );
              expect(
                infliction['chancePercent'],
                inInclusiveRange(1, 100),
                reason: '$path: $json',
              );
            }
          }
        }
        if (json['fieldEffect'] case final String fieldEffect) {
          expect(
            FieldEffectKind.values.map((kind) => kind.name),
            contains(fieldEffect),
            reason: '$path: $json',
          );
        }
        expect(
          [...expressions, ...valueEffectKeys.where(json.containsKey)],
          isNotEmpty,
          reason: '$path: $json',
        );
        for (final expression in expressions) {
          expect(expression, isA<String>(), reason: '$path: $json');
          expect(
            moveExpressionViolation(source: expression! as String),
            isNull,
            reason: '$path: $json',
          );
        }
        expect(json['summary'], isA<String>(), reason: '$path: $json');
        expect(json['rule'], isA<String>(), reason: '$path: $json');
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
        'effectId': 'machine_particle',
        'learnableLevelMinimum': 1,
        'learnableLevelMaximum': 30,
        'rationale': 'ゴムの玉をはじく技',
        'specialEffect': {
          'power': 'if(not movesFirst, 140, 100)',
          'summary': '後に動くと強い',
          'rule': '後に行動すると威力が上がる',
          'rationale': 'ゴムは引き絞ってから放つため',
        },
      },
    );
    expect(move.power, 40);
    expect(move.specialEffect?.power, 'if(not movesFirst, 140, 100)');
    expect(move.specialEffect?.summary, '後に動くと強い');
    expect(move.specialEffect?.rule, '後に行動すると威力が上がる');
  });

  test('全属性が補助技 (相手の防御・自分の攻撃・相手の素早さ・回復のどれか) を持つ (#181 の完了条件)', () {
    for (final elementType in master.elementTypes) {
      expect(
        master.moves.where(
          (move) =>
              move.elementTypeId == elementType.id &&
              move.category == MoveCategory.support,
        ),
        isNotEmpty,
        reason: elementType.id,
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
          'custom_rubber': {'thunder': 2},
          'fire': {'custom_rubber': 2},
        },
        'moves': [
          {
            'id': 'custom_rubber_1',
            'displayName': 'ゴムだまはじき',
            'elementTypeId': 'custom_rubber',
            'power': 40,
            'powerPoints': 30,
            'category': 'attack',
            'effectId': 'machine_particle',
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
        defenderElementTypeId: 'steel',
      ),
      1,
    );
    expect(
      merged.typeMultiplier(
        attackerElementTypeId: 'fire',
        defenderElementTypeId: 'custom_rubber',
      ),
      1,
    );
  });
}
