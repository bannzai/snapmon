import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/battle/status_condition.dart';
import 'package:snapmon/domain/master/element_type.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/domain/master/move.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';

/// バトルの規則だけを確かめるための小さな master。fire は grass に 2 倍、grass は fire に 0.5 倍。
final testMaster = MasterData(
  version: 1,
  elementTypes: [
    ElementType(id: 'fire', displayName: 'ほのお'),
    ElementType(id: 'grass', displayName: 'くさ'),
  ],
  typeChart: {
    'fire': {'fire': 1, 'grass': 2},
    'grass': {'fire': 0.5, 'grass': 1},
  },
  moves: [
    Move(
      id: 'fire_strong',
      displayName: 'つよいほのお',
      elementTypeId: 'fire',
      power: 60,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
    ),
    Move(
      id: 'grass_strong',
      displayName: 'つよいくさ',
      elementTypeId: 'grass',
      power: 60,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
    ),
    Move(
      id: 'grass_weak',
      displayName: 'よわいくさ',
      elementTypeId: 'grass',
      power: 20,
      powerPoints: 2,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
    ),
    Move(
      id: 'fire_last',
      displayName: 'あとだしほのお',
      elementTypeId: 'fire',
      power: 60,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: 'if(not movesFirst, 200, 100)',
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        summary: '後に動くと強い',
        rule: '後に行動すると威力が上がる',
      ),
    ),
    Move(
      id: 'fire_last_resort',
      displayName: 'のこりびほのお',
      elementTypeId: 'fire',
      power: 60,
      powerPoints: 2,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power:
            '100 + 100 * (move.maximumPowerPoints - move.remainingPowerPoints) / (move.maximumPowerPoints - 1)',
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        summary: 'PP が減るほど強い',
        rule: 'この技の残り PP が少ないほど威力が上がる',
      ),
    ),
    Move(
      id: 'fire_desperate',
      displayName: 'やけっぱちほのお',
      elementTypeId: 'fire',
      power: 60,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power:
            '100 + 100 * (self.maximumHitPoints - self.hitPoints) / self.maximumHitPoints',
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        summary: '自分が弱るほど強い',
        rule: '自分の HP が減っているほど威力が上がる',
      ),
    ),
    Move(
      id: 'fire_lower_defense',
      displayName: 'ぼうぎょさげ',
      elementTypeId: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {StatKind.defense: '-25'},
        selfHitPointsRecovery: null,
        summary: '相手の防御を下げる',
        rule: '相手の防御を下げる',
      ),
    ),
    Move(
      id: 'fire_raise_attack',
      displayName: 'こうげきあげ',
      elementTypeId: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {StatKind.attack: '25'},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        summary: '自分の攻撃を上げる',
        rule: '自分の攻撃を上げる',
      ),
    ),
    Move(
      id: 'fire_lower_speed',
      displayName: 'すばやさげ',
      elementTypeId: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {StatKind.speed: '-25'},
        selfHitPointsRecovery: null,
        summary: '相手の素早さを下げる',
        rule: '相手の素早さを下げる',
      ),
    ),
    Move(
      id: 'fire_recover',
      displayName: 'かいふく',
      elementTypeId: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: 'self.maximumHitPoints * 30 / 100',
        summary: 'HP を回復する',
        rule: '最大 HP の 3 割を回復する',
      ),
    ),
    // 版 9 (#224) の効果を 1 つずつ持つ技
    for (final (id, kind) in [
      ('fire_paralyze', StatusConditionKind.paralysis),
      ('fire_stun', StatusConditionKind.stun),
      ('fire_burn', StatusConditionKind.burn),
      ('fire_drowsy', StatusConditionKind.drowsy),
      ('fire_curse', StatusConditionKind.curse),
      ('fire_confuse', StatusConditionKind.confusion),
      ('fire_dizzy', StatusConditionKind.dizzy),
      ('fire_freeze', StatusConditionKind.frozen),
      ('fire_poison_support', StatusConditionKind.poison),
      ('fire_block_switch', StatusConditionKind.switchBlocked),
    ])
      Move(
        id: id,
        displayName: id,
        elementTypeId: 'fire',
        power: 0,
        powerPoints: 10,
        category: MoveCategory.support,
        effectId: 'none',
        learnableLevelMinimum: 1,
        learnableLevelMaximum: 999,
        specialEffect: MoveSpecialEffect(
          power: null,
          selfStatChanges: const {},
          opponentStatChanges: const {},
          selfHitPointsRecovery: null,
          opponentStatusConditions: [
            StatusConditionInfliction(kind: kind, chancePercent: 100),
          ],
          summary: '相手を ${kind.name} にする',
          rule: '相手を ${kind.name} にする',
        ),
      ),
    const Move(
      id: 'fire_excite',
      displayName: 'こうふん',
      elementTypeId: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        selfStatusConditions: [
          StatusConditionInfliction(
            kind: StatusConditionKind.excited,
            chancePercent: 100,
          ),
        ],
        summary: '自分が興奮する',
        rule: '自分が興奮する',
      ),
    ),
    const Move(
      id: 'fire_poison_attack',
      displayName: 'どくのほのお',
      elementTypeId: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        opponentStatusConditions: [
          StatusConditionInfliction(
            kind: StatusConditionKind.poison,
            chancePercent: 100,
          ),
        ],
        summary: '相手を毒にする',
        rule: '相手を毒にする',
      ),
    ),
    const Move(
      id: 'poison_strong',
      displayName: 'つよいどく',
      elementTypeId: 'poison',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
    ),
    const Move(
      id: 'fire_cure',
      displayName: 'かいじょ',
      elementTypeId: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        curesSelfStatusConditions: true,
        summary: '自分の状態を治す',
        rule: '自分の状態を治す',
      ),
    ),
    const Move(
      id: 'fire_shuffle',
      displayName: 'いれかえ',
      elementTypeId: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        fieldEffect: FieldEffectKind.statShuffle,
        summary: 'ステータスが入れ替わる',
        rule: 'ステータスが入れ替わる',
      ),
    ),
    const Move(
      id: 'fire_self_destruct',
      displayName: 'じばく',
      elementTypeId: 'fire',
      power: 200,
      powerPoints: 5,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        selfDestructs: true,
        summary: '自爆する',
        rule: '自爆する',
      ),
    ),
    const Move(
      id: 'fire_one_hit',
      displayName: 'いちげき',
      elementTypeId: 'fire',
      power: 0,
      powerPoints: 1,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        isOneHitKnockout: true,
        summary: '一撃必殺',
        rule: '一撃必殺',
      ),
      accuracy: 30,
    ),
    const Move(
      id: 'fire_sure_hit',
      displayName: 'ひっちゅう',
      elementTypeId: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        isSureHit: true,
        summary: '必ず当たる',
        rule: '必ず当たる',
      ),
      accuracy: 50,
    ),
    const Move(
      id: 'fire_priority',
      displayName: 'せんせい',
      elementTypeId: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
      priority: 1,
    ),
    const Move(
      id: 'fire_inaccurate',
      displayName: 'はずれやすい',
      elementTypeId: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectId: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
      accuracy: 50,
    ),
  ],
  effects: [],
  statGrades: [],
  elementSelection: null,
);

/// テストのバトルの対戦日。今の特殊効果はどれも対戦日を使わないため、値は結果に効かない。
final testBattleDate = DateTime.utc(2026, 10, 28);

/// 種族値・個体値を揃えた、テスト用のモンスターの定義を返す。
MonsterDefinition testDefinition({
  required String id,
  required String elementTypeId,
  required List<String> moveIds,
  required int speed,
  int hitPoints = 80,
}) => MonsterDefinition(
  id: id,
  sourcePhotoReference: 'users/test/photos/$id.jpg',
  name: id,
  encyclopediaText: '',
  elementTypeIds: [elementTypeId],
  learnset: [
    for (final moveId in moveIds) LearnsetEntry(moveId: moveId, unlockLevel: 1),
  ],
  baseStats: MonsterStats(
    hitPoints: hitPoints,
    attack: 80,
    defense: 80,
    speed: speed,
  ),
  individualValues: const MonsterStats(
    hitPoints: 0,
    attack: 0,
    defense: 0,
    speed: 0,
  ),
  statCalculationVersion: 1,
  masterVersion: 1,
);

BattleMonster prepare({
  required MonsterDefinition definition,
  int level = 50,
}) => prepareBattleMonster(
  definition: definition,
  level: level,
  experience: 0,
  master: testMaster,
);

/// 両陣営とも CPU の規則で行動させ、決着までのターンを進めた状態を返す。
BattleState playUntilFinished({required BattleState state}) {
  var current = state;
  while (current.winner == null) {
    current = advanceRound(
      state: current,
      playerAction: chooseCpuAction(
        state: current,
        side: BattleSideId.player,
        master: testMaster,
      ),
      opponentAction: chooseCpuAction(
        state: current,
        side: BattleSideId.opponent,
        master: testMaster,
      ),
      master: testMaster,
    );
    expect(current.turnNumber, lessThan(1000), reason: 'バトルが終わらない');
  }
  return current;
}

