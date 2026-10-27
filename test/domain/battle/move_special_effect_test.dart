import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/battle/move_special_effect.dart';
import 'package:snapmon/domain/master/move.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/domain/monster/monster_state.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';

/// [kind] の特殊効果 (最大 [maximumPowerPercent]%) を持つ、PP 10 のテスト用の技を返す。
Move testMove({
  required MoveSpecialEffectKind? kind,
  int maximumPowerPercent = 200,
}) => Move(
  id: 'test_move',
  displayName: 'テストのわざ',
  elementTypeId: 'fire',
  power: 40,
  powerPoints: 10,
  category: MoveCategory.attack,
  effectId: 'none',
  learnableLevelMinimum: 1,
  learnableLevelMaximum: 999,
  specialEffect: kind == null
      ? null
      : MoveSpecialEffect(
          kind: kind,
          maximumPowerPercent: maximumPowerPercent,
        ),
);

/// 属性 [elementTypeIds]・HP [currentHitPoints]・テストの技の残り PP [remainingPowerPoints] のバトル中のモンスターを返す。
BattleMonster testMonster({
  List<String> elementTypeIds = const ['fire'],
  int currentHitPoints = 100,
  int remainingPowerPoints = 10,
}) => BattleMonster(
  definition: MonsterDefinition(
    id: 'monster',
    sourcePhotoReference: null,
    name: 'モンスター',
    encyclopediaText: '',
    elementTypeIds: elementTypeIds,
    learnset: const [LearnsetEntry(moveId: 'test_move', unlockLevel: 1)],
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
    remainingPowerPoints: {'test_move': remainingPowerPoints},
  ),
);

/// HP 100・攻撃と防御が [attack]・[defense] のステータスを返す。
MonsterStats testStats({int attack = 50, int defense = 50}) => MonsterStats(
  hitPoints: 100,
  attack: attack,
  defense: defense,
  speed: 50,
);

/// 既定の状況 (両者の HP 満タン・同じ属性・技の PP 満タン・先に行動) を引数で変えて、[move] の効果を計算する。
({int powerPercent, String description})? calculate({
  required Move move,
  BattleMonster? attacker,
  BattleMonster? defender,
  MonsterStats? attackerStats,
  MonsterStats? defenderStats,
  bool attackerMovesFirst = true,
}) => calculateMoveSpecialEffect(
  move: move,
  attacker: attacker ?? testMonster(),
  defender: defender ?? testMonster(),
  attackerStats: attackerStats ?? testStats(),
  defenderStats: defenderStats ?? testStats(),
  attackerMovesFirst: attackerMovesFirst,
  battleDate: DateTime.utc(2026, 10, 28),
);

