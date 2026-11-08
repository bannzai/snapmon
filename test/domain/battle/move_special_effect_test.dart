import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/battle/move_special_effect.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/domain/master/move.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/domain/monster/monster_state.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';

/// 威力の倍率の式 [power] の特殊効果を持つ、PP [powerPoints] のテスト用の技を返す。[power] が null なら特殊効果を持たない。
Move testMove({required String? power, int powerPoints = 10}) => Move(
  id: 'test_move',
  displayName: 'テストのわざ',
  elementTypeId: 'fire',
  power: 40,
  powerPoints: powerPoints,
  category: MoveCategory.attack,
  effectId: 'none',
  learnableLevelMinimum: 1,
  learnableLevelMaximum: 999,
  specialEffect: power == null
      ? null
      : MoveSpecialEffect(
          power: power,
          selfStatChanges: const {},
          opponentStatChanges: const {},
          selfHitPointsRecovery: null,
          summary: 'テストの効果',
          rule: 'テストの規則',
        ),
);

/// 属性 [elementTypeIds]・HP [currentHitPoints]・技 [moveId] の残り PP [remainingPowerPoints] のバトル中のモンスターを返す。
BattleMonster testMonster({
  List<String> elementTypeIds = const ['fire'],
  int currentHitPoints = 100,
  String moveId = 'test_move',
  int remainingPowerPoints = 10,
}) => BattleMonster(
  definition: MonsterDefinition(
    id: 'monster',
    sourcePhotoReference: null,
    name: 'モンスター',
    encyclopediaText: '',
    elementTypeIds: elementTypeIds,
    learnset: [LearnsetEntry(moveId: moveId, unlockLevel: 1)],
    baseStats: const MonsterStats(
      hitPoints: 80,
      attack: 80,
      defense: 80,
      speed: 80,
    ),
    individualValues: const MonsterStats(
      hitPoints: 0,
      attack: 0,
      defense: 0,
      speed: 0,
    ),
    statCalculationVersion: 1,
    masterVersion: 1,
  ),
  state: MonsterState(
    level: 50,
    experience: 0,
    currentHitPoints: currentHitPoints,
    remainingPowerPoints: {moveId: remainingPowerPoints},
    statModifierPercents: const {},
    statusConditions: const {},
  ),
);

/// HP [hitPoints]・攻撃と防御が [attack]・[defense] のステータスを返す。
MonsterStats testStats({
  int hitPoints = 100,
  int attack = 50,
  int defense = 50,
}) => MonsterStats(
  hitPoints: hitPoints,
  attack: attack,
  defense: defense,
  speed: 50,
);

/// 既定の状況 (両者の HP 満タン・同じ属性・技の PP 満タン・先に行動) を引数で変えた、[move] を使う時点の式の変数を返す。
Map<String, int> testVariables({
  required Move move,
  BattleMonster? attacker,
  BattleMonster? defender,
  MonsterStats? attackerStats,
  MonsterStats? defenderStats,
  bool attackerMovesFirst = true,
  DateTime? battleDate,
}) => moveExpressionVariables(
  move: move,
  attacker: attacker ?? testMonster(),
  defender: defender ?? testMonster(),
  attackerStats: attackerStats ?? testStats(),
  defenderStats: defenderStats ?? testStats(),
  attackerMovesFirst: attackerMovesFirst,
  battleDate: battleDate ?? DateTime.utc(2026, 10, 28),
);

/// 既定の状況を引数で変えて、[move] の威力の倍率の効果を計算する。
({int powerPercent, String description})? calculate({
  required Move move,
  BattleMonster? attacker,
  BattleMonster? defender,
  MonsterStats? attackerStats,
  MonsterStats? defenderStats,
  bool attackerMovesFirst = true,
  DateTime? battleDate,
}) => calculateMoveSpecialEffect(
  move: move,
  variables: testVariables(
    move: move,
    attacker: attacker,
    defender: defender,
    attackerStats: attackerStats,
    defenderStats: defenderStats,
    attackerMovesFirst: attackerMovesFirst,
    battleDate: battleDate,
  ),
);