void main() {
  test('相性 2 倍の技は等倍より与ダメージが大きく、0.5 倍は小さい', () {
    int damage(double typeMultiplier) => calculateDamage(
      attackerLevel: 50,
      power: 60,
      attack: 100,
      defense: 100,
      typeMultiplier: typeMultiplier,
      randomPercent: 100,
    );
    expect(damage(2), greaterThan(damage(1)));
    expect(damage(0.5), lessThan(damage(1)));
    expect(
      totalTypeMultiplier(
        moveElementTypeId: 'fire',
        defenderElementTypeIds: ['grass', 'grass'],
        master: testMaster,
      ),
      4,
    );

    final state = startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeId: 'fire',
            moveIds: ['fire_strong'],
            speed: 100,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeId: 'fire',
            moveIds: ['grass_strong'],
            speed: 50,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
    );
    final grassTarget = startBattle(
      playerMembers: state.player.members,
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeId: 'grass',
            moveIds: ['grass_strong'],
            speed: 50,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
    );
    MoveUsedEvent firstHit(BattleState battleState) => advanceRound(
      state: battleState,
      playerAction: const UseMoveAction(moveId: 'fire_strong'),
      opponentAction: const UseMoveAction(moveId: 'grass_strong'),
      master: testMaster,
    ).events.whereType<MoveUsedEvent>().first;
    expect(firstHit(grassTarget).typeMultiplier, 2);
    expect(firstHit(grassTarget).damage, greaterThan(firstHit(state).damage));
  });

  test('CPU は相性の倍率が最大の技を選ぶ (倍率が同じなら威力が高い技)', () {
    final state = startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeId: 'grass',
            moveIds: ['grass_weak', 'fire_strong'],
            speed: 50,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeId: 'fire',
            moveIds: ['grass_weak', 'grass_strong'],
            speed: 50,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
    );
    final playerAction = chooseCpuAction(
      state: state,
      side: BattleSideId.player,
      master: testMaster,
    );
    expect((playerAction as UseMoveAction).moveId, 'fire_strong');
    final opponentAction = chooseCpuAction(
      state: state,
      side: BattleSideId.opponent,
      master: testMaster,
    );
    expect((opponentAction as UseMoveAction).moveId, 'grass_strong');
  });

  test('素早さが高い方が先に動く', () {
    BattleSideId firstAttacker({
      required int playerSpeed,
      required int opponentSpeed,
    }) => advanceRound(
      state: startBattle(
        playerMembers: [
          prepare(
            definition: testDefinition(
              id: 'player',
              elementTypeId: 'fire',
              moveIds: ['fire_strong'],
              speed: playerSpeed,
            ),
          ),
        ],
        opponentMembers: [
          prepare(
            definition: testDefinition(
              id: 'opponent',
              elementTypeId: 'fire',
              moveIds: ['fire_strong'],
              speed: opponentSpeed,
            ),
          ),
        ],
        randomSeed: 1,
        battleDate: testBattleDate,
      ),
      playerAction: const UseMoveAction(moveId: 'fire_strong'),
      opponentAction: const UseMoveAction(moveId: 'fire_strong'),
      master: testMaster,
    ).events.whereType<MoveUsedEvent>().first.attackerSide;

    expect(
      firstAttacker(playerSpeed: 100, opponentSpeed: 50),
      BattleSideId.player,
    );
    expect(
      firstAttacker(playerSpeed: 50, opponentSpeed: 100),
      BattleSideId.opponent,
    );
  });

  test('PP が尽きた技は選べず、使える技が無くなるとわるあがきになる', () {
    var state = startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeId: 'fire',
            moveIds: ['grass_weak'],
            speed: 100,
            hitPoints: 250,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeId: 'fire',
            moveIds: ['grass_weak'],
            speed: 50,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
    );
    expect(
      () => advanceRound(
        state: state,
        playerAction: const StruggleAction(),
        opponentAction: const UseMoveAction(moveId: 'grass_weak'),
        master: testMaster,
      ),
      throwsArgumentError,
    );
    for (var turn = 0; turn < 2; turn++) {
      state = advanceRound(
        state: state,
        playerAction: const UseMoveAction(moveId: 'grass_weak'),
        opponentAction: const UseMoveAction(moveId: 'grass_weak'),
        master: testMaster,
      );
    }
    expect(
      state.player.activeMember.state.remainingPowerPoints['grass_weak'],
      0,
    );
    expect(
      selectableMoves(monster: state.player.activeMember, master: testMaster),
      isEmpty,
    );
    expect(
      () => advanceRound(
        state: state,
        playerAction: const UseMoveAction(moveId: 'grass_weak'),
        opponentAction: const StruggleAction(),
        master: testMaster,
      ),
      throwsArgumentError,
    );
    expect(
      chooseCpuAction(
        state: state,
        side: BattleSideId.opponent,
        master: testMaster,
      ),
      isA<StruggleAction>(),
    );
    final afterStruggle = advanceRound(
      state: state,
      playerAction: const StruggleAction(),
      opponentAction: const StruggleAction(),
      master: testMaster,
    );
    final struggleEvents = afterStruggle.events
        .whereType<MoveUsedEvent>()
        .where((event) => event.turnNumber >= state.turnNumber);
    expect(struggleEvents.map((event) => event.moveId), [null, null]);
    expect(struggleEvents.every((event) => event.damage > 0), isTrue);
  });

  group('3 体の手持ち', () {
    BattleState startThreeOnThree({
      required int randomSeed,
      int leadPlayerLevel = 50,
    }) => startBattle(
      playerMembers: [
        for (final index in [1, 2, 3])
          prepare(
            definition: testDefinition(
              id: 'player_$index',
              elementTypeId: 'fire',
              moveIds: ['fire_strong'],
              speed: 100,
            ),
            level: index == 1 ? leadPlayerLevel : 50,
          ),
      ],
      opponentMembers: [
        for (final index in [1, 2, 3])
          prepare(
            definition: testDefinition(
              id: 'opponent_$index',
              elementTypeId: 'grass',
              moveIds: ['grass_strong'],
              speed: 50,
            ),
          ),
      ],
      randomSeed: randomSeed,
      battleDate: testBattleDate,
    );

    test('3 体すべて倒れた側が負け、勝敗を問わず場に出た手持ちのレベルが 1 上がる (上限 999)', () {
      final finished = playUntilFinished(
        state: startThreeOnThree(randomSeed: 7, leadPlayerLevel: 999),
      );

      expect(finished.winner, BattleSideId.player);
      expect(finished.opponent.isDefeated, isTrue);
      expect(
        finished.events.whereType<MonsterSwitchedInEvent>().map(
          (event) => event.monsterId,
        ),
        containsAllInOrder(['opponent_2', 'opponent_3']),
      );
      // 先頭の 1 体 (レベル 999) だけで勝つため、場に出なかった 2・3 体目は変わらない
      expect(finished.player.members.map((member) => member.state.level), [
        999,
        50,
        50,
      ]);
      expect(finished.player.members.map((member) => member.state.experience), [
        1,
        0,
        0,
      ]);
      expect(finished.opponent.members.map((member) => member.state.level), [
        51,
        51,
        51,
      ]);
      expect(
        finished.opponent.members.map((member) => member.state.experience),
        [1, 1, 1],
      );
      expect(finished.events.last, isA<BattleFinishedEvent>());
      expect(
        () => advanceRound(
          state: finished,
          playerAction: const UseMoveAction(moveId: 'fire_strong'),
          opponentAction: const UseMoveAction(moveId: 'grass_strong'),
          master: testMaster,
        ),
        throwsStateError,
      );
    });

    test('seed が同じなら結果が同じで、seed が違えばダメージの乱数幅で結果が変わる', () {
      List<int> damages(BattleState state) => [
        for (final event in state.events.whereType<MoveUsedEvent>())
          event.damage,
      ];
      final first = playUntilFinished(state: startThreeOnThree(randomSeed: 42));
      final second = playUntilFinished(
        state: startThreeOnThree(randomSeed: 42),
      );
      expect(damages(first), damages(second));
      expect(first.turnNumber, second.turnNumber);
      expect(first.randomState, second.randomState);
      // 素早さが違う組み合わせで同速の判定を通らないため、差はダメージの乱数幅からだけ生まれる
      final otherSeed = playUntilFinished(
        state: startThreeOnThree(randomSeed: 43),
      );
      expect(damages(otherSeed), isNot(damages(first)));
    });
  });

  test('素早さが同じ時の行動順は seed で決まる (同じ seed なら同じ、seed によって入れ替わる)', () {
    BattleSideId firstAttacker({required int randomSeed}) => advanceRound(
      state: startBattle(
        playerMembers: [
          prepare(
            definition: testDefinition(
              id: 'player',
              elementTypeId: 'fire',
              moveIds: ['fire_strong'],
              speed: 80,
            ),
          ),
        ],
        opponentMembers: [
          prepare(
            definition: testDefinition(
              id: 'opponent',
              elementTypeId: 'fire',
              moveIds: ['fire_strong'],
              speed: 80,
            ),
          ),
        ],
        randomSeed: randomSeed,
        battleDate: testBattleDate,
      ),
      playerAction: const UseMoveAction(moveId: 'fire_strong'),
      opponentAction: const UseMoveAction(moveId: 'fire_strong'),
      master: testMaster,
    ).events.whereType<MoveUsedEvent>().first.attackerSide;

    final firstAttackers = [
      for (var randomSeed = 1; randomSeed <= 20; randomSeed++)
        firstAttacker(randomSeed: randomSeed),
    ];
    expect(firstAttackers.toSet(), BattleSideId.values.toSet());
    expect([
      for (var randomSeed = 1; randomSeed <= 20; randomSeed++)
        firstAttacker(randomSeed: randomSeed),
    ], firstAttackers);
  });

  test('補助技しか残っていない時はわるあがきを選べ、CPU の行動で決着する', () {
    final supportOnlyMaster = mergeMasterData(
      base: testMaster,
      additional: const MasterData(
        version: 1,
        elementTypes: [],
        typeChart: {},
        moves: [
          Move(
            id: 'support_only',
            displayName: 'みまもる',
            elementTypeId: 'fire',
            power: 0,
            powerPoints: 5,
            category: MoveCategory.support,
            effectId: 'none',
            learnableLevelMinimum: 1,
            learnableLevelMaximum: 999,
            specialEffect: null,
          ),
        ],
        effects: [],
        statGrades: [],
        elementSelection: null,
      ),
    );
    BattleMonster supportOnlyMonster({required String id}) =>
        prepareBattleMonster(
          definition: testDefinition(
            id: id,
            elementTypeId: 'fire',
            moveIds: ['support_only'],
            speed: id == 'player' ? 100 : 50,
          ),
          level: 50,
          experience: 0,
          master: supportOnlyMaster,
        );
    var state = startBattle(
      playerMembers: [supportOnlyMonster(id: 'player')],
      opponentMembers: [supportOnlyMonster(id: 'opponent')],
      randomSeed: 1,
      battleDate: testBattleDate,
    );
    while (state.winner == null) {
      state = advanceRound(
        state: state,
        playerAction: chooseCpuAction(
          state: state,
          side: BattleSideId.player,
          master: supportOnlyMaster,
        ),
        opponentAction: chooseCpuAction(
          state: state,
          side: BattleSideId.opponent,
          master: supportOnlyMaster,
        ),
        master: supportOnlyMaster,
      );
      expect(state.turnNumber, lessThan(1000), reason: 'バトルが終わらない');
    }
    expect(state.winner, isNotNull);
  });

  group('技の特殊効果', () {
    /// 速さ [playerSpeed] の自分と速さ [opponentSpeed] の相手が、それぞれ [playerMoveId]・[opponentMoveId] だけを持つバトル。
    BattleState startDuel({
      required String playerMoveId,
      required String opponentMoveId,
      required int playerSpeed,
      required int opponentSpeed,
    }) => startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeId: 'fire',
            moveIds: [playerMoveId],
            speed: playerSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeId: 'fire',
            moveIds: [opponentMoveId],
            speed: opponentSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
    );

    /// [state] から両陣営が [playerMoveId]・[opponentMoveId] を使って 1 ターン進め、陣営ごとの技のログを返す。
    Map<BattleSideId, MoveUsedEvent> playTurn({
      required BattleState state,
      required String playerMoveId,
      required String opponentMoveId,
    }) => {
      for (final event in advanceRound(
        state: state,
        playerAction: UseMoveAction(moveId: playerMoveId),
        opponentAction: UseMoveAction(moveId: opponentMoveId),
        master: testMaster,
      ).events.skip(state.events.length).whereType<MoveUsedEvent>())
        event.attackerSide: event,
    };

    test('後に動くと強い技は、そのターンに後に行動した側だけ倍率が最大になり、ダメージが増える', () {
      final events = playTurn(
        state: startDuel(
          playerMoveId: 'fire_last',
          opponentMoveId: 'fire_last',
          playerSpeed: 50,
          opponentSpeed: 100,
        ),
        playerMoveId: 'fire_last',
        opponentMoveId: 'fire_last',
      );
      expect(events[BattleSideId.opponent]!.specialEffect!.powerPercent, 100);
      expect(events[BattleSideId.player]!.specialEffect!.powerPercent, 200);
      // 威力 2 倍は乱数幅 (85〜100%) より大きいため、同じ条件の相手より必ず多く与える
      expect(
        events[BattleSideId.player]!.damage,
        greaterThan(events[BattleSideId.opponent]!.damage),
      );
    });

    test('残り PP が少ないほど強い技は、使う前の残りで計算する (PP 2 の技の 2 回目で最大)', () {
      final firstState = startDuel(
        playerMoveId: 'fire_last_resort',
        opponentMoveId: 'fire_strong',
        playerSpeed: 100,
        opponentSpeed: 50,
      );
      expect(
        playTurn(
          state: firstState,
          playerMoveId: 'fire_last_resort',
          opponentMoveId: 'fire_strong',
        )[BattleSideId.player]!.specialEffect!.powerPercent,
        100,
      );
      expect(
        playTurn(
          state: advanceRound(
            state: firstState,
            playerAction: const UseMoveAction(moveId: 'fire_last_resort'),
            opponentAction: const UseMoveAction(moveId: 'fire_strong'),
            master: testMaster,
          ),
          playerMoveId: 'fire_last_resort',
          opponentMoveId: 'fire_strong',
        )[BattleSideId.player]!.specialEffect!.powerPercent,
        200,
      );
    });

    test('自分の HP が減っているほど強い技は、同じターンに先に受けたダメージを倍率に入れる', () {
      final events = playTurn(
        state: startDuel(
          playerMoveId: 'fire_desperate',
          opponentMoveId: 'fire_strong',
          playerSpeed: 50,
          opponentSpeed: 100,
        ),
        playerMoveId: 'fire_desperate',
        opponentMoveId: 'fire_strong',
      );
      expect(events[BattleSideId.opponent]!.damage, greaterThan(0));
      expect(
        events[BattleSideId.player]!.specialEffect!.powerPercent,
        greaterThan(100),
      );
    });

    test('特殊効果の無い技のログは特殊効果を持たない', () {
      final events = playTurn(
        state: startDuel(
          playerMoveId: 'fire_strong',
          opponentMoveId: 'fire_strong',
          playerSpeed: 100,
          opponentSpeed: 50,
        ),
        playerMoveId: 'fire_strong',
        opponentMoveId: 'fire_strong',
      );
      expect(events[BattleSideId.player]!.specialEffect, isNull);
    });
  });

  group('補助技', () {
    /// 自分 (速さ [playerSpeed]、技 [playerMoveIds]) と相手 (速さ [opponentSpeed]、技 [opponentMoveIds]) の 1 対 1 のバトル。
    BattleState startDuel({
      required List<String> playerMoveIds,
      required List<String> opponentMoveIds,
      required int playerSpeed,
      required int opponentSpeed,
      int randomSeed = 1,
    }) => startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeId: 'fire',
            moveIds: playerMoveIds,
            speed: playerSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeId: 'fire',
            moveIds: opponentMoveIds,
            speed: opponentSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: randomSeed,
      battleDate: testBattleDate,
    );

    /// [state] から両陣営が [playerMoveId]・[opponentMoveId] を使って 1 ターン進めた状態を返す。
    BattleState playTurn({
      required BattleState state,
      required String playerMoveId,
      required String opponentMoveId,
    }) => advanceRound(
      state: state,
      playerAction: UseMoveAction(moveId: playerMoveId),
      opponentAction: UseMoveAction(moveId: opponentMoveId),
      master: testMaster,
    );

    /// [state] の最後のターンの、[side] が使った技のログ。
    MoveUsedEvent lastMoveOf({
      required BattleState state,
      required BattleSideId side,
    }) => state.events.whereType<MoveUsedEvent>().lastWhere(
      (event) => event.attackerSide == side,
    );

    test('相手の防御を下げる技はダメージを与えず、倍率を 25 ずつ下げ、下限 50 で止まる', () {
      var state = startDuel(
        playerMoveIds: ['fire_lower_defense'],
        opponentMoveIds: ['grass_weak'],
        playerSpeed: 100,
        opponentSpeed: 50,
      );
      // 相手の技 (grass_weak) は PP 2 のため、2 ターン使った後はわるあがきになる
      for (final expectedPercent in [75, 50]) {
        final previousPercent = statModifierPercentOf(
          monster: state.opponent.activeMember,
          statKind: StatKind.defense,
        );
        state = playTurn(
          state: state,
          playerMoveId: 'fire_lower_defense',
          opponentMoveId: 'grass_weak',
        );
        final event = lastMoveOf(state: state, side: BattleSideId.player);
        expect(event.damage, 0);
        expect(event.statModifierChanges, hasLength(1));
        expect(event.statModifierChanges.single.side, BattleSideId.opponent);
        expect(event.statModifierChanges.single.statKind, StatKind.defense);
        expect(
          event.statModifierChanges.single.previousPercent,
          previousPercent,
        );
        expect(event.statModifierChanges.single.newPercent, expectedPercent);
        expect(
          statModifierPercentOf(
            monster: state.opponent.activeMember,
            statKind: StatKind.defense,
          ),
          expectedPercent,
        );
      }
      // 下限に達した後にもう一度使うと、倍率は変わらず、変化の前後が同じ値で残る
      state = advanceRound(
        state: state,
        playerAction: const UseMoveAction(moveId: 'fire_lower_defense'),
        opponentAction: const StruggleAction(),
        master: testMaster,
      );
      final capped = lastMoveOf(state: state, side: BattleSideId.player);
      expect(capped.statModifierChanges.single.previousPercent, 50);
      expect(capped.statModifierChanges.single.newPercent, 50);
    });

    test('下げた防御はダメージ式に入り、同じ乱数なら下げる前より多く与える', () {
      final before = startDuel(
        playerMoveIds: ['fire_strong', 'fire_lower_defense'],
        opponentMoveIds: ['fire_strong'],
        playerSpeed: 100,
        opponentSpeed: 50,
      );
      final lowered = playTurn(
        state: before,
        playerMoveId: 'fire_lower_defense',
        opponentMoveId: 'fire_strong',
      );
      // 乱数の状態を揃えて、防御の倍率だけが違う 2 つの状態から同じ攻撃をする
      final loweredWithSameRandom = BattleState(
        player: lowered.player,
        opponent: lowered.opponent,
        turnNumber: before.turnNumber,
        randomState: before.randomState,
        events: before.events,
        winner: null,
        battleDate: before.battleDate,
        field: null,
      );
      final beforeWithSameHitPoints = BattleState(
        player: lowered.player,
        opponent: BattleParty(
          members: [
            BattleMonster(
              definition: lowered.opponent.activeMember.definition,
              state: lowered.opponent.activeMember.state.copyWith(
                statModifierPercents: const {},
              ),
            ),
          ],
          activeMemberIndex: 0,
        ),
        turnNumber: before.turnNumber,
        randomState: before.randomState,
        events: before.events,
        winner: null,
        battleDate: before.battleDate,
        field: null,
      );
      int damageOf({required BattleState state}) => lastMoveOf(
        state: playTurn(
          state: state,
          playerMoveId: 'fire_strong',
          opponentMoveId: 'fire_strong',
        ),
        side: BattleSideId.player,
      ).damage;
      expect(
        damageOf(state: loweredWithSameRandom),
        greaterThan(damageOf(state: beforeWithSameHitPoints)),
      );
    });

    test('自分の攻撃を上げる技は、倍率を掛けた攻撃を返す', () {
      final state = playTurn(
        state: startDuel(
          playerMoveIds: ['fire_raise_attack'],
          opponentMoveIds: ['grass_weak'],
          playerSpeed: 100,
          opponentSpeed: 50,
        ),
        playerMoveId: 'fire_raise_attack',
        opponentMoveId: 'grass_weak',
      );
      final player = state.player.activeMember;
      final event = lastMoveOf(state: state, side: BattleSideId.player);
      expect(event.statModifierChanges.single.side, BattleSideId.player);
      expect(event.statModifierChanges.single.newPercent, 125);
      final baseAttack = effectiveStats(
        monster: BattleMonster(
          definition: player.definition,
          state: player.state.copyWith(statModifierPercents: const {}),
        ),
      ).attack;
      expect(effectiveStats(monster: player).attack, baseAttack * 125 ~/ 100);
    });

    test('相手の素早さを下げると、次のターンから行動順が入れ替わる', () {
      var state = startDuel(
        playerMoveIds: ['fire_strong'],
        opponentMoveIds: ['fire_lower_speed', 'fire_strong'],
        playerSpeed: 100,
        opponentSpeed: 90,
      );
      state = playTurn(
        state: state,
        playerMoveId: 'fire_strong',
        opponentMoveId: 'fire_lower_speed',
      );
      final firstTurnEvents = state.events.whereType<MoveUsedEvent>().toList();
      expect(firstTurnEvents.first.attackerSide, BattleSideId.player);
      state = playTurn(
        state: state,
        playerMoveId: 'fire_strong',
        opponentMoveId: 'fire_strong',
      );
      final secondTurnEvents = state.events
          .whereType<MoveUsedEvent>()
          .skip(firstTurnEvents.length)
          .toList();
      expect(secondTurnEvents.first.attackerSide, BattleSideId.opponent);
    });

    test('回復する技は最大 HP を超えず、満タンなら 0 回復', () {
      final fullHitPoints = playTurn(
        state: startDuel(
          playerMoveIds: ['fire_recover'],
          opponentMoveIds: ['grass_weak'],
          playerSpeed: 100,
          opponentSpeed: 50,
        ),
        playerMoveId: 'fire_recover',
        opponentMoveId: 'grass_weak',
      );
      expect(
        lastMoveOf(
          state: fullHitPoints,
          side: BattleSideId.player,
        ).recoveredHitPoints,
        0,
      );

      // 相手が先に攻撃して減った HP を、同じターンに回復する
      final damaged = playTurn(
        state: startDuel(
          playerMoveIds: ['fire_recover'],
          opponentMoveIds: ['fire_strong'],
          playerSpeed: 50,
          opponentSpeed: 100,
        ),
        playerMoveId: 'fire_recover',
        opponentMoveId: 'fire_strong',
      );
      final damage = lastMoveOf(
        state: damaged,
        side: BattleSideId.opponent,
      ).damage;
      final recovery = lastMoveOf(state: damaged, side: BattleSideId.player);
      final maximumHitPoints = effectiveStats(
        monster: damaged.player.activeMember,
      ).hitPoints;
      expect(recovery.damage, 0);
      expect(recovery.recoveredHitPoints, greaterThan(0));
      expect(
        recovery.recoveredHitPoints,
        lessThanOrEqualTo(math.min(damage, maximumHitPoints * 30 ~/ 100)),
      );
      expect(
        damaged.player.activeMember.state.currentHitPoints,
        recovery.attackerRemainingHitPoints,
      );
    });

    test('CPU は効果のある補助技をおよそ 1/4 の確率で選び、効果が無くなった補助技は選ばない', () {
      var supportCount = 0;
      const seedCount = 400;
      for (var seed = 1; seed <= seedCount; seed++) {
        final action = chooseCpuAction(
          state: startDuel(
            playerMoveIds: ['fire_strong', 'fire_lower_defense'],
            opponentMoveIds: ['fire_strong'],
            playerSpeed: 100,
            opponentSpeed: 50,
            randomSeed: seed,
          ),
          side: BattleSideId.player,
          master: testMaster,
        );
        if (action case UseMoveAction(moveId: 'fire_lower_defense')) {
          supportCount++;
        }
      }
      // 1/4 の期待値は 100 回。xorshift の偏りを許す幅として ±40 にした
      expect(supportCount, inInclusiveRange(60, 140));

      final defenseAtMinimum = startDuel(
        playerMoveIds: ['fire_strong', 'fire_lower_defense'],
        opponentMoveIds: ['fire_strong'],
        playerSpeed: 100,
        opponentSpeed: 50,
      );
      for (var seed = 1; seed <= 50; seed++) {
        final state = BattleState(
          player: defenseAtMinimum.player,
          opponent: BattleParty(
            members: [
              BattleMonster(
                definition: defenseAtMinimum.opponent.activeMember.definition,
                state: defenseAtMinimum.opponent.activeMember.state.copyWith(
                  statModifierPercents: const {
                    StatKind.defense: statModifierPercentMinimum,
                  },
                ),
              ),
            ],
            activeMemberIndex: 0,
          ),
          turnNumber: 1,
          randomState: seed,
          events: const [],
          winner: null,
          battleDate: testBattleDate,
          field: null,
        );
        expect(
          chooseCpuAction(
            state: state,
            side: BattleSideId.player,
            master: testMaster,
          ),
          isA<UseMoveAction>().having(
            (action) => action.moveId,
            'moveId',
            'fire_strong',
          ),
        );
      }

      // HP が満タンの時は回復だけの技を選ばない
      for (var seed = 1; seed <= 50; seed++) {
        expect(
          chooseCpuAction(
            state: startDuel(
              playerMoveIds: ['fire_strong', 'fire_recover'],
              opponentMoveIds: ['fire_strong'],
              playerSpeed: 100,
              opponentSpeed: 50,
              randomSeed: seed,
            ),
            side: BattleSideId.player,
            master: testMaster,
          ),
          isA<UseMoveAction>().having(
            (action) => action.moveId,
            'moveId',
            'fire_strong',
          ),
        );
      }
    });

    test('補助技を持つ CPU 同士のバトルも決着する', () {
      final state = playUntilFinished(
        state: startDuel(
          playerMoveIds: [
            'fire_strong',
            'fire_lower_defense',
            'fire_raise_attack',
            'fire_recover',
          ],
          opponentMoveIds: [
            'fire_strong',
            'fire_lower_speed',
            'fire_raise_attack',
            'fire_recover',
          ],
          playerSpeed: 100,
          opponentSpeed: 90,
        ),
      );
      expect(state.winner, isNotNull);
      expect(
        state.events.whereType<MoveUsedEvent>().any(
          (event) => event.statModifierChanges.isNotEmpty,
        ),
        isTrue,
      );
    });
  });

  test('手持ちが 0 体・4 体以上ではバトルを始められない', () {
    final member = prepare(
      definition: testDefinition(
        id: 'member',
        elementTypeId: 'fire',
        moveIds: ['fire_strong'],
        speed: 50,
      ),
    );
    expect(
      () => startBattle(
        playerMembers: const [],
        opponentMembers: [member],
        randomSeed: 1,
        battleDate: testBattleDate,
      ),
      throwsArgumentError,
    );
    expect(
      () => startBattle(
        playerMembers: [member, member, member, member],
        opponentMembers: [member],
        randomSeed: 1,
        battleDate: testBattleDate,
      ),
      throwsArgumentError,
    );
  });

  group('equippedLearnsetEntries', () {
    const learnset = [
      LearnsetEntry(moveId: 'a', unlockLevel: 1),
      LearnsetEntry(moveId: 'b', unlockLevel: 1),
      LearnsetEntry(moveId: 'c', unlockLevel: 1),
      LearnsetEntry(moveId: 'd', unlockLevel: 1),
      LearnsetEntry(moveId: 'e', unlockLevel: 15),
      LearnsetEntry(moveId: 'f', unlockLevel: 15),
      LearnsetEntry(moveId: 'g', unlockLevel: 100),
    ];
    List<String> equippedMoveIds({required int level}) => [
      for (final learnsetEntry in equippedLearnsetEntries(
        learnset: learnset,
        level: level,
      ))
        learnsetEntry.moveId,
    ];

    test('開放済みの技が枠の数までなら、開放済みの技をすべて一覧の順で返す', () {
      expect(equippedMoveIds(level: 14), ['a', 'b', 'c', 'd']);
    });

    test('開放済みの技が枠より多い時は、新しく覚えた技が一番古い技と入れ替わる', () {
      expect(equippedMoveIds(level: 15), ['c', 'd', 'e', 'f']);
      expect(equippedMoveIds(level: 100), ['d', 'e', 'f', 'g']);
    });

    test('覚える技が枠より少ない (前の規則で生まれた) モンスターも、開放済みの技をすべて返す', () {
      expect(
        equippedLearnsetEntries(
          learnset: const [
            LearnsetEntry(moveId: 'paper_1', unlockLevel: 1),
            LearnsetEntry(moveId: 'paper_2', unlockLevel: 15),
          ],
          level: 1,
        ).map((learnsetEntry) => learnsetEntry.moveId),
        ['paper_1'],
      );
    });

    test('バトルで選べる技は枠に入った技だけ', () {
      final monster = prepare(
        definition: testDefinition(
          id: 'player',
          elementTypeId: 'fire',
          moveIds: ['fire_strong', 'grass_strong'],
          speed: 50,
        ),
        level: 1,
      );
      expect(
        selectableMoves(
          monster: monster,
          master: testMaster,
        ).map((move) => move.id),
        ['fire_strong', 'grass_strong'],
      );
    });
  });

  group('状態・フィールド・命中・先制 (版 9)', () {
    /// 速い自分 (fire、技 [playerMoveIds]) と遅い相手 (fire、技 [opponentMoveIds]。HP は多め) の 1 対 1 を始める。
    BattleState duel({
      required List<String> playerMoveIds,
      required List<String> opponentMoveIds,
      int randomSeed = 1,
      int playerSpeed = 100,
      int opponentSpeed = 50,
      int opponentHitPoints = 250,
    }) => startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeId: 'fire',
            moveIds: playerMoveIds,
            speed: playerSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeId: 'fire',
            moveIds: opponentMoveIds,
            speed: opponentSpeed,
            hitPoints: opponentHitPoints,
          ),
        ),
      ],
      // 小さい seed (1, 2, ...) は xorshift の最初の出力が seed × 270369 (3 の倍数) になり、1〜3 の乱数が
      // どの seed でも同じ値になる。アプリの seed は Random の 32 bit の値のため、テストでも黄金比の定数を掛けて散らす
      randomSeed: (randomSeed * 0x9E3779B9) & 0xFFFFFFFF,
      battleDate: testBattleDate,
    );

    BattleState play({
      required BattleState state,
      required String playerMoveId,
      required String opponentMoveId,
    }) => advanceRound(
      state: state,
      playerAction: UseMoveAction(moveId: playerMoveId),
      opponentAction: UseMoveAction(moveId: opponentMoveId),
      master: testMaster,
    );

    /// [state] の最後のラウンドで増えたログ。
    List<BattleEvent> lastRoundEvents({
      required BattleState state,
      required BattleState previous,
    }) => state.events.skip(previous.events.length).toList();

    test('1 ラウンドは両陣営のターン 2 つで、ログのターン番号は行動ごとに 1 増える', () {
      final before = duel(
        playerMoveIds: ['fire_strong'],
        opponentMoveIds: ['fire_strong'],
      );
      final after = play(
        state: before,
        playerMoveId: 'fire_strong',
        opponentMoveId: 'fire_strong',
      );
      expect(before.turnNumber, 1);
      expect(before.roundNumber, 1);
      expect(after.turnNumber, 3);
      expect(after.roundNumber, 2);
      expect(
        after.events.whereType<MoveUsedEvent>().map(
          (event) => event.turnNumber,
        ),
        [1, 2],
      );
    });

    test('毒は持ち主のターンの終わりに最大 HP の 1/16 を削り、毒の技を受けると重なりが増える', () {
      var state = duel(
        playerMoveIds: ['fire_poison_attack', 'poison_strong'],
        opponentMoveIds: ['fire_strong'],
      );
      state = play(
        state: state,
        playerMoveId: 'fire_poison_attack',
        opponentMoveId: 'fire_strong',
      );
      final opponent = state.opponent.activeMember;
      final poison =
          opponent.state.statusConditions[StatusConditionKind.poison];
      expect(poison, isNotNull);
      expect(poison!.stackCount, 1);
      expect(poison.remainingTurns, isNull);
      final maximumHitPoints = effectiveStats(monster: opponent).hitPoints;
      final poisonDamages = state.events
          .whereType<StatusConditionDamageEvent>()
          .toList();
      expect(poisonDamages, hasLength(1));
      expect(poisonDamages.single.side, BattleSideId.opponent);
      expect(poisonDamages.single.damage, maximumHitPoints ~/ 16);
      expect(poisonDamages.single.turnNumber, 2);

      state = play(
        state: state,
        playerMoveId: 'poison_strong',
        opponentMoveId: 'fire_strong',
      );
      expect(
        state
            .opponent
            .activeMember
            .state
            .statusConditions[StatusConditionKind.poison]!
            .stackCount,
        2,
      );
      expect(
        state.events.whereType<StatusConditionDamageEvent>().last.damage,
        maximumHitPoints * 2 ~/ 16,
      );
      expect(
        state.events.whereType<StatusConditionInflictedEvent>().last.stackCount,
        2,
      );
    });

    test('麻痺は次の自分のターンの攻撃技だけを失敗させ (PP は減らない)、そのターンの終わりに消える', () {
      var state = duel(
        playerMoveIds: ['fire_paralyze', 'fire_strong'],
        opponentMoveIds: ['fire_strong', 'fire_raise_attack'],
      );
      state = play(
        state: state,
        playerMoveId: 'fire_paralyze',
        opponentMoveId: 'fire_strong',
      );
      final failed = state.events.whereType<ActionFailedEvent>().single;
      expect(failed.side, BattleSideId.opponent);
      expect(failed.reason, ActionFailureReason.paralysis);
      expect(failed.turnNumber, 2);
      expect(
        state.opponent.activeMember.state.remainingPowerPoints['fire_strong'],
        10,
      );
      expect(
        state.events.whereType<StatusConditionCuredEvent>().single.cause,
        StatusConditionCureCause.expired,
      );
      expect(state.opponent.activeMember.state.statusConditions, isEmpty);
      // 麻痺でも補助技は使える
      state = play(
        state: state,
        playerMoveId: 'fire_paralyze',
        opponentMoveId: 'fire_raise_attack',
      );
      expect(
        state.events.whereType<MoveUsedEvent>().last.moveId,
        'fire_raise_attack',
      );
    });

    test('気絶・眠り・凍結は全ての行動を失敗させ、凍結は技のダメージを受けると解ける', () {
      for (final (moveId, reason) in [
        ('fire_stun', ActionFailureReason.stun),
        ('fire_freeze', ActionFailureReason.frozen),
      ]) {
        final state = play(
          state: duel(
            playerMoveIds: [moveId, 'fire_strong'],
            opponentMoveIds: ['fire_raise_attack'],
          ),
          playerMoveId: moveId,
          opponentMoveId: 'fire_raise_attack',
        );
        expect(
          state.events.whereType<ActionFailedEvent>().single.reason,
          reason,
        );
      }
      // 凍結は 1〜3 ターンで、1 ターンなら最初の自分のターンの終わりに解けるため、2 ターン以上残った seed で確かめる
      var state = duel(
        playerMoveIds: ['fire_freeze', 'fire_strong'],
        opponentMoveIds: ['fire_strong'],
      );
      for (var seed = 1; seed <= 20; seed++) {
        state = play(
          state: duel(
            playerMoveIds: ['fire_freeze', 'fire_strong'],
            opponentMoveIds: ['fire_strong'],
            randomSeed: seed,
          ),
          playerMoveId: 'fire_freeze',
          opponentMoveId: 'fire_strong',
        );
        if (state.opponent.activeMember.state.statusConditions.containsKey(
          StatusConditionKind.frozen,
        )) {
          break;
        }
      }
      expect(
        state.opponent.activeMember.state.statusConditions,
        contains(StatusConditionKind.frozen),
      );
      final previous = state;
      state = play(
        state: state,
        playerMoveId: 'fire_strong',
        opponentMoveId: 'fire_strong',
      );
      final roundEvents = lastRoundEvents(state: state, previous: previous);
      expect(
        roundEvents.whereType<StatusConditionCuredEvent>().single.cause,
        StatusConditionCureCause.damaged,
      );
      // 解けた後の自分のターンには動ける
      expect(
        roundEvents.whereType<MoveUsedEvent>().map(
          (event) => event.attackerSide,
        ),
        [BattleSideId.player, BattleSideId.opponent],
      );
    });

    test('眠りは 1〜3 ターン続き、その間は眠りの失敗になる', () {
      for (var seed = 1; seed <= 20; seed++) {
        var state = duel(
          playerMoveIds: ['fire_drowsy', 'fire_raise_attack'],
          opponentMoveIds: ['fire_raise_attack'],
          randomSeed: seed,
        );
        state = play(
          state: state,
          playerMoveId: 'fire_drowsy',
          opponentMoveId: 'fire_raise_attack',
        );
        // 2 回目の眠気で眠りになり、同じラウンドの相手のターンから失敗が始まる
        final beforeSleep = state;
        state = play(
          state: state,
          playerMoveId: 'fire_drowsy',
          opponentMoveId: 'fire_raise_attack',
        );
        expect(
          lastRoundEvents(
            state: state,
            previous: beforeSleep,
          ).whereType<StatusConditionInflictedEvent>().single.kind,
          StatusConditionKind.sleep,
        );
        var failedCount = lastRoundEvents(state: state, previous: beforeSleep)
            .whereType<ActionFailedEvent>()
            .where((event) => event.reason == ActionFailureReason.sleep)
            .length;
        expect(failedCount, 1);
        for (var round = 0; round < 2; round++) {
          final previous = state;
          state = play(
            state: state,
            playerMoveId: 'fire_raise_attack',
            opponentMoveId: 'fire_raise_attack',
          );
          failedCount += lastRoundEvents(state: state, previous: previous)
              .whereType<ActionFailedEvent>()
              .where((event) => event.reason == ActionFailureReason.sleep)
              .length;
        }
        expect(failedCount, inInclusiveRange(1, 3));
        expect(
          state.opponent.activeMember.state.statusConditions,
          isNot(contains(StatusConditionKind.sleep)),
        );
      }
    });

    test('眠気は素早さを半分にし、眠気の中でもう一度眠気を受けると眠りに置き換わる', () {
      var state = duel(
        playerMoveIds: ['fire_drowsy'],
        opponentMoveIds: ['fire_raise_attack'],
      );
      final speedBefore = effectiveStats(
        monster: state.opponent.activeMember,
      ).speed;
      state = play(
        state: state,
        playerMoveId: 'fire_drowsy',
        opponentMoveId: 'fire_raise_attack',
      );
      expect(
        effectiveStats(monster: state.opponent.activeMember).speed,
        speedBefore ~/ 2,
      );
      state = play(
        state: state,
        playerMoveId: 'fire_drowsy',
        opponentMoveId: 'fire_raise_attack',
      );
      final inflicted = state.events
          .whereType<StatusConditionInflictedEvent>()
          .last;
      expect(inflicted.kind, StatusConditionKind.sleep);
      expect(inflicted.replacedKind, StatusConditionKind.drowsy);
      expect(
        state.opponent.activeMember.state.statusConditions,
        isNot(contains(StatusConditionKind.drowsy)),
      );
    });

    test('呪いは攻撃・防御・素早さのどれか 1 つを半分にし、重ねられない', () {
      var state = duel(
        playerMoveIds: ['fire_curse'],
        opponentMoveIds: ['fire_raise_attack'],
        randomSeed: 3,
      );
      final statsBefore = effectiveStats(monster: state.opponent.activeMember);
      state = play(
        state: state,
        playerMoveId: 'fire_curse',
        opponentMoveId: 'fire_raise_attack',
      );
      final curse = state
          .opponent
          .activeMember
          .state
          .statusConditions[StatusConditionKind.curse]!;
      final cursedStatKind = curse.cursedStatKind!;
      // 相手は攻撃を上げる技を使うため、攻撃の倍率が変わっている
      final statsAfter = effectiveStats(monster: state.opponent.activeMember);
      final expected =
          statsBefore.valueOf(statKind: cursedStatKind) *
          (cursedStatKind == StatKind.attack ? 125 : 100) ~/
          100 ~/
          2;
      expect(statsAfter.valueOf(statKind: cursedStatKind), expected);
      final inflictedCount = state.events
          .whereType<StatusConditionInflictedEvent>()
          .length;
      state = play(
        state: state,
        playerMoveId: 'fire_curse',
        opponentMoveId: 'fire_raise_attack',
      );
      expect(
        state.events.whereType<StatusConditionInflictedEvent>().length,
        inflictedCount,
      );
    });

    test('やけどは与える攻撃のダメージを半分にし、受けるダメージを 1.1 倍にする', () {
      final before = duel(
        playerMoveIds: ['fire_strong'],
        opponentMoveIds: ['fire_strong'],
      );
      BattleState withBurn({required BattleSideId side, required int stack}) {
        BattleParty withStatus(BattleParty party) => BattleParty(
          members: [
            BattleMonster(
              definition: party.activeMember.definition,
              state: party.activeMember.state.copyWith(
                statusConditions: {
                  StatusConditionKind.burn: StatusCondition(
                    kind: StatusConditionKind.burn,
                    remainingTurns: null,
                    stackCount: stack,
                    cursedStatKind: null,
                  ),
                },
              ),
            ),
          ],
          activeMemberIndex: 0,
        );
        return BattleState(
          player: side == BattleSideId.player
              ? withStatus(before.player)
              : before.player,
          opponent: side == BattleSideId.opponent
              ? withStatus(before.opponent)
              : before.opponent,
          turnNumber: before.turnNumber,
          randomState: before.randomState,
          events: before.events,
          winner: null,
          battleDate: before.battleDate,
          field: null,
        );
      }

      int playerDamage(BattleState state) => play(
        state: state,
        playerMoveId: 'fire_strong',
        opponentMoveId: 'fire_strong',
      ).events.whereType<MoveUsedEvent>().first.damage;
      final normal = playerDamage(before);
      expect(
        playerDamage(withBurn(side: BattleSideId.player, stack: 1)),
        normal ~/ 2,
      );
      expect(
        playerDamage(withBurn(side: BattleSideId.opponent, stack: 1)),
        normal * 11 ~/ 10,
      );
      expect(
        playerDamage(withBurn(side: BattleSideId.opponent, stack: 3)),
        normal * 13 ~/ 10,
      );
    });

    test('興奮は攻撃を 1.5 倍、防御を半分にする', () {
      var state = duel(
        playerMoveIds: ['fire_excite'],
        opponentMoveIds: ['fire_raise_attack'],
      );
      final statsBefore = effectiveStats(monster: state.player.activeMember);
      state = play(
        state: state,
        playerMoveId: 'fire_excite',
        opponentMoveId: 'fire_raise_attack',
      );
      final statsAfter = effectiveStats(monster: state.player.activeMember);
      expect(statsAfter.attack, statsBefore.attack * 3 ~/ 2);
      expect(statsAfter.defense, statsBefore.defense ~/ 2);
      expect(statsAfter.speed, statsBefore.speed);
    });

    test('混乱は 1/2 の確率で選んだ技の代わりに他の使える技を出す', () {
      var replacedCount = 0;
      const seedCount = 100;
      for (var seed = 1; seed <= seedCount; seed++) {
        var state = duel(
          playerMoveIds: ['fire_confuse'],
          opponentMoveIds: ['fire_raise_attack', 'fire_lower_speed'],
          randomSeed: seed,
        );
        state = play(
          state: state,
          playerMoveId: 'fire_confuse',
          opponentMoveId: 'fire_raise_attack',
        );
        final previous = state;
        state = play(
          state: state,
          playerMoveId: 'fire_confuse',
          opponentMoveId: 'fire_raise_attack',
        );
        final opponentMove = lastRoundEvents(state: state, previous: previous)
            .whereType<MoveUsedEvent>()
            .firstWhere((event) => event.attackerSide == BattleSideId.opponent);
        if (opponentMove.replacedMoveId != null) {
          replacedCount++;
          expect(opponentMove.replacedMoveId, 'fire_raise_attack');
          expect(opponentMove.moveId, 'fire_lower_speed');
          // PP は実際に出た技から減る
          expect(
            state
                .opponent
                .activeMember
                .state
                .remainingPowerPoints['fire_lower_speed'],
            lessThan(10),
          );
        }
      }
      // 1/2 の期待値は 50 回。xorshift の偏りを許す幅として ±25 にした
      expect(replacedCount, inInclusiveRange(25, 75));
    });

    test('命中率 50 の技は外れることがあり (PP は使う)、必中の技は眩暈でも外れない', () {
      var missedCount = 0;
      const seedCount = 100;
      for (var seed = 1; seed <= seedCount; seed++) {
        final state = play(
          state: duel(
            playerMoveIds: ['fire_inaccurate'],
            opponentMoveIds: ['fire_raise_attack'],
            randomSeed: seed,
          ),
          playerMoveId: 'fire_inaccurate',
          opponentMoveId: 'fire_raise_attack',
        );
        final missed = state.events.whereType<ActionFailedEvent>().where(
          (event) => event.reason == ActionFailureReason.missed,
        );
        if (missed.isNotEmpty) {
          missedCount++;
          expect(missed.single.side, BattleSideId.player);
          expect(missed.single.moveId, 'fire_inaccurate');
        }
        expect(
          state
              .player
              .activeMember
              .state
              .remainingPowerPoints['fire_inaccurate'],
          9,
        );
      }
      expect(missedCount, inInclusiveRange(25, 75));

      for (var seed = 1; seed <= 30; seed++) {
        var state = duel(
          playerMoveIds: ['fire_sure_hit', 'fire_inaccurate'],
          opponentMoveIds: ['fire_dizzy'],
          randomSeed: seed,
        );
        state = play(
          state: state,
          playerMoveId: 'fire_sure_hit',
          opponentMoveId: 'fire_dizzy',
        );
        expect(
          state.player.activeMember.state.statusConditions,
          contains(StatusConditionKind.dizzy),
        );
        expect(
          moveHitChancePercent(
            move: testMaster.moveById(moveId: 'fire_inaccurate'),
            attacker: state.player.activeMember,
          ),
          35,
        );
        state = play(
          state: state,
          playerMoveId: 'fire_sure_hit',
          opponentMoveId: 'fire_dizzy',
        );
        expect(state.events.whereType<ActionFailedEvent>(), isEmpty);
      }
    });

    test('一撃必殺は当たれば威力に関係なく相手の HP を 0 にし、PP 1 で外れやすい', () {
      var hitCount = 0;
      const seedCount = 100;
      for (var seed = 1; seed <= seedCount; seed++) {
        final state = play(
          state: duel(
            playerMoveIds: ['fire_one_hit', 'fire_strong'],
            opponentMoveIds: ['fire_strong'],
            randomSeed: seed,
          ),
          playerMoveId: 'fire_one_hit',
          opponentMoveId: 'fire_strong',
        );
        final moveUsed = state.events.whereType<MoveUsedEvent>().where(
          (event) => event.attackerSide == BattleSideId.player,
        );
        if (moveUsed.isNotEmpty) {
          hitCount++;
          expect(moveUsed.single.isOneHitKnockout, isTrue);
          expect(moveUsed.single.defenderRemainingHitPoints, 0);
          expect(state.winner, BattleSideId.player);
        }
        expect(
          state.player.activeMember.state.remainingPowerPoints['fire_one_hit'],
          0,
        );
      }
      // 命中率 30 の期待値は 30 回
      expect(hitCount, inInclusiveRange(12, 48));
    });

    test('自爆はダメージを与えた後に自分の HP を 0 にし、相打ちなら利用者の勝ち', () {
      final state = play(
        state: duel(
          playerMoveIds: ['fire_self_destruct'],
          opponentMoveIds: ['fire_strong'],
        ),
        playerMoveId: 'fire_self_destruct',
        opponentMoveId: 'fire_strong',
      );
      // 自分が速いため先に自爆する。倒れた相手には後に動く側も技を使わないため、技のログは自爆の 1 件だけ
      final moveUsed = state.events.whereType<MoveUsedEvent>().single;
      expect(moveUsed.attackerSide, BattleSideId.player);
      expect(moveUsed.selfDestructed, isTrue);
      expect(moveUsed.damage, greaterThan(0));
      expect(moveUsed.attackerRemainingHitPoints, 0);
      expect(state.player.activeMember.isFainted, isTrue);
      expect(
        state.events.whereType<MonsterFaintedEvent>().map(
          (event) => event.side,
        ),
        [BattleSideId.player],
      );
      // 相手は技を使っていないので PP も減らない
      expect(
        state.opponent.activeMember.state.remainingPowerPoints['fire_strong'],
        10,
      );
      expect(state.winner, BattleSideId.opponent);

      final mutual = play(
        state: duel(
          playerMoveIds: ['fire_self_destruct'],
          opponentMoveIds: ['fire_strong'],
          opponentHitPoints: 1,
        ),
        playerMoveId: 'fire_self_destruct',
        opponentMoveId: 'fire_strong',
      );
      expect(mutual.player.isDefeated, isTrue);
      expect(mutual.opponent.isDefeated, isTrue);
      expect(mutual.winner, BattleSideId.player);
      expect(mutual.events.whereType<MonsterFaintedEvent>(), hasLength(2));
    });

    test('先に動いた側が毒で倒れた時も、後に動く側は倒れた相手に技を使わず、倒れたログは 1 件', () {
      // 毒の持ち主 (自分) を最大 HP が小さく毒 4 重ねで 1 ターンで倒れる状態にする
      final before = duel(
        playerMoveIds: ['fire_raise_attack'],
        opponentMoveIds: ['fire_strong'],
      );
      final player = before.player.activeMember;
      final maximumHitPoints = effectiveStats(monster: player).hitPoints;
      final poisoned = BattleState(
        player: BattleParty(
          members: [
            BattleMonster(
              definition: player.definition,
              state: player.state.copyWith(
                currentHitPoints: 1,
                statusConditions: const {
                  StatusConditionKind.poison: StatusCondition(
                    kind: StatusConditionKind.poison,
                    remainingTurns: null,
                    stackCount: 1,
                    cursedStatKind: null,
                  ),
                },
              ),
            ),
          ],
          activeMemberIndex: 0,
        ),
        opponent: before.opponent,
        turnNumber: before.turnNumber,
        randomState: before.randomState,
        events: const [],
        winner: null,
        battleDate: before.battleDate,
        field: null,
      );
      expect(
        poisonDamage(maximumHitPoints: maximumHitPoints, stackCount: 1),
        greaterThanOrEqualTo(1),
      );
      final state = play(
        state: poisoned,
        playerMoveId: 'fire_raise_attack',
        opponentMoveId: 'fire_strong',
      );
      expect(
        state.events.whereType<MoveUsedEvent>().map(
          (event) => event.attackerSide,
        ),
        [BattleSideId.player],
      );
      expect(
        state.events.whereType<StatusConditionDamageEvent>(),
        hasLength(1),
      );
      expect(
        state.events.whereType<MonsterFaintedEvent>().map(
          (event) => event.side,
        ),
        [BattleSideId.player],
      );
      expect(state.winner, BattleSideId.opponent);
    });

    test('自爆・一撃必殺だけが残った時はわるあがきも選べる', () {
      final state = duel(
        playerMoveIds: ['fire_one_hit', 'fire_self_destruct'],
        opponentMoveIds: ['fire_strong'],
      );
      expect(
        () => advanceRound(
          state: state,
          playerAction: const StruggleAction(),
          opponentAction: const UseMoveAction(moveId: 'fire_strong'),
          master: testMaster,
        ),
        returnsNormally,
      );
      expect(
        () => advanceRound(
          state: duel(
            playerMoveIds: ['fire_one_hit', 'fire_strong'],
            opponentMoveIds: ['fire_strong'],
          ),
          playerAction: const StruggleAction(),
          opponentAction: const UseMoveAction(moveId: 'fire_strong'),
          master: testMaster,
        ),
        throwsArgumentError,
      );
    });

    test('先制の技は素早さに関係なく先に出る', () {
      final state = play(
        state: duel(
          playerMoveIds: ['fire_strong'],
          opponentMoveIds: ['fire_priority'],
        ),
        playerMoveId: 'fire_strong',
        opponentMoveId: 'fire_priority',
      );
      expect(
        state.events.whereType<MoveUsedEvent>().map(
          (event) => event.attackerSide,
        ),
        [BattleSideId.opponent, BattleSideId.player],
      );
    });

    test('状態を解除する技は自分の状態をすべて消す', () {
      var state = duel(
        playerMoveIds: ['fire_burn', 'fire_poison_support'],
        opponentMoveIds: ['fire_cure', 'fire_raise_attack'],
      );
      state = play(
        state: state,
        playerMoveId: 'fire_burn',
        opponentMoveId: 'fire_raise_attack',
      );
      state = play(
        state: state,
        playerMoveId: 'fire_poison_support',
        opponentMoveId: 'fire_raise_attack',
      );
      expect(state.opponent.activeMember.state.statusConditions, hasLength(2));
      final previous = state;
      state = play(
        state: state,
        playerMoveId: 'fire_burn',
        opponentMoveId: 'fire_cure',
      );
      final cured = lastRoundEvents(
        state: state,
        previous: previous,
      ).whereType<StatusConditionCuredEvent>().single;
      expect(cured.cause, StatusConditionCureCause.move);
      expect(
        cured.kinds,
        unorderedEquals([StatusConditionKind.burn, StatusConditionKind.poison]),
      );
      expect(state.opponent.activeMember.state.statusConditions, isEmpty);
      // 毒が消えた後のターンの終わりには毒のダメージを受けない
      expect(
        lastRoundEvents(
          state: state,
          previous: previous,
        ).whereType<StatusConditionDamageEvent>(),
        isEmpty,
      );
    });

    test('入れ替えのフィールドは次のラウンドから 3 ラウンドの間、ラウンドの始めに 2 つのステータスを入れ替える', () {
      var state = duel(
        playerMoveIds: ['fire_shuffle', 'fire_raise_attack'],
        opponentMoveIds: ['fire_raise_attack'],
      );
      state = play(
        state: state,
        playerMoveId: 'fire_shuffle',
        opponentMoveId: 'fire_raise_attack',
      );
      expect(state.field?.kind, FieldEffectKind.statShuffle);
      expect(state.field?.remainingRounds, 3);
      expect(state.field?.swappedStatKinds, isNull);
      expect(state.events.whereType<FieldEffectStartedEvent>(), hasLength(1));
      for (var round = 0; round < 3; round++) {
        final previous = state;
        state = play(
          state: state,
          playerMoveId: 'fire_raise_attack',
          opponentMoveId: 'fire_raise_attack',
        );
        final shuffled = lastRoundEvents(
          state: state,
          previous: previous,
        ).whereType<FieldEffectShuffledEvent>().single;
        expect(shuffled.statKinds.$1, isNot(shuffled.statKinds.$2));
        expect(state.field?.remainingRounds, 2 - round);
        final swapped = state.field!.swappedStatKinds!;
        final plain = effectiveStats(monster: state.player.activeMember);
        final onField = effectiveStats(
          monster: state.player.activeMember,
          field: state.field,
        );
        expect(
          onField.valueOf(statKind: swapped.$1),
          plain.valueOf(statKind: swapped.$2),
        );
        expect(
          onField.valueOf(statKind: swapped.$2),
          plain.valueOf(statKind: swapped.$1),
        );
      }
      final previous = state;
      state = play(
        state: state,
        playerMoveId: 'fire_raise_attack',
        opponentMoveId: 'fire_raise_attack',
      );
      expect(
        lastRoundEvents(
          state: state,
          previous: previous,
        ).whereType<FieldEffectEndedEvent>(),
        hasLength(1),
      );
      expect(state.field, isNull);
    });

    test('CPU は状態を付ける補助技を相手がその状態でない時だけ効果ありとみなし、一撃必殺・自爆を通常の攻撃に選ばない', () {
      var state = duel(
        playerMoveIds: ['fire_paralyze', 'fire_strong'],
        opponentMoveIds: ['fire_strong'],
      );
      var supportCount = 0;
      for (var seed = 1; seed <= 100; seed++) {
        final action = chooseCpuAction(
          state: duel(
            playerMoveIds: ['fire_paralyze', 'fire_strong'],
            opponentMoveIds: ['fire_strong'],
            randomSeed: seed,
          ),
          side: BattleSideId.player,
          master: testMaster,
        );
        if (action case UseMoveAction(moveId: 'fire_paralyze')) {
          supportCount++;
        }
      }
      expect(supportCount, inInclusiveRange(10, 40));
      state = play(
        state: state,
        playerMoveId: 'fire_paralyze',
        opponentMoveId: 'fire_strong',
      );
      // 相手が麻痺の間 (このラウンドの始め) は麻痺の技を選ばない
      expect(
        state.opponent.activeMember.state.statusConditions,
        isNot(contains(StatusConditionKind.paralysis)),
      );

      var oneHitCount = 0;
      for (var seed = 1; seed <= 100; seed++) {
        final action = chooseCpuAction(
          state: duel(
            playerMoveIds: [
              'fire_one_hit',
              'fire_self_destruct',
              'fire_strong',
            ],
            opponentMoveIds: ['fire_strong'],
            randomSeed: seed,
          ),
          side: BattleSideId.player,
          master: testMaster,
        );
        switch (action) {
          case UseMoveAction(moveId: 'fire_one_hit'):
            oneHitCount++;
          case UseMoveAction(moveId: 'fire_strong'):
            break;
          default:
            fail('HP が満タンの時に自爆・わるあがきを選んだ: $action');
        }
      }
      expect(oneHitCount, inInclusiveRange(10, 40));
    });

    test('CPU は通常の攻撃技が無く一撃必殺・自爆だけが残った時、確率で選ばなければわるあがきにし、HP が満タンなら自爆しない', () {
      var oneHitCount = 0;
      var struggleCount = 0;
      for (final moveIds in [
        ['fire_one_hit', 'fire_self_destruct'],
        ['fire_self_destruct'],
        ['fire_one_hit', 'fire_raise_attack'],
      ]) {
        for (var seed = 1; seed <= 30; seed++) {
          final state = duel(
            playerMoveIds: moveIds,
            opponentMoveIds: ['fire_strong'],
            randomSeed: seed,
          );
          final action = chooseCpuAction(
            state: state,
            side: BattleSideId.player,
            master: testMaster,
          );
          switch (action) {
            case UseMoveAction(moveId: 'fire_one_hit'):
              oneHitCount++;
            case UseMoveAction(moveId: 'fire_raise_attack'):
              break;
            case StruggleAction():
              struggleCount++;
            default:
              fail('HP が満タンの時に自爆を選んだ: $moveIds seed=$seed: $action');
          }
          // 選んだ行動は advanceRound の検証を通る
          expect(
            () => advanceRound(
              state: state,
              playerAction: action,
              opponentAction: const UseMoveAction(moveId: 'fire_strong'),
              master: testMaster,
            ),
            returnsNormally,
            reason: '$moveIds seed=$seed: $action',
          );
        }
      }
      expect(oneHitCount, greaterThan(0));
      expect(struggleCount, greaterThan(0));
    });

    test('麻痺と混乱が重なり、補助技が攻撃技に置き換わった時も麻痺で失敗する', () {
      final before = duel(
        playerMoveIds: ['fire_raise_attack'],
        opponentMoveIds: ['fire_raise_attack', 'fire_strong'],
      );
      BattleState withStatuses({required int seed}) {
        final opponent = before.opponent.activeMember;
        return BattleState(
          player: before.player,
          opponent: BattleParty(
            members: [
              BattleMonster(
                definition: opponent.definition,
                state: opponent.state.copyWith(
                  statusConditions: const {
                    StatusConditionKind.paralysis: StatusCondition(
                      kind: StatusConditionKind.paralysis,
                      remainingTurns: 5,
                      stackCount: 1,
                      cursedStatKind: null,
                    ),
                    StatusConditionKind.confusion: StatusCondition(
                      kind: StatusConditionKind.confusion,
                      remainingTurns: 5,
                      stackCount: 1,
                      cursedStatKind: null,
                    ),
                  },
                ),
              ),
            ],
            activeMemberIndex: 0,
          ),
          turnNumber: before.turnNumber,
          randomState: seed,
          events: const [],
          winner: null,
          battleDate: before.battleDate,
          field: null,
        );
      }

      var paralyzedCount = 0;
      for (var seed = 1; seed <= 60; seed++) {
        final state = play(
          state: withStatuses(seed: seed * 0x9E3779B9 & 0xFFFFFFFF),
          playerMoveId: 'fire_raise_attack',
          opponentMoveId: 'fire_raise_attack',
        );
        // 相手が攻撃技を出すことはない (置き換わった攻撃技は麻痺で失敗する)
        expect(
          state.events.whereType<MoveUsedEvent>().where(
            (event) =>
                event.attackerSide == BattleSideId.opponent &&
                event.moveId == 'fire_strong',
          ),
          isEmpty,
          reason: 'seed=$seed',
        );
        final failed = state.events.whereType<ActionFailedEvent>().where(
          (event) => event.reason == ActionFailureReason.paralysis,
        );
        if (failed.isNotEmpty) {
          paralyzedCount++;
          expect(failed.single.moveId, 'fire_strong');
        }
      }
      // 混乱で置き換わるのは 1/2 なので、半分ほどが麻痺で失敗する
      expect(paralyzedCount, inInclusiveRange(15, 45));
    });

    test('続いている入れ替えのフィールドを同じ技で始め直しても、そのラウンドの入れ替えは保たれる', () {
      var state = duel(
        playerMoveIds: ['fire_shuffle', 'fire_raise_attack'],
        opponentMoveIds: ['fire_raise_attack'],
      );
      state = play(
        state: state,
        playerMoveId: 'fire_shuffle',
        opponentMoveId: 'fire_raise_attack',
      );
      state = play(
        state: state,
        playerMoveId: 'fire_raise_attack',
        opponentMoveId: 'fire_raise_attack',
      );
      final swappedBefore = state.field!.swappedStatKinds;
      expect(swappedBefore, isNotNull);
      state = play(
        state: state,
        playerMoveId: 'fire_shuffle',
        opponentMoveId: 'fire_raise_attack',
      );
      expect(state.field?.remainingRounds, 3);
      // このラウンドの始めに選び直した組のまま (始め直しで消えない)
      expect(state.field?.swappedStatKinds, isNotNull);
      expect(state.events.whereType<FieldEffectShuffledEvent>().length, 2);
    });
  });

  group('自分からの交代と交換不可 (#239)', () {
    /// [member] の残りの HP を [hitPoints] にしたモンスター。null なら [member] のまま (満タン)。
    BattleMonster withHitPoints({
      required BattleMonster member,
      required int? hitPoints,
    }) => hitPoints == null
        ? member
        : BattleMonster(
            definition: member.definition,
            state: member.state.copyWith(currentHitPoints: hitPoints),
          );

    /// 利用者は素早さ 50 の 3 体 (player_1〜3)、相手は素早さ 100 の 1 体。[playerHitPoints] は手持ちの位置ごとの残りの HP (無ければ満タン)。
    BattleState startSwitchBattle({
      Map<int, int> playerHitPoints = const {},
      int? opponentHitPoints,
    }) => startBattle(
      playerMembers: [
        for (final index in [0, 1, 2])
          withHitPoints(
            member: prepare(
              definition: testDefinition(
                id: 'player_${index + 1}',
                elementTypeId: 'fire',
                moveIds: ['fire_strong', 'fire_raise_attack'],
                speed: 50,
              ),
            ),
            hitPoints: playerHitPoints[index],
          ),
      ],
      opponentMembers: [
        withHitPoints(
          member: prepare(
            definition: testDefinition(
              id: 'opponent_1',
              elementTypeId: 'grass',
              moveIds: [
                'grass_strong',
                'fire_priority',
                'fire_block_switch',
                'fire_curse',
              ],
              speed: 100,
            ),
          ),
          hitPoints: opponentHitPoints,
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
    );

    test('交代は先制の技より先に行われ、交代して出たモンスターが相手の技を受ける', () {
      final state = startSwitchBattle();
      final next = advanceRound(
        state: state,
        playerAction: const SwitchMonsterAction(memberIndex: 1),
        opponentAction: const UseMoveAction(moveId: 'fire_priority'),
        master: testMaster,
      );

      final switched = next.events.first as MonsterSwitchedInEvent;
      expect(switched.turnNumber, 1);
      expect(switched.side, BattleSideId.player);
      expect(switched.monsterId, 'player_2');
      expect(switched.withdrawnMonsterId, 'player_1');
      final moveUsed = next.events[1] as MoveUsedEvent;
      expect(moveUsed.turnNumber, 2);
      expect(moveUsed.attackerSide, BattleSideId.opponent);
      expect(next.player.activeMemberIndex, 1);
      expect(
        next.player.members[1].state.currentHitPoints,
        lessThan(state.player.members[1].state.currentHitPoints),
      );
      expect(
        next.player.members[0].state.currentHitPoints,
        state.player.members[0].state.currentHitPoints,
      );
    });

    test('場にいる・倒れている・手持ちに無い位置への交代は拒まれ、倒れていない控えだけが候補になる', () {
      final state = startSwitchBattle(playerHitPoints: {1: 0});
      expect(switchableMemberIndices(party: state.player), [2]);
      for (final memberIndex in [0, 1, 3]) {
        expect(
          () => advanceRound(
            state: state,
            playerAction: SwitchMonsterAction(memberIndex: memberIndex),
            opponentAction: const UseMoveAction(moveId: 'grass_strong'),
            master: testMaster,
          ),
          throwsArgumentError,
          reason: 'memberIndex=$memberIndex',
        );
      }
      expect(
        () => advanceRound(
          state: state,
          playerAction: const SwitchMonsterAction(memberIndex: 2),
          opponentAction: const UseMoveAction(moveId: 'grass_strong'),
          master: testMaster,
        ),
        returnsNormally,
      );
    });

    test('場を離れるとステータスの倍率は等倍に戻り、状態は残る', () {
      var state = advanceRound(
        state: startSwitchBattle(),
        playerAction: const UseMoveAction(moveId: 'fire_raise_attack'),
        opponentAction: const UseMoveAction(moveId: 'fire_curse'),
        master: testMaster,
      );
      expect(
        statModifierPercentOf(
          monster: state.player.activeMember,
          statKind: StatKind.attack,
        ),
        greaterThan(100),
      );
      expect(
        state.player.activeMember.state.statusConditions,
        contains(StatusConditionKind.curse),
      );
      state = advanceRound(
        state: state,
        playerAction: const SwitchMonsterAction(memberIndex: 1),
        opponentAction: const UseMoveAction(moveId: 'fire_curse'),
        master: testMaster,
      );
      final withdrawn = state.player.members[0];
      expect(
        statModifierPercentOf(monster: withdrawn, statKind: StatKind.attack),
        100,
      );
      expect(
        withdrawn.state.statusConditions,
        contains(StatusConditionKind.curse),
      );
    });

    test('交換不可の間は交代が拒まれ、残りのターンが 0 になって消えると交代できる', () {
      var state = advanceRound(
        state: startSwitchBattle(),
        playerAction: const UseMoveAction(moveId: 'fire_raise_attack'),
        opponentAction: const UseMoveAction(moveId: 'fire_block_switch'),
        master: testMaster,
      );
      expect(
        state.events.whereType<StatusConditionInflictedEvent>().single.kind,
        StatusConditionKind.switchBlocked,
      );
      var blockedRounds = 0;
      while (isSwitchBlocked(party: state.player)) {
        final blockedState = state;
        expect(
          () => advanceRound(
            state: blockedState,
            playerAction: const SwitchMonsterAction(memberIndex: 1),
            opponentAction: const UseMoveAction(moveId: 'fire_curse'),
            master: testMaster,
          ),
          throwsArgumentError,
        );
        state = advanceRound(
          state: state,
          playerAction: const UseMoveAction(moveId: 'fire_raise_attack'),
          opponentAction: const UseMoveAction(moveId: 'fire_curse'),
          master: testMaster,
        );
        blockedRounds++;
        expect(blockedRounds, lessThanOrEqualTo(3));
      }
      // 相手が先に動いて付けたため、付いたラウンドの自分のターンの終わりで 1 減り、残りの 2 ラウンドだけ封じる
      expect(blockedRounds, 2);
      expect(
        state.events.whereType<StatusConditionCuredEvent>().last.kinds,
        [StatusConditionKind.switchBlocked],
      );
      final next = advanceRound(
        state: state,
        playerAction: const SwitchMonsterAction(memberIndex: 1),
        opponentAction: const UseMoveAction(moveId: 'fire_curse'),
        master: testMaster,
      );
      expect(next.player.activeMemberIndex, 1);
    });

    test('交換不可でも、倒れた時の交代は止まらない', () {
      var state = advanceRound(
        state: startSwitchBattle(playerHitPoints: {0: 1}),
        playerAction: const UseMoveAction(moveId: 'fire_raise_attack'),
        opponentAction: const UseMoveAction(moveId: 'fire_block_switch'),
        master: testMaster,
      );
      expect(isSwitchBlocked(party: state.player), isTrue);
      state = advanceRound(
        state: state,
        playerAction: const UseMoveAction(moveId: 'fire_raise_attack'),
        opponentAction: const UseMoveAction(moveId: 'grass_strong'),
        master: testMaster,
      );
      final switched = state.events.whereType<MonsterSwitchedInEvent>().single;
      expect(switched.monsterId, 'player_2');
      expect(switched.withdrawnMonsterId, isNull);
      expect(state.player.activeMemberIndex, 1);
    });

    test('交代で場に出たモンスターだけがレベルアップの対象になる (先頭→3 体目→倒れて先頭に戻る)', () {
      var state = advanceRound(
        state: startSwitchBattle(playerHitPoints: {2: 1}, opponentHitPoints: 1),
        playerAction: const SwitchMonsterAction(memberIndex: 2),
        opponentAction: const UseMoveAction(moveId: 'grass_strong'),
        master: testMaster,
      );
      // 3 体目は相手の技で倒れ、倒れていない最も前の先頭が戻る
      expect(
        state.events.whereType<MonsterSwitchedInEvent>().map(
          (event) => (event.monsterId, event.withdrawnMonsterId),
        ),
        [('player_3', 'player_1'), ('player_1', null)],
      );
      expect(state.player.activeMemberIndex, 0);
      state = advanceRound(
        state: state,
        playerAction: const UseMoveAction(moveId: 'fire_strong'),
        opponentAction: const UseMoveAction(moveId: 'fire_curse'),
        master: testMaster,
      );
      expect(state.winner, BattleSideId.player);
      expect(state.player.members.map((member) => member.state.level), [
        51,
        50,
        51,
      ]);
      expect(
        state.events.whereType<LevelUpEvent>().where(
          (event) => event.side == BattleSideId.player,
        ).map((event) => event.monsterId),
        ['player_1', 'player_3'],
      );
    });
  });
}