void main() {
  test('特殊効果の無い技は null を返す', () {
    expect(calculate(move: testMove(kind: null)), isNull);
  });

  test('相手の HP が減っているほど: 満タンで 1 倍、半分で中間、残り 1 でほぼ最大', () {
    final move = testMove(kind: MoveSpecialEffectKind.opponentHitPointsLow);
    expect(calculate(move: move)!.powerPercent, 100);
    final halfHitPoints = calculate(
      move: move,
      defender: testMonster(currentHitPoints: 50),
    )!;
    expect(halfHitPoints.powerPercent, 150);
    expect(
      halfHitPoints.description,
      '相手の HP が減っているほど威力が上がる (今回は 1.5 倍)',
    );
    expect(
      calculate(
        move: move,
        defender: testMonster(currentHitPoints: 1),
      )!.powerPercent,
      199,
    );
  });

  test('自分の HP が減っているほど: 自分の HP の割合で決まり、相手の HP は効かない', () {
    final move = testMove(kind: MoveSpecialEffectKind.ownHitPointsLow);
    expect(
      calculate(
        move: move,
        defender: testMonster(currentHitPoints: 10),
      )!.powerPercent,
      100,
    );
    expect(
      calculate(
        move: move,
        attacker: testMonster(currentHitPoints: 25),
      )!.powerPercent,
      175,
    );
  });

  test('硬い相手に: 相手の防御が自分の攻撃より高い時だけ最大、同じなら 1 倍', () {
    final move = testMove(
      kind: MoveSpecialEffectKind.tougherOpponent,
      maximumPowerPercent: 150,
    );
    expect(
      calculate(
        move: move,
        attackerStats: testStats(attack: 50),
        defenderStats: testStats(defense: 51),
      )!.powerPercent,
      150,
    );
    expect(
      calculate(
        move: move,
        attackerStats: testStats(attack: 50),
        defenderStats: testStats(defense: 50),
      )!.powerPercent,
      100,
    );
  });

  test('残り PP が少ないほど: 最初の 1 回は 1 倍、最後の 1 回 (使う前の残り 1) で最大', () {
    final move = testMove(kind: MoveSpecialEffectKind.powerPointsLow);
    expect(calculate(move: move)!.powerPercent, 100);
    expect(
      calculate(
        move: move,
        attacker: testMonster(remainingPowerPoints: 1),
      )!.powerPercent,
      200,
    );
    // PP 10 の技で残り 4: 使った回数 6 / (10 - 1) で 166%
    expect(
      calculate(
        move: move,
        attacker: testMonster(remainingPowerPoints: 4),
      )!.powerPercent,
      166,
    );
  });

  test('同じ属性の相手に: 属性を 1 つでも共有すれば最大、共有しなければ 1 倍', () {
    final move = testMove(
      kind: MoveSpecialEffectKind.sameElementAsOpponent,
      maximumPowerPercent: 150,
    );
    expect(
      calculate(
        move: move,
        attacker: testMonster(elementTypeIds: ['fire', 'water']),
        defender: testMonster(elementTypeIds: ['grass', 'water']),
      )!.powerPercent,
      150,
    );
    expect(
      calculate(
        move: move,
        defender: testMonster(elementTypeIds: ['grass']),
      )!.powerPercent,
      100,
    );
  });

  test('違う属性の相手に: 属性を 1 つも共有しなければ最大、共有すれば 1 倍', () {
    final move = testMove(
      kind: MoveSpecialEffectKind.differentElementFromOpponent,
      maximumPowerPercent: 120,
    );
    expect(
      calculate(
        move: move,
        defender: testMonster(elementTypeIds: ['grass']),
      )!.powerPercent,
      120,
    );
    expect(calculate(move: move)!.powerPercent, 100);
  });

  test('先に動くと: 先に行動した時だけ最大', () {
    final move = testMove(
      kind: MoveSpecialEffectKind.movesFirst,
      maximumPowerPercent: 130,
    );
    expect(calculate(move: move)!.powerPercent, 130);
    expect(
      calculate(move: move, attackerMovesFirst: false)!.powerPercent,
      100,
    );
  });

  test('後に動くと: 後に行動した時だけ最大', () {
    final move = testMove(
      kind: MoveSpecialEffectKind.movesLast,
      maximumPowerPercent: 140,
    );
    expect(
      calculate(move: move, attackerMovesFirst: false)!.powerPercent,
      140,
    );
    expect(calculate(move: move)!.powerPercent, 100);
  });

  test('倍率の表示は整数から組み立て、末尾の 0 を省く', () {
    expect(formatPowerPercent(powerPercent: 100), '1');
    expect(formatPowerPercent(powerPercent: 150), '1.5');
    expect(formatPowerPercent(powerPercent: 125), '1.25');
    expect(formatPowerPercent(powerPercent: 105), '1.05');
    expect(formatPowerPercent(powerPercent: 200), '2');
  });

  test('知らない種類の特殊効果は読まずに null にする (新しい版の master を古いアプリが読めるように)', () {
    expect(
      moveSpecialEffectFromJson(
        json: {'kind': 'weatherSunny', 'maximumPowerPercent': 150},
      ),
      isNull,
    );
    expect(moveSpecialEffectFromJson(json: null), isNull);
    final specialEffect = moveSpecialEffectFromJson(
      json: {'kind': 'movesFirst', 'maximumPowerPercent': 130},
    )!;
    expect(specialEffect.kind, MoveSpecialEffectKind.movesFirst);
    expect(specialEffect.maximumPowerPercent, 130);
  });

  test('すべての種類に技の枠の短い説明がある', () {
    for (final kind in MoveSpecialEffectKind.values) {
      expect(moveSpecialEffectSummary(kind: kind), isNotEmpty);
    }
  });
}