/// 版 4 までの 8 種類の特殊効果 (技の識別子と、種類・倍率の最大 %)。版 5 で式に書き直した効果と、版 6 で足した技の効果
/// (同じ 8 種類の式を使う) が、版 4 のアプリと同じ倍率を返すことを確かめる。版 5 から残した技は版 4 の同じ技の種類、
/// 版 6 で足した技はその技の式に当たる種類を書いた。
const _version4SpecialEffects = {
  'fire_1b': (kind: 'movesFirst', maximumPowerPercent: 130),
  'fire_1c': (kind: 'opponentHitPointsLow', maximumPowerPercent: 200),
  'water_1b': (kind: 'sameElementAsOpponent', maximumPowerPercent: 150),
  'water_1c': (kind: 'movesFirst', maximumPowerPercent: 130),
  'grass_1b': (kind: 'differentElementFromOpponent', maximumPowerPercent: 120),
  'grass_1c': (kind: 'tougherOpponent', maximumPowerPercent: 150),
  'thunder_1b': (kind: 'movesFirst', maximumPowerPercent: 130),
  'thunder_1c': (
    kind: 'differentElementFromOpponent',
    maximumPowerPercent: 120,
  ),
  'earth_1b': (kind: 'movesLast', maximumPowerPercent: 140),
  'earth_1c': (kind: 'tougherOpponent', maximumPowerPercent: 150),
  'steel_1b': (kind: 'tougherOpponent', maximumPowerPercent: 150),
  'steel_1c': (kind: 'movesLast', maximumPowerPercent: 140),
  'wood_1b': (kind: 'opponentHitPointsLow', maximumPowerPercent: 200),
  'wood_1c': (kind: 'ownHitPointsLow', maximumPowerPercent: 200),
  'light_1b': (kind: 'movesFirst', maximumPowerPercent: 130),
  'light_1c': (kind: 'powerPointsLow', maximumPowerPercent: 200),
  'dark_1b': (kind: 'movesFirst', maximumPowerPercent: 130),
  'dark_1c': (kind: 'ownHitPointsLow', maximumPowerPercent: 200),
  'poison_1b': (kind: 'differentElementFromOpponent', maximumPowerPercent: 120),
  'poison_1c': (kind: 'opponentHitPointsLow', maximumPowerPercent: 200),
  'sound_1b': (kind: 'movesFirst', maximumPowerPercent: 130),
  'sound_1c': (kind: 'powerPointsLow', maximumPowerPercent: 200),
  'beast_1b': (kind: 'movesLast', maximumPowerPercent: 140),
  'beast_1c': (kind: 'tougherOpponent', maximumPowerPercent: 150),
  'bug_1b': (kind: 'movesLast', maximumPowerPercent: 140),
  'bug_1c': (kind: 'sameElementAsOpponent', maximumPowerPercent: 150),
  'bird_1b': (kind: 'movesFirst', maximumPowerPercent: 130),
  'bird_1c': (kind: 'tougherOpponent', maximumPowerPercent: 150),
  'fish_1b': (kind: 'movesFirst', maximumPowerPercent: 130),
  'fish_1c': (kind: 'tougherOpponent', maximumPowerPercent: 150),
  'ice_1b': (kind: 'opponentHitPointsLow', maximumPowerPercent: 200),
  'ice_1c': (kind: 'tougherOpponent', maximumPowerPercent: 150),
  'wind_1b': (kind: 'movesFirst', maximumPowerPercent: 130),
  'wind_1c': (kind: 'powerPointsLow', maximumPowerPercent: 200),
  'flower_1b': (kind: 'differentElementFromOpponent', maximumPowerPercent: 120),
  'flower_1c': (kind: 'tougherOpponent', maximumPowerPercent: 150),
  'machine_1b': (kind: 'powerPointsLow', maximumPowerPercent: 200),
  'machine_1c': (kind: 'movesFirst', maximumPowerPercent: 130),
  'sweets_1b': (kind: 'sameElementAsOpponent', maximumPowerPercent: 150),
  'sweets_1c': (kind: 'ownHitPointsLow', maximumPowerPercent: 200),
  'ghost_1b': (kind: 'movesLast', maximumPowerPercent: 140),
  'ghost_1c': (kind: 'ownHitPointsLow', maximumPowerPercent: 200),
  'dragon_1b': (kind: 'tougherOpponent', maximumPowerPercent: 150),
  'dragon_1c': (kind: 'opponentHitPointsLow', maximumPowerPercent: 200),
  'paper_1b': (kind: 'powerPointsLow', maximumPowerPercent: 200),
  'paper_1c': (kind: 'sameElementAsOpponent', maximumPowerPercent: 150),
};

/// 版 4 のアプリ (`calculateMoveSpecialEffect` の種類ごとの計算) が返した倍率 (%)。版 4 の実装から写した。
int _version4PowerPercent({
  required String kind,
  required int maximumPowerPercent,
  required int attackerHitPoints,
  required int attackerMaximumHitPoints,
  required int defenderHitPoints,
  required int defenderMaximumHitPoints,
  required int attackerAttack,
  required int defenderDefense,
  required int remainingPowerPoints,
  required int maximumPowerPoints,
  required bool sharesElementType,
  required bool attackerMovesFirst,
}) {
  int percentByRatio({required int numerator, required int denominator}) =>
      denominator <= 0
      ? 100
      : 100 + (maximumPowerPercent - 100) * numerator ~/ denominator;
  int percentByCondition({required bool condition}) =>
      condition ? maximumPowerPercent : 100;
  return switch (kind) {
    'opponentHitPointsLow' => percentByRatio(
      numerator: defenderMaximumHitPoints - defenderHitPoints,
      denominator: defenderMaximumHitPoints,
    ),
    'ownHitPointsLow' => percentByRatio(
      numerator: attackerMaximumHitPoints - attackerHitPoints,
      denominator: attackerMaximumHitPoints,
    ),
    'tougherOpponent' => percentByCondition(
      condition: defenderDefense > attackerAttack,
    ),
    'powerPointsLow' => percentByRatio(
      numerator: maximumPowerPoints - remainingPowerPoints,
      denominator: maximumPowerPoints - 1,
    ),
    'sameElementAsOpponent' => percentByCondition(condition: sharesElementType),
    'differentElementFromOpponent' => percentByCondition(
      condition: !sharesElementType,
    ),
    'movesFirst' => percentByCondition(condition: attackerMovesFirst),
    _ => percentByCondition(condition: !attackerMovesFirst),
  };
}

void main() {
  test('特殊効果の無い技は null を返す', () {
    expect(calculate(move: testMove(power: null)), isNull);
  });

  test('式の値を倍率にし、説明は効果の規則と今回の倍率', () {
    final result = calculate(
      move: testMove(
        power:
            '100 + 100 * (opponent.maximumHitPoints - opponent.hitPoints) / opponent.maximumHitPoints',
      ),
      defender: testMonster(currentHitPoints: 50),
    )!;
    expect(result.powerPercent, 150);
    expect(result.description, 'テストの規則 (今回は 1.5 倍)');
  });

  test('変数は技を使う側・相手・技・行動順・属性の共有・対戦日の値', () {
    int evaluate({required String power}) => calculate(
      move: testMove(power: power),
      attacker: testMonster(currentHitPoints: 30, remainingPowerPoints: 4),
      defender: testMonster(currentHitPoints: 70, elementTypeIds: ['water']),
      attackerStats: testStats(hitPoints: 90, attack: 61, defense: 62),
      defenderStats: testStats(hitPoints: 110, attack: 71, defense: 72),
      attackerMovesFirst: false,
      battleDate: DateTime(2026, 12, 24),
    )!.powerPercent;

    expect(evaluate(power: 'self.hitPoints'), 30);
    expect(evaluate(power: 'self.maximumHitPoints'), 90);
    expect(evaluate(power: 'self.attack'), 61);
    expect(evaluate(power: 'self.defense'), 62);
    expect(evaluate(power: 'self.speed'), 50);
    expect(evaluate(power: 'self.level'), 50);
    expect(evaluate(power: 'opponent.hitPoints'), 70);
    expect(evaluate(power: 'opponent.maximumHitPoints'), 110);
    expect(evaluate(power: 'opponent.attack'), 71);
    expect(evaluate(power: 'opponent.defense'), 72);
    expect(evaluate(power: 'opponent.speed'), 50);
    expect(evaluate(power: 'opponent.level'), 50);
    expect(evaluate(power: 'move.power'), 40);
    expect(evaluate(power: 'move.remainingPowerPoints'), 4);
    expect(evaluate(power: 'move.maximumPowerPoints'), 10);
    expect(evaluate(power: 'movesFirst'), 0);
    expect(evaluate(power: 'sharesElementType'), 0);
    expect(evaluate(power: 'battleDate.year'), 2026);
    expect(evaluate(power: 'battleDate.month'), 12);
    expect(evaluate(power: 'battleDate.day'), 24);
  });

  test('評価できない式 (未知の変数・文法の誤り・0 での割り算) と負の値は倍率 100 にする', () {
    for (final power in [
      'if(opponent.armor > 0, 150, 100)',
      'if(1, 150',
      '100 / (move.maximumPowerPoints - move.maximumPowerPoints)',
      '-50',
    ]) {
      final result = calculate(move: testMove(power: power))!;
      expect(result.powerPercent, 100, reason: power);
      expect(result.description, 'テストの規則 (今回は 1 倍)', reason: power);
    }
    expect(calculate(move: testMove(power: '0'))!.powerPercent, 0);
  });

  test('master の特殊効果の式は、版 4 までの同じ種類の効果と同じ倍率を返す', () {
    final master = MasterData.fromJson(
      json:
          jsonDecode(File('assets/master/master.json').readAsStringSync())
              as Map<String, dynamic>,
    );
    final movesWithSpecialEffect = master.moves.where(
      (move) => _version4SpecialEffects.containsKey(move.id),
    );
    expect(
      movesWithSpecialEffect.map((move) => move.id).toSet(),
      _version4SpecialEffects.keys.toSet(),
    );
    var comparedCount = 0;
    for (final move in movesWithSpecialEffect) {
      final version4 = _version4SpecialEffects[move.id]!;
      for (final (attackerHitPoints, defenderHitPoints) in [
        (100, 100),
        (50, 37),
        (1, 1),
        (0, 0),
      ]) {
        for (
          var remainingPowerPoints = move.powerPoints;
          remainingPowerPoints >= 1;
          remainingPowerPoints--
        ) {
          for (final (attack, defense) in [(80, 60), (60, 80), (70, 70)]) {
            for (final attackerMovesFirst in [true, false]) {
              for (final defenderElementTypeIds in [
                ['fire'],
                ['water'],
              ]) {
                final actual = calculate(
                  move: move,
                  attacker: testMonster(
                    currentHitPoints: attackerHitPoints,
                    moveId: move.id,
                    remainingPowerPoints: remainingPowerPoints,
                  ),
                  defender: testMonster(
                    currentHitPoints: defenderHitPoints,
                    elementTypeIds: defenderElementTypeIds,
                  ),
                  attackerStats: testStats(attack: attack),
                  defenderStats: testStats(defense: defense),
                  attackerMovesFirst: attackerMovesFirst,
                  battleDate: DateTime.utc(2026, 11, 6),
                )!.powerPercent;
                final expected = _version4PowerPercent(
                  kind: version4.kind,
                  maximumPowerPercent: version4.maximumPowerPercent,
                  attackerHitPoints: attackerHitPoints,
                  attackerMaximumHitPoints: 100,
                  defenderHitPoints: defenderHitPoints,
                  defenderMaximumHitPoints: 100,
                  attackerAttack: attack,
                  defenderDefense: defense,
                  remainingPowerPoints: remainingPowerPoints,
                  maximumPowerPoints: move.powerPoints,
                  sharesElementType: defenderElementTypeIds.contains('fire'),
                  attackerMovesFirst: attackerMovesFirst,
                );
                expect(
                  actual,
                  expected,
                  reason:
                      '${move.id} HP $attackerHitPoints/$defenderHitPoints PP $remainingPowerPoints 攻撃 $attack 防御 $defense 先 $attackerMovesFirst 相手 $defenderElementTypeIds',
                );
                comparedCount++;
              }
            }
          }
        }
      }
    }
    expect(comparedCount, greaterThan(0));
  });

  test('倍率を倍の数の文字列にする', () {
    expect(formatPowerPercent(powerPercent: 100), '1');
    expect(formatPowerPercent(powerPercent: 150), '1.5');
    expect(formatPowerPercent(powerPercent: 125), '1.25');
    expect(formatPowerPercent(powerPercent: 105), '1.05');
    expect(formatPowerPercent(powerPercent: 200), '2');
  });

  test('JSON から特殊効果を読み、式を持たない形 (版 4 までの kind の形) と null は null にする', () {
    final specialEffect = moveSpecialEffectFromJson(
      json: {
        'power': 'if(movesFirst, 130, 100)',
        'summary': '先に動くと強い',
        'rule': '先に行動すると威力が上がる',
        'rationale': '根拠',
      },
    )!;
    expect(specialEffect.power, 'if(movesFirst, 130, 100)');
    expect(specialEffect.summary, '先に動くと強い');
    expect(specialEffect.rule, '先に行動すると威力が上がる');
    expect(
      moveSpecialEffectFromJson(
        json: {'kind': 'movesFirst', 'maximumPowerPercent': 130},
      ),
      isNull,
    );
    expect(moveSpecialEffectFromJson(json: null), isNull);
  });

  test('JSON から補助技の効果を読み、変えられないステータス (HP) のキーと式でない値は読まない', () {
    final specialEffect = moveSpecialEffectFromJson(
      json: {
        'selfStatChanges': {'attack': '25', 'hitPoints': '25'},
        'opponentStatChanges': {'defense': '-25', 'speed': 25},
        'selfHitPointsRecovery': 'self.maximumHitPoints / 4',
        'summary': '攻撃を上げる',
        'rule': '自分の攻撃と相手の防御を変える',
      },
    )!;
    expect(specialEffect.power, isNull);
    expect(specialEffect.selfStatChanges, {StatKind.attack: '25'});
    expect(specialEffect.opponentStatChanges, {StatKind.defense: '-25'});
    expect(specialEffect.selfHitPointsRecovery, 'self.maximumHitPoints / 4');
    expect(
      moveSpecialEffectFromJson(
        json: {
          'selfStatChanges': {'hitPoints': '25'},
          'summary': '何もしない',
          'rule': '何もしない',
        },
      ),
      isNull,
    );
  });

  test('補助技の効果の式を評価し、評価できない式と負の回復は 0 にする', () {
    Move supportMove({
      Map<StatKind, String> selfStatChanges = const {},
      Map<StatKind, String> opponentStatChanges = const {},
      String? selfHitPointsRecovery,
    }) => Move(
      id: 'test_move',
      displayName: 'テストのわざ',
      elementTypeId: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: selfStatChanges,
        opponentStatChanges: opponentStatChanges,
        selfHitPointsRecovery: selfHitPointsRecovery,
        summary: 'テストの効果',
        rule: 'テストの規則',
      ),
    );
    final move = supportMove(
      selfStatChanges: {StatKind.attack: 'if(movesFirst, 50, 25)'},
      opponentStatChanges: {
        StatKind.defense: '-25',
        StatKind.speed: 'opponent.armor',
      },
      selfHitPointsRecovery: 'self.maximumHitPoints / 4',
    );
    final result = calculateMoveStatusEffect(
      move: move,
      variables: testVariables(
        move: move,
        attackerStats: testStats(hitPoints: 120),
      ),
    );
    expect(result.selfStatChanges, {StatKind.attack: 50});
    expect(result.opponentStatChanges, {
      StatKind.defense: -25,
      StatKind.speed: 0,
    });
    expect(result.hitPointsRecovery, 30);
    // 攻撃技 (威力の倍率だけを持つ) は変化も回復も無い
    final attackMove = testMove(power: '150');
    final attackResult = calculateMoveStatusEffect(
      move: attackMove,
      variables: testVariables(move: attackMove),
    );
    expect(attackResult.selfStatChanges, isEmpty);
    expect(attackResult.opponentStatChanges, isEmpty);
    expect(attackResult.hitPointsRecovery, 0);
    final negativeRecovery = supportMove(selfHitPointsRecovery: '-10');
    expect(
      calculateMoveStatusEffect(
        move: negativeRecovery,
        variables: testVariables(move: negativeRecovery),
      ).hitPointsRecovery,
      0,
    );
    // 補助技は威力の倍率を持たない
    expect(calculate(move: move), isNull);
  });
}
