import 'dart:convert';
import 'dart:io';
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
import 'package:snapmon/domain/monster/stat_calculation.dart';

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
      elementTypeID: 'fire',
      power: 60,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
    ),
    Move(
      id: 'grass_strong',
      displayName: 'つよいくさ',
      elementTypeID: 'grass',
      power: 60,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
    ),
    Move(
      id: 'grass_weak',
      displayName: 'よわいくさ',
      elementTypeID: 'grass',
      power: 20,
      powerPoints: 2,
      category: MoveCategory.attack,
      effectID: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
    ),
    Move(
      id: 'fire_last',
      displayName: 'あとだしほのお',
      elementTypeID: 'fire',
      power: 60,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 60,
      powerPoints: 2,
      category: MoveCategory.attack,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 60,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectID: 'none',
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
        elementTypeID: 'fire',
        power: 0,
        powerPoints: 10,
        category: MoveCategory.support,
        effectID: 'none',
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
    // 版 11 (#257) の、ステータス・状態の変化を追加効果に持つ攻撃技
    const Move(
      id: 'fire_block_switch_attack',
      displayName: 'こうたいふうじ',
      elementTypeID: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
      learnableLevelMinimum: 5,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {},
        selfHitPointsRecovery: null,
        opponentStatusConditions: [
          StatusConditionInfliction(
            kind: StatusConditionKind.switchBlocked,
            chancePercent: 100,
          ),
        ],
        summary: '相手を交代できなくする',
        rule: '当たると相手を交換不可にする',
      ),
    ),
    const Move(
      id: 'fire_lower_defense_attack',
      displayName: 'ぼうぎょさげ',
      elementTypeID: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
      learnableLevelMinimum: 5,
      learnableLevelMaximum: 999,
      specialEffect: MoveSpecialEffect(
        power: null,
        selfStatChanges: {},
        opponentStatChanges: {StatKind.defense: '-25'},
        selfHitPointsRecovery: null,
        summary: '相手の防御を下げる',
        rule: '当たると相手の防御を下げる',
      ),
    ),
    const Move(
      id: 'fire_excite',
      displayName: 'こうふん',
      elementTypeID: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
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
      elementTypeID: 'poison',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
    ),
    const Move(
      id: 'fire_cure',
      displayName: 'かいじょ',
      elementTypeID: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 0,
      powerPoints: 10,
      category: MoveCategory.support,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 200,
      powerPoints: 5,
      category: MoveCategory.attack,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 0,
      powerPoints: 1,
      category: MoveCategory.attack,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
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
      elementTypeID: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
      learnableLevelMinimum: 1,
      learnableLevelMaximum: 999,
      specialEffect: null,
      priority: 1,
    ),
    const Move(
      id: 'fire_inaccurate',
      displayName: 'はずれやすい',
      elementTypeID: 'fire',
      power: 40,
      powerPoints: 10,
      category: MoveCategory.attack,
      effectID: 'none',
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
  required String elementTypeID,
  required List<String> moveIDs,
  required int speed,
  int hitPoints = 80,
  int accuracyBaseStat = 120,
}) => MonsterDefinition(
  id: id,
  sourcePhotoReference: 'users/test/photos/$id.jpg',
  name: id,
  encyclopediaText: '',
  elementTypeIDs: [elementTypeID],
  learnset: [
    for (final moveID in moveIDs) LearnsetEntry(moveID: moveID, unlockLevel: 1),
  ],
  // 命中は既定で種族値・個体値の最大 (計算した命中が 100) にし、技の命中率だけで当たり外れが決まるようにする。
  // 命中の効き目は「使う側の命中を技の命中率に掛ける」のテストで、[accuracyBaseStat] を下げて確かめる
  baseStats: MonsterStats(
    hitPoints: hitPoints,
    attack: 80,
    defense: 80,
    speed: speed,
    accuracy: accuracyBaseStat,
  ),
  individualValues: const MonsterStats(
    hitPoints: 0,
    attack: 0,
    defense: 0,
    speed: 0,
    accuracy: individualValueMaximum,
  ),
  statCalculationVersion: 1,
  masterVersion: 1,
);

BattleMonster prepare({
  required MonsterDefinition definition,
  int level = 50,
  List<String> actionCardMoveIDs = const [],
}) => prepareBattleMonster(
  definition: definition,
  level: level,
  experience: 0,
  actionCardMoveIDs: actionCardMoveIDs,
  master: testMaster,
  maximumHitPointsPercent: 100,
);

/// 両陣営とも CPU の規則で行動させ、決着までのターンを進めた状態を返す。
BattleState playUntilFinished({required BattleState state}) {
  var current = state;
  while (current.winner == null) {
    current = advanceRound(
      state: current,
      playerAction: chooseCpuAction(
        state: current,
        side: BattleSideID.player,
        master: testMaster,
      ),
      opponentAction: chooseCpuAction(
        state: current,
        side: BattleSideID.opponent,
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
        moveElementTypeID: 'fire',
        defenderElementTypeIDs: ['grass', 'grass'],
        master: testMaster,
      ),
      4,
    );

    final state = startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeID: 'fire',
            moveIDs: ['fire_strong'],
            speed: 100,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeID: 'fire',
            moveIDs: ['grass_strong'],
            speed: 50,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );
    final grassTarget = startBattle(
      playerMembers: state.player.members,
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeID: 'grass',
            moveIDs: ['grass_strong'],
            speed: 50,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );
    MoveUsedEvent firstHit(BattleState battleState) => advanceRound(
      state: battleState,
      playerAction: const UseMoveAction(moveID: 'fire_strong'),
      opponentAction: const UseMoveAction(moveID: 'grass_strong'),
      master: testMaster,
    ).events.whereType<MoveUsedEvent>().first;
    expect(firstHit(grassTarget).typeMultiplier, 2);
    expect(firstHit(grassTarget).damage, greaterThan(firstHit(state).damage));
  });

  test('技のボタンに出す相性の倍率は、攻撃技 (自爆を含む) だけ相手の属性で決まり、補助技と一撃必殺は null', () {
    final grassDefender = prepare(
      definition: testDefinition(
        id: 'opponent',
        elementTypeID: 'grass',
        moveIDs: ['grass_strong'],
        speed: 50,
      ),
    );
    final fireDefender = prepare(
      definition: testDefinition(
        id: 'opponent',
        elementTypeID: 'fire',
        moveIDs: ['grass_strong'],
        speed: 50,
      ),
    );
    double? multiplierOf({
      required String moveID,
      required BattleMonster defender,
    }) => moveTypeMultiplierAgainst(
      move: testMaster.moveByID(moveID: moveID),
      defender: defender,
      master: testMaster,
    );
    expect(multiplierOf(moveID: 'fire_strong', defender: grassDefender), 2);
    expect(multiplierOf(moveID: 'grass_strong', defender: fireDefender), 0.5);
    expect(multiplierOf(moveID: 'fire_strong', defender: fireDefender), 1);
    // 自爆はダメージに相性が掛かるため出す
    expect(
      multiplierOf(moveID: 'fire_self_destruct', defender: grassDefender),
      2,
    );
    // 同じ炎の技でも、ダメージの無い補助技と HP を 0 にする一撃必殺は相性が効かない
    expect(
      multiplierOf(moveID: 'fire_lower_defense', defender: grassDefender),
      isNull,
    );
    expect(
      multiplierOf(moveID: 'fire_one_hit', defender: grassDefender),
      isNull,
    );
  });

  test('CPU は相性の倍率が最大の技を選ぶ (倍率が同じなら威力が高い技)', () {
    final state = startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeID: 'grass',
            moveIDs: ['grass_weak', 'fire_strong'],
            speed: 50,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeID: 'fire',
            moveIDs: ['grass_weak', 'grass_strong'],
            speed: 50,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );
    final playerAction = chooseCpuAction(
      state: state,
      side: BattleSideID.player,
      master: testMaster,
    );
    expect((playerAction as UseMoveAction).moveID, 'fire_strong');
    final opponentAction = chooseCpuAction(
      state: state,
      side: BattleSideID.opponent,
      master: testMaster,
    );
    expect((opponentAction as UseMoveAction).moveID, 'grass_strong');
  });

  test('素早さが高い方が先に動く', () {
    BattleSideID firstAttacker({
      required int playerSpeed,
      required int opponentSpeed,
    }) => advanceRound(
      state: startBattle(
        playerMembers: [
          prepare(
            definition: testDefinition(
              id: 'player',
              elementTypeID: 'fire',
              moveIDs: ['fire_strong'],
              speed: playerSpeed,
            ),
          ),
        ],
        opponentMembers: [
          prepare(
            definition: testDefinition(
              id: 'opponent',
              elementTypeID: 'fire',
              moveIDs: ['fire_strong'],
              speed: opponentSpeed,
            ),
          ),
        ],
        randomSeed: 1,
        battleDate: testBattleDate,
        opponentDamagePercent: 100,
      ),
      playerAction: const UseMoveAction(moveID: 'fire_strong'),
      opponentAction: const UseMoveAction(moveID: 'fire_strong'),
      master: testMaster,
    ).events.whereType<MoveUsedEvent>().first.attackerSide;

    expect(
      firstAttacker(playerSpeed: 100, opponentSpeed: 50),
      BattleSideID.player,
    );
    expect(
      firstAttacker(playerSpeed: 50, opponentSpeed: 100),
      BattleSideID.opponent,
    );
  });

  test('PP が尽きた技は選べず、使える技が無くなるとわるあがきになる', () {
    var state = startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeID: 'fire',
            moveIDs: ['grass_weak'],
            speed: 100,
            hitPoints: 250,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeID: 'fire',
            moveIDs: ['grass_weak'],
            speed: 50,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );
    expect(
      () => advanceRound(
        state: state,
        playerAction: const StruggleAction(),
        opponentAction: const UseMoveAction(moveID: 'grass_weak'),
        master: testMaster,
      ),
      throwsArgumentError,
    );
    for (var turn = 0; turn < 2; turn++) {
      state = advanceRound(
        state: state,
        playerAction: const UseMoveAction(moveID: 'grass_weak'),
        opponentAction: const UseMoveAction(moveID: 'grass_weak'),
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
        playerAction: const UseMoveAction(moveID: 'grass_weak'),
        opponentAction: const StruggleAction(),
        master: testMaster,
      ),
      throwsArgumentError,
    );
    expect(
      chooseCpuAction(
        state: state,
        side: BattleSideID.opponent,
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
    expect(struggleEvents.map((event) => event.moveID), [null, null]);
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
              elementTypeID: 'fire',
              moveIDs: ['fire_strong'],
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
              elementTypeID: 'grass',
              moveIDs: ['grass_strong'],
              speed: 50,
            ),
          ),
      ],
      randomSeed: randomSeed,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );

    test('3 体すべて倒れた側が負け、勝敗を問わず場に出た手持ちのレベルが 1 上がる (上限 999)', () {
      final finished = playUntilFinished(
        state: startThreeOnThree(randomSeed: 7, leadPlayerLevel: 999),
      );

      expect(finished.winner, BattleSideID.player);
      expect(finished.opponent.isDefeated, isTrue);
      expect(
        finished.events.whereType<MonsterSwitchedInEvent>().map(
          (event) => event.monsterID,
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
          playerAction: const UseMoveAction(moveID: 'fire_strong'),
          opponentAction: const UseMoveAction(moveID: 'grass_strong'),
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
    BattleSideID firstAttacker({required int randomSeed}) => advanceRound(
      state: startBattle(
        playerMembers: [
          prepare(
            definition: testDefinition(
              id: 'player',
              elementTypeID: 'fire',
              moveIDs: ['fire_strong'],
              speed: 80,
            ),
          ),
        ],
        opponentMembers: [
          prepare(
            definition: testDefinition(
              id: 'opponent',
              elementTypeID: 'fire',
              moveIDs: ['fire_strong'],
              speed: 80,
            ),
          ),
        ],
        randomSeed: randomSeed,
        battleDate: testBattleDate,
        opponentDamagePercent: 100,
      ),
      playerAction: const UseMoveAction(moveID: 'fire_strong'),
      opponentAction: const UseMoveAction(moveID: 'fire_strong'),
      master: testMaster,
    ).events.whereType<MoveUsedEvent>().first.attackerSide;

    final firstAttackers = [
      for (var randomSeed = 1; randomSeed <= 20; randomSeed++)
        firstAttacker(randomSeed: randomSeed),
    ];
    expect(firstAttackers.toSet(), BattleSideID.values.toSet());
    expect([
      for (var randomSeed = 1; randomSeed <= 20; randomSeed++)
        firstAttacker(randomSeed: randomSeed),
    ], firstAttackers);
  });

  test('攻撃技の追加効果のステータスの変化と交換不可は、ダメージと一緒に相手に付く (#257)', () {
    var state = startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeID: 'fire',
            moveIDs: ['fire_lower_defense_attack', 'fire_block_switch_attack'],
            speed: 100,
          ),
        ),
      ],
      opponentMembers: [
        for (final index in [1, 2])
          prepare(
            definition: testDefinition(
              id: 'opponent_$index',
              elementTypeID: 'fire',
              moveIDs: ['fire_priority'],
              speed: 50,
            ),
          ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );
    final opponentHitPoints =
        state.opponent.activeMember.state.currentHitPoints;
    state = advanceRound(
      state: state,
      playerAction: const UseMoveAction(moveID: 'fire_lower_defense_attack'),
      opponentAction: const UseMoveAction(moveID: 'fire_priority'),
      master: testMaster,
    );
    expect(
      state.opponent.activeMember.state.currentHitPoints,
      lessThan(opponentHitPoints),
    );
    expect(
      statModifierPercentOf(
        monster: state.opponent.activeMember,
        statKind: StatKind.defense,
      ),
      lessThan(100),
    );

    state = advanceRound(
      state: state,
      playerAction: const UseMoveAction(moveID: 'fire_block_switch_attack'),
      opponentAction: const UseMoveAction(moveID: 'fire_priority'),
      master: testMaster,
    );
    expect(isSwitchBlocked(party: state.opponent), isTrue);
    final blockedState = state;
    expect(
      () => advanceRound(
        state: blockedState,
        playerAction: const UseMoveAction(moveID: 'fire_lower_defense_attack'),
        opponentAction: const SwitchMonsterAction(memberIndex: 1),
        master: testMaster,
      ),
      throwsArgumentError,
    );
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
            elementTypeID: 'fire',
            power: 0,
            powerPoints: 5,
            category: MoveCategory.support,
            effectID: 'none',
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
            elementTypeID: 'fire',
            moveIDs: ['support_only'],
            speed: id == 'player' ? 100 : 50,
          ),
          level: 50,
          experience: 0,
          actionCardMoveIDs: const [],
          master: supportOnlyMaster,
          maximumHitPointsPercent: 100,
        );
    var state = startBattle(
      playerMembers: [supportOnlyMonster(id: 'player')],
      opponentMembers: [supportOnlyMonster(id: 'opponent')],
      randomSeed: 1,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );
    while (state.winner == null) {
      state = advanceRound(
        state: state,
        playerAction: chooseCpuAction(
          state: state,
          side: BattleSideID.player,
          master: supportOnlyMaster,
        ),
        opponentAction: chooseCpuAction(
          state: state,
          side: BattleSideID.opponent,
          master: supportOnlyMaster,
        ),
        master: supportOnlyMaster,
      );
      expect(state.turnNumber, lessThan(1000), reason: 'バトルが終わらない');
    }
    expect(state.winner, isNotNull);
  });

  group('技の特殊効果', () {
    /// 速さ [playerSpeed] の自分と速さ [opponentSpeed] の相手が、それぞれ [playerMoveID]・[opponentMoveID] だけを持つバトル。
    BattleState startDuel({
      required String playerMoveID,
      required String opponentMoveID,
      required int playerSpeed,
      required int opponentSpeed,
    }) => startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeID: 'fire',
            moveIDs: [playerMoveID],
            speed: playerSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeID: 'fire',
            moveIDs: [opponentMoveID],
            speed: opponentSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: 1,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );

    /// [state] から両陣営が [playerMoveID]・[opponentMoveID] を使って 1 ターン進め、陣営ごとの技のログを返す。
    Map<BattleSideID, MoveUsedEvent> playTurn({
      required BattleState state,
      required String playerMoveID,
      required String opponentMoveID,
    }) => {
      for (final event in advanceRound(
        state: state,
        playerAction: UseMoveAction(moveID: playerMoveID),
        opponentAction: UseMoveAction(moveID: opponentMoveID),
        master: testMaster,
      ).events.skip(state.events.length).whereType<MoveUsedEvent>())
        event.attackerSide: event,
    };

    test('後に動くと強い技は、そのターンに後に行動した側だけ倍率が最大になり、ダメージが増える', () {
      final events = playTurn(
        state: startDuel(
          playerMoveID: 'fire_last',
          opponentMoveID: 'fire_last',
          playerSpeed: 50,
          opponentSpeed: 100,
        ),
        playerMoveID: 'fire_last',
        opponentMoveID: 'fire_last',
      );
      expect(events[BattleSideID.opponent]!.specialEffect!.powerPercent, 100);
      expect(events[BattleSideID.player]!.specialEffect!.powerPercent, 200);
      // 威力 2 倍は乱数幅 (85〜100%) より大きいため、同じ条件の相手より必ず多く与える
      expect(
        events[BattleSideID.player]!.damage,
        greaterThan(events[BattleSideID.opponent]!.damage),
      );
    });

    test('残り PP が少ないほど強い技は、使う前の残りで計算する (PP 2 の技の 2 回目で最大)', () {
      final firstState = startDuel(
        playerMoveID: 'fire_last_resort',
        opponentMoveID: 'fire_strong',
        playerSpeed: 100,
        opponentSpeed: 50,
      );
      expect(
        playTurn(
          state: firstState,
          playerMoveID: 'fire_last_resort',
          opponentMoveID: 'fire_strong',
        )[BattleSideID.player]!.specialEffect!.powerPercent,
        100,
      );
      expect(
        playTurn(
          state: advanceRound(
            state: firstState,
            playerAction: const UseMoveAction(moveID: 'fire_last_resort'),
            opponentAction: const UseMoveAction(moveID: 'fire_strong'),
            master: testMaster,
          ),
          playerMoveID: 'fire_last_resort',
          opponentMoveID: 'fire_strong',
        )[BattleSideID.player]!.specialEffect!.powerPercent,
        200,
      );
    });

    test('自分の HP が減っているほど強い技は、同じターンに先に受けたダメージを倍率に入れる', () {
      final events = playTurn(
        state: startDuel(
          playerMoveID: 'fire_desperate',
          opponentMoveID: 'fire_strong',
          playerSpeed: 50,
          opponentSpeed: 100,
        ),
        playerMoveID: 'fire_desperate',
        opponentMoveID: 'fire_strong',
      );
      expect(events[BattleSideID.opponent]!.damage, greaterThan(0));
      expect(
        events[BattleSideID.player]!.specialEffect!.powerPercent,
        greaterThan(100),
      );
    });

    test('特殊効果の無い技のログは特殊効果を持たない', () {
      final events = playTurn(
        state: startDuel(
          playerMoveID: 'fire_strong',
          opponentMoveID: 'fire_strong',
          playerSpeed: 100,
          opponentSpeed: 50,
        ),
        playerMoveID: 'fire_strong',
        opponentMoveID: 'fire_strong',
      );
      expect(events[BattleSideID.player]!.specialEffect, isNull);
    });
  });

  group('補助技', () {
    /// 自分 (速さ [playerSpeed]、技 [playerMoveIDs]) と相手 (速さ [opponentSpeed]、技 [opponentMoveIDs]) の 1 対 1 のバトル。
    BattleState startDuel({
      required List<String> playerMoveIDs,
      required List<String> opponentMoveIDs,
      required int playerSpeed,
      required int opponentSpeed,
      int randomSeed = 1,
    }) => startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeID: 'fire',
            moveIDs: playerMoveIDs,
            speed: playerSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeID: 'fire',
            moveIDs: opponentMoveIDs,
            speed: opponentSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      randomSeed: randomSeed,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );

    /// [state] から両陣営が [playerMoveID]・[opponentMoveID] を使って 1 ターン進めた状態を返す。
    BattleState playTurn({
      required BattleState state,
      required String playerMoveID,
      required String opponentMoveID,
    }) => advanceRound(
      state: state,
      playerAction: UseMoveAction(moveID: playerMoveID),
      opponentAction: UseMoveAction(moveID: opponentMoveID),
      master: testMaster,
    );

    /// [state] の最後のターンの、[side] が使った技のログ。
    MoveUsedEvent lastMoveOf({
      required BattleState state,
      required BattleSideID side,
    }) => state.events.whereType<MoveUsedEvent>().lastWhere(
      (event) => event.attackerSide == side,
    );

    test('相手の防御を下げる技はダメージを与えず、倍率を 25 ずつ下げ、下限 50 で止まる', () {
      var state = startDuel(
        playerMoveIDs: ['fire_lower_defense'],
        opponentMoveIDs: ['grass_weak'],
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
          playerMoveID: 'fire_lower_defense',
          opponentMoveID: 'grass_weak',
        );
        final event = lastMoveOf(state: state, side: BattleSideID.player);
        expect(event.damage, 0);
        expect(event.statModifierChanges, hasLength(1));
        expect(event.statModifierChanges.single.side, BattleSideID.opponent);
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
        playerAction: const UseMoveAction(moveID: 'fire_lower_defense'),
        opponentAction: const StruggleAction(),
        master: testMaster,
      );
      final capped = lastMoveOf(state: state, side: BattleSideID.player);
      expect(capped.statModifierChanges.single.previousPercent, 50);
      expect(capped.statModifierChanges.single.newPercent, 50);
    });

    test('下げた防御はダメージ式に入り、同じ乱数なら下げる前より多く与える', () {
      final before = startDuel(
        playerMoveIDs: ['fire_strong', 'fire_lower_defense'],
        opponentMoveIDs: ['fire_strong'],
        playerSpeed: 100,
        opponentSpeed: 50,
      );
      final lowered = playTurn(
        state: before,
        playerMoveID: 'fire_lower_defense',
        opponentMoveID: 'fire_strong',
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
        opponentDamagePercent: 100,
      );
      final beforeWithSameHitPoints = BattleState(
        player: lowered.player,
        opponent: BattleParty(
          members: [
            BattleMonster(
              definition: lowered.opponent.activeMember.definition,
              maximumHitPointsPercent:
                  lowered.opponent.activeMember.maximumHitPointsPercent,
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
        opponentDamagePercent: 100,
      );
      int damageOf({required BattleState state}) => lastMoveOf(
        state: playTurn(
          state: state,
          playerMoveID: 'fire_strong',
          opponentMoveID: 'fire_strong',
        ),
        side: BattleSideID.player,
      ).damage;
      expect(
        damageOf(state: loweredWithSameRandom),
        greaterThan(damageOf(state: beforeWithSameHitPoints)),
      );
    });

    test('自分の攻撃を上げる技は、倍率を掛けた攻撃を返す', () {
      final state = playTurn(
        state: startDuel(
          playerMoveIDs: ['fire_raise_attack'],
          opponentMoveIDs: ['grass_weak'],
          playerSpeed: 100,
          opponentSpeed: 50,
        ),
        playerMoveID: 'fire_raise_attack',
        opponentMoveID: 'grass_weak',
      );
      final player = state.player.activeMember;
      final event = lastMoveOf(state: state, side: BattleSideID.player);
      expect(event.statModifierChanges.single.side, BattleSideID.player);
      expect(event.statModifierChanges.single.newPercent, 125);
      final baseAttack = effectiveStats(
        monster: BattleMonster(
          definition: player.definition,
          maximumHitPointsPercent: player.maximumHitPointsPercent,
          state: player.state.copyWith(statModifierPercents: const {}),
        ),
      ).attack;
      expect(effectiveStats(monster: player).attack, baseAttack * 125 ~/ 100);
    });

    test('相手の素早さを下げると、次のターンから行動順が入れ替わる', () {
      var state = startDuel(
        playerMoveIDs: ['fire_strong'],
        opponentMoveIDs: ['fire_lower_speed', 'fire_strong'],
        playerSpeed: 100,
        opponentSpeed: 90,
      );
      state = playTurn(
        state: state,
        playerMoveID: 'fire_strong',
        opponentMoveID: 'fire_lower_speed',
      );
      final firstTurnEvents = state.events.whereType<MoveUsedEvent>().toList();
      expect(firstTurnEvents.first.attackerSide, BattleSideID.player);
      state = playTurn(
        state: state,
        playerMoveID: 'fire_strong',
        opponentMoveID: 'fire_strong',
      );
      final secondTurnEvents = state.events
          .whereType<MoveUsedEvent>()
          .skip(firstTurnEvents.length)
          .toList();
      expect(secondTurnEvents.first.attackerSide, BattleSideID.opponent);
    });

    test('回復する技は最大 HP を超えず、満タンなら 0 回復', () {
      final fullHitPoints = playTurn(
        state: startDuel(
          playerMoveIDs: ['fire_recover'],
          opponentMoveIDs: ['grass_weak'],
          playerSpeed: 100,
          opponentSpeed: 50,
        ),
        playerMoveID: 'fire_recover',
        opponentMoveID: 'grass_weak',
      );
      expect(
        lastMoveOf(
          state: fullHitPoints,
          side: BattleSideID.player,
        ).recoveredHitPoints,
        0,
      );

      // 相手が先に攻撃して減った HP を、同じターンに回復する
      final damaged = playTurn(
        state: startDuel(
          playerMoveIDs: ['fire_recover'],
          opponentMoveIDs: ['fire_strong'],
          playerSpeed: 50,
          opponentSpeed: 100,
        ),
        playerMoveID: 'fire_recover',
        opponentMoveID: 'fire_strong',
      );
      final damage = lastMoveOf(
        state: damaged,
        side: BattleSideID.opponent,
      ).damage;
      final recovery = lastMoveOf(state: damaged, side: BattleSideID.player);
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
            playerMoveIDs: ['fire_strong', 'fire_lower_defense'],
            opponentMoveIDs: ['fire_strong'],
            playerSpeed: 100,
            opponentSpeed: 50,
            randomSeed: seed,
          ),
          side: BattleSideID.player,
          master: testMaster,
        );
        if (action case UseMoveAction(moveID: 'fire_lower_defense')) {
          supportCount++;
        }
      }
      // 1/4 の期待値は 100 回。xorshift の偏りを許す幅として ±40 にした
      expect(supportCount, inInclusiveRange(60, 140));

      final defenseAtMinimum = startDuel(
        playerMoveIDs: ['fire_strong', 'fire_lower_defense'],
        opponentMoveIDs: ['fire_strong'],
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
                maximumHitPointsPercent: defenseAtMinimum
                    .opponent
                    .activeMember
                    .maximumHitPointsPercent,
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
          opponentDamagePercent: 100,
        );
        expect(
          chooseCpuAction(
            state: state,
            side: BattleSideID.player,
            master: testMaster,
          ),
          isA<UseMoveAction>().having(
            (action) => action.moveID,
            'moveID',
            'fire_strong',
          ),
        );
      }

      // HP が満タンの時は回復だけの技を選ばない
      for (var seed = 1; seed <= 50; seed++) {
        expect(
          chooseCpuAction(
            state: startDuel(
              playerMoveIDs: ['fire_strong', 'fire_recover'],
              opponentMoveIDs: ['fire_strong'],
              playerSpeed: 100,
              opponentSpeed: 50,
              randomSeed: seed,
            ),
            side: BattleSideID.player,
            master: testMaster,
          ),
          isA<UseMoveAction>().having(
            (action) => action.moveID,
            'moveID',
            'fire_strong',
          ),
        );
      }
    });

    test('補助技を持つ CPU 同士のバトルも決着する', () {
      final state = playUntilFinished(
        state: startDuel(
          playerMoveIDs: [
            'fire_strong',
            'fire_lower_defense',
            'fire_raise_attack',
            'fire_recover',
          ],
          opponentMoveIDs: [
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
        elementTypeID: 'fire',
        moveIDs: ['fire_strong'],
        speed: 50,
      ),
    );
    expect(
      () => startBattle(
        playerMembers: const [],
        opponentMembers: [member],
        randomSeed: 1,
        battleDate: testBattleDate,
        opponentDamagePercent: 100,
      ),
      throwsArgumentError,
    );
    expect(
      () => startBattle(
        playerMembers: [member, member, member, member],
        opponentMembers: [member],
        randomSeed: 1,
        battleDate: testBattleDate,
        opponentDamagePercent: 100,
      ),
      throwsArgumentError,
    );
  });

  group('equippedMoveChanges と nextLearnsetUnlockLevel', () {
    // 版 9 (#224) より前の規則で生まれたモンスターの一覧。Lv.1 の次は補助技の Lv.5、段階 2 の Lv.15
    const previousRuleLearnset = [
      LearnsetEntry(moveID: 'a', unlockLevel: 1),
      LearnsetEntry(moveID: 'b', unlockLevel: 1),
      LearnsetEntry(moveID: 'c', unlockLevel: 1),
      LearnsetEntry(moveID: 'd', unlockLevel: 1),
      LearnsetEntry(moveID: 's', unlockLevel: 5),
      LearnsetEntry(moveID: 'e', unlockLevel: 15),
    ];
    // 版 9 の規則 (Lv.2・3・5・8… で 1 つずつ覚える) で生まれたモンスターの一覧
    const currentRuleLearnset = [
      LearnsetEntry(moveID: 'a', unlockLevel: 1),
      LearnsetEntry(moveID: 'b', unlockLevel: 1),
      LearnsetEntry(moveID: 'c', unlockLevel: 1),
      LearnsetEntry(moveID: 'd', unlockLevel: 1),
      LearnsetEntry(moveID: 'e', unlockLevel: 2),
      LearnsetEntry(moveID: 'f', unlockLevel: 3),
    ];
    ({List<String> learnedMoveIDs, List<String> forgottenMoveIDs})
    levelUpChanges({
      required List<LearnsetEntry> learnset,
      required List<String> actionCardMoveIDs,
      required int previousLevel,
      required int newLevel,
    }) => equippedMoveChanges(
      previousMoveIDs: equippedLearnsetEntries(
        learnset: learnset,
        actionCardMoveIDs: actionCardMoveIDs,
        level: previousLevel,
      ),
      newMoveIDs: equippedLearnsetEntries(
        learnset: learnset,
        actionCardMoveIDs: actionCardMoveIDs,
        level: newLevel,
      ),
    );

    test('技を覚えるレベルに上がった時は、覚えた技と入れ替わりで外れた技を返す', () {
      final changes = levelUpChanges(
        learnset: currentRuleLearnset,
        actionCardMoveIDs: const [],
        previousLevel: 1,
        newLevel: 2,
      );
      expect(changes.learnedMoveIDs, ['e']);
      expect(changes.forgottenMoveIDs, ['a']);
    });

    test('前の規則で生まれたモンスターが Lv.2〜4 に上がっても技の枠は変わらず、次に覚えるのは Lv.5', () {
      final changes = levelUpChanges(
        learnset: previousRuleLearnset,
        actionCardMoveIDs: const [],
        previousLevel: 2,
        newLevel: 3,
      );
      expect(changes.learnedMoveIDs, isEmpty);
      expect(changes.forgottenMoveIDs, isEmpty);
      expect(
        nextLearnsetUnlockLevel(
          learnset: previousRuleLearnset,
          actionCardMoveIDs: const [],
          level: 3,
        ),
        5,
      );
    });

    test('Lv.5 に上がると補助技を覚え、次に覚えるのは Lv.15', () {
      final changes = levelUpChanges(
        learnset: previousRuleLearnset,
        actionCardMoveIDs: const [],
        previousLevel: 4,
        newLevel: 5,
      );
      expect(changes.learnedMoveIDs, ['s']);
      expect(changes.forgottenMoveIDs, ['a']);
      expect(
        nextLearnsetUnlockLevel(
          learnset: previousRuleLearnset,
          actionCardMoveIDs: const [],
          level: 5,
        ),
        15,
      );
    });

    test('枠に空きがある間は、覚えても外れる技は無い', () {
      final changes = levelUpChanges(
        learnset: const [
          LearnsetEntry(moveID: 'paper_1', unlockLevel: 1),
          LearnsetEntry(moveID: 'paper_2', unlockLevel: 15),
        ],
        actionCardMoveIDs: const [],
        previousLevel: 14,
        newLevel: 15,
      );
      expect(changes.learnedMoveIDs, ['paper_2']);
      expect(changes.forgottenMoveIDs, isEmpty);
    });

    test('もう覚える技が無ければ、次に覚えるレベルは null', () {
      expect(
        nextLearnsetUnlockLevel(
          learnset: currentRuleLearnset,
          actionCardMoveIDs: const [],
          level: 3,
        ),
        isNull,
      );
    });

    test('Action Card で先に覚えさせた技は、開放レベルに上がっても枠を変えず次に覚えるレベルにも数えない', () {
      final changes = levelUpChanges(
        learnset: currentRuleLearnset,
        actionCardMoveIDs: const ['e'],
        previousLevel: 1,
        newLevel: 2,
      );
      expect(changes.learnedMoveIDs, isEmpty);
      expect(changes.forgottenMoveIDs, isEmpty);
      expect(
        nextLearnsetUnlockLevel(
          learnset: currentRuleLearnset,
          actionCardMoveIDs: const ['e'],
          level: 1,
        ),
        3,
      );
    });

    test('Action Card の技が枠の数以上ある時は、開放レベルに上がっても枠が変わらず次に覚えるレベルを出さない', () {
      const actionCardMoveIDs = ['w', 'x', 'y', 'z'];
      final changes = levelUpChanges(
        learnset: currentRuleLearnset,
        actionCardMoveIDs: actionCardMoveIDs,
        previousLevel: 1,
        newLevel: 2,
      );
      expect(changes.learnedMoveIDs, isEmpty);
      expect(
        nextLearnsetUnlockLevel(
          learnset: currentRuleLearnset,
          actionCardMoveIDs: actionCardMoveIDs,
          level: 1,
        ),
        isNull,
      );
      // 枠の数より 1 つ少なければ、開放した技が枠に入るので次のレベルを出す
      expect(
        nextLearnsetUnlockLevel(
          learnset: currentRuleLearnset,
          actionCardMoveIDs: const ['x', 'y', 'z'],
          level: 1,
        ),
        2,
      );
    });

    test('Action Card の技を覚えさせると、一番古い技が枠から外れる', () {
      final changes = equippedMoveChanges(
        previousMoveIDs: equippedLearnsetEntries(
          learnset: currentRuleLearnset,
          actionCardMoveIDs: const [],
          level: 1,
        ),
        newMoveIDs: equippedLearnsetEntries(
          learnset: currentRuleLearnset,
          actionCardMoveIDs: const ['x'],
          level: 1,
        ),
      );
      expect(changes.learnedMoveIDs, ['x']);
      expect(changes.forgottenMoveIDs, ['a']);
    });
  });

  group('equippedLearnsetEntries', () {
    const learnset = [
      LearnsetEntry(moveID: 'a', unlockLevel: 1),
      LearnsetEntry(moveID: 'b', unlockLevel: 1),
      LearnsetEntry(moveID: 'c', unlockLevel: 1),
      LearnsetEntry(moveID: 'd', unlockLevel: 1),
      LearnsetEntry(moveID: 'e', unlockLevel: 15),
      LearnsetEntry(moveID: 'f', unlockLevel: 15),
      LearnsetEntry(moveID: 'g', unlockLevel: 100),
    ];
    List<String> learnsetMoveIDs({required int level}) =>
        equippedLearnsetEntries(
          learnset: learnset,
          actionCardMoveIDs: const [],
          level: level,
        );

    test('開放済みの技が枠の数までなら、開放済みの技をすべて一覧の順で返す', () {
      expect(learnsetMoveIDs(level: 14), ['a', 'b', 'c', 'd']);
    });

    test('開放済みの技が枠より多い時は、新しく覚えた技が一番古い技と入れ替わる', () {
      expect(learnsetMoveIDs(level: 15), ['c', 'd', 'e', 'f']);
      expect(learnsetMoveIDs(level: 100), ['d', 'e', 'f', 'g']);
    });

    test('覚える技が枠より少ない (前の規則で生まれた) モンスターも、開放済みの技をすべて返す', () {
      expect(
        equippedLearnsetEntries(
          learnset: const [
            LearnsetEntry(moveID: 'paper_1', unlockLevel: 1),
            LearnsetEntry(moveID: 'paper_2', unlockLevel: 15),
          ],
          actionCardMoveIDs: const [],
          level: 1,
        ),
        ['paper_1'],
      );
    });

    // Functions の技の枠 (functions/src/action_card_rules.ts の equippedMoveIDs) と共通のテストケース
    for (final equippedMoveCase
        in ((jsonDecode(
                      File(
                        'test/fixtures/equipped_move_cases.json',
                      ).readAsStringSync(),
                    )
                    as Map<String, dynamic>)['cases']
                as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      test('共通のテストケース: ${equippedMoveCase['name']}', () {
        expect(
          equippedLearnsetEntries(
            learnset: [
              for (final learnsetEntryJson
                  in equippedMoveCase['learnset'] as List<dynamic>)
                LearnsetEntry.fromJson(
                  json: learnsetEntryJson as Map<String, dynamic>,
                ),
            ],
            actionCardMoveIDs: [
              for (final moveID
                  in equippedMoveCase['actionCardMoveIDs'] as List<dynamic>)
                moveID as String,
            ],
            level: equippedMoveCase['level'] as int,
          ),
          equippedMoveCase['expectedMoveIDs'],
        );
      });
    }

    test('バトルで選べる技は枠に入った技だけ', () {
      final monster = prepare(
        definition: testDefinition(
          id: 'player',
          elementTypeID: 'fire',
          moveIDs: ['fire_strong', 'grass_strong'],
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

    test('Action Card で覚えさせた技は、PP を満タンにして枠の後ろで選べる', () {
      final monster = prepare(
        definition: testDefinition(
          id: 'player',
          elementTypeID: 'fire',
          moveIDs: ['fire_strong'],
          speed: 50,
        ),
        level: 1,
        actionCardMoveIDs: ['grass_strong'],
      );
      expect(
        monster.state.remainingPowerPoints['grass_strong'],
        testMaster.moveByID(moveID: 'grass_strong').powerPoints,
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
    /// 速い自分 (fire、技 [playerMoveIDs]) と遅い相手 (fire、技 [opponentMoveIDs]。HP は多め) の 1 対 1 を始める。
    BattleState duel({
      required List<String> playerMoveIDs,
      required List<String> opponentMoveIDs,
      int randomSeed = 1,
      int playerSpeed = 100,
      int opponentSpeed = 50,
      int opponentHitPoints = 250,
    }) => startBattle(
      playerMembers: [
        prepare(
          definition: testDefinition(
            id: 'player',
            elementTypeID: 'fire',
            moveIDs: playerMoveIDs,
            speed: playerSpeed,
            hitPoints: 250,
          ),
        ),
      ],
      opponentMembers: [
        prepare(
          definition: testDefinition(
            id: 'opponent',
            elementTypeID: 'fire',
            moveIDs: opponentMoveIDs,
            speed: opponentSpeed,
            hitPoints: opponentHitPoints,
          ),
        ),
      ],
      // 小さい seed (1, 2, ...) は xorshift の最初の出力が seed × 270369 (3 の倍数) になり、1〜3 の乱数が
      // どの seed でも同じ値になる。アプリの seed は Random の 32 bit の値のため、テストでも黄金比の定数を掛けて散らす
      randomSeed: (randomSeed * 0x9E3779B9) & 0xFFFFFFFF,
      battleDate: testBattleDate,
      opponentDamagePercent: 100,
    );

    BattleState play({
      required BattleState state,
      required String playerMoveID,
      required String opponentMoveID,
    }) => advanceRound(
      state: state,
      playerAction: UseMoveAction(moveID: playerMoveID),
      opponentAction: UseMoveAction(moveID: opponentMoveID),
      master: testMaster,
    );

    /// [state] の最後のラウンドで増えたログ。
    List<BattleEvent> lastRoundEvents({
      required BattleState state,
      required BattleState previous,
    }) => state.events.skip(previous.events.length).toList();

    test('1 ラウンドは両陣営のターン 2 つで、ログのターン番号は行動ごとに 1 増える', () {
      final before = duel(
        playerMoveIDs: ['fire_strong'],
        opponentMoveIDs: ['fire_strong'],
      );
      final after = play(
        state: before,
        playerMoveID: 'fire_strong',
        opponentMoveID: 'fire_strong',
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
        playerMoveIDs: ['fire_poison_attack', 'poison_strong'],
        opponentMoveIDs: ['fire_strong'],
      );
      state = play(
        state: state,
        playerMoveID: 'fire_poison_attack',
        opponentMoveID: 'fire_strong',
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
      expect(poisonDamages.single.side, BattleSideID.opponent);
      expect(poisonDamages.single.damage, maximumHitPoints ~/ 16);
      expect(poisonDamages.single.turnNumber, 2);

      state = play(
        state: state,
        playerMoveID: 'poison_strong',
        opponentMoveID: 'fire_strong',
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

    test('麻痺は次の自分のターンの攻撃技だけを 5 割の確率で失敗させ (PP は減らない)、そのターンの終わりに消える', () {
      var failedCount = 0;
      var attackedCount = 0;
      for (var seed = 1; seed <= 200; seed++) {
        var state = duel(
          playerMoveIDs: ['fire_paralyze', 'fire_strong'],
          opponentMoveIDs: ['fire_strong', 'fire_raise_attack'],
          randomSeed: seed,
        );
        state = play(
          state: state,
          playerMoveID: 'fire_paralyze',
          opponentMoveID: 'fire_strong',
        );
        final failed = state.events.whereType<ActionFailedEvent>().toList();
        if (failed.isEmpty) {
          // 止められなかったターンは、麻痺が無い時と同じに攻撃技を出して PP を使う
          attackedCount++;
          expect(
            state.events.whereType<MoveUsedEvent>().last.attackerSide,
            BattleSideID.opponent,
            reason: 'seed=$seed',
          );
          expect(
            state
                .opponent
                .activeMember
                .state
                .remainingPowerPoints['fire_strong'],
            9,
            reason: 'seed=$seed',
          );
        } else {
          failedCount++;
          expect(failed.single.side, BattleSideID.opponent);
          expect(failed.single.reason, ActionFailureReason.paralysis);
          expect(failed.single.turnNumber, 2);
          expect(
            state
                .opponent
                .activeMember
                .state
                .remainingPowerPoints['fire_strong'],
            10,
            reason: 'seed=$seed',
          );
        }
        // 止めたかどうかに関係なく、麻痺はそのターンの終わりに消える
        expect(
          state.events.whereType<StatusConditionCuredEvent>().single.cause,
          StatusConditionCureCause.expired,
          reason: 'seed=$seed',
        );
        expect(state.opponent.activeMember.state.statusConditions, isEmpty);
      }
      // 200 回の 5 割は、二項分布の 99.9% の範囲がおよそ 77〜123 回
      expect(failedCount, inInclusiveRange(70, 130));
      expect(attackedCount, 200 - failedCount);
    });

    test('麻痺でも補助技はどの seed でも使え、麻痺の乱数を引かない', () {
      for (var seed = 1; seed <= 50; seed++) {
        final state = play(
          state: duel(
            playerMoveIDs: ['fire_paralyze'],
            opponentMoveIDs: ['fire_raise_attack'],
            randomSeed: seed,
          ),
          playerMoveID: 'fire_paralyze',
          opponentMoveID: 'fire_raise_attack',
        );
        expect(
          state.events.whereType<ActionFailedEvent>(),
          isEmpty,
          reason: 'seed=$seed',
        );
        expect(
          state.events.whereType<MoveUsedEvent>().last.moveID,
          'fire_raise_attack',
        );
        // 相手が補助技を出す前に麻痺が付いている (麻痺を持ったまま補助技を出した)
        final paralysisIndex = state.events.indexWhere(
          (event) =>
              event is StatusConditionInflictedEvent &&
              event.side == BattleSideID.opponent &&
              event.kind == StatusConditionKind.paralysis,
        );
        expect(paralysisIndex, isNonNegative, reason: 'seed=$seed');
        expect(
          state.events.indexWhere(
            (event) =>
                event is MoveUsedEvent &&
                event.attackerSide == BattleSideID.opponent,
          ),
          greaterThan(paralysisIndex),
          reason: 'seed=$seed',
        );
        // 麻痺の技を使わないラウンドと乱数の進み方が同じ (補助技の時は麻痺の判定の乱数を引かない)
        expect(
          state.randomState,
          play(
            state: duel(
              playerMoveIDs: ['fire_raise_attack'],
              opponentMoveIDs: ['fire_raise_attack'],
              randomSeed: seed,
            ),
            playerMoveID: 'fire_raise_attack',
            opponentMoveID: 'fire_raise_attack',
          ).randomState,
          reason: 'seed=$seed',
        );
      }
    });

    test('気絶・凍結は 5 割の確率で全ての行動 (補助技を含む) を失敗させる', () {
      for (final (moveID, reason) in [
        ('fire_stun', ActionFailureReason.stun),
        ('fire_freeze', ActionFailureReason.frozen),
      ]) {
        var failedCount = 0;
        for (var seed = 1; seed <= 200; seed++) {
          final state = play(
            state: duel(
              playerMoveIDs: [moveID, 'fire_strong'],
              opponentMoveIDs: ['fire_raise_attack'],
              randomSeed: seed,
            ),
            playerMoveID: moveID,
            opponentMoveID: 'fire_raise_attack',
          );
          final failed = state.events.whereType<ActionFailedEvent>().toList();
          final opponentMoves = state.events.whereType<MoveUsedEvent>().where(
            (event) => event.attackerSide == BattleSideID.opponent,
          );
          // 止まったかどうかに関係なく、相手の行動の前に状態が付いている
          final inflictedIndex = state.events.indexWhere(
            (event) =>
                event is StatusConditionInflictedEvent &&
                event.side == BattleSideID.opponent,
          );
          expect(inflictedIndex, isNonNegative, reason: '$moveID seed=$seed');
          if (failed.isEmpty) {
            expect(opponentMoves.single.moveID, 'fire_raise_attack');
            expect(
              state.events.indexOf(opponentMoves.single),
              greaterThan(inflictedIndex),
              reason: '$moveID seed=$seed',
            );
          } else {
            failedCount++;
            expect(failed.single.reason, reason);
            expect(opponentMoves, isEmpty);
          }
        }
        expect(failedCount, inInclusiveRange(70, 130), reason: moveID);
      }
    });

    test('凍結は技のダメージを受けると解ける', () {
      // 凍結は 1〜3 ターンで、1 ターンなら最初の自分のターンの終わりに解けるため、2 ターン以上残った seed で確かめる
      var state = duel(
        playerMoveIDs: ['fire_freeze', 'fire_strong'],
        opponentMoveIDs: ['fire_strong'],
      );
      for (var seed = 1; seed <= 20; seed++) {
        state = play(
          state: duel(
            playerMoveIDs: ['fire_freeze', 'fire_strong'],
            opponentMoveIDs: ['fire_strong'],
            randomSeed: seed,
          ),
          playerMoveID: 'fire_freeze',
          opponentMoveID: 'fire_strong',
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
        playerMoveID: 'fire_strong',
        opponentMoveID: 'fire_strong',
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
        [BattleSideID.player, BattleSideID.opponent],
      );
    });

    test('眠りは 1〜3 ターン続き、その間は自分のターンごとに 5 割の確率で眠りの失敗になる', () {
      var sleepTurnCount = 0;
      var sleepFailedCount = 0;
      for (var seed = 1; seed <= 60; seed++) {
        var state = duel(
          playerMoveIDs: ['fire_drowsy', 'fire_raise_attack'],
          opponentMoveIDs: ['fire_raise_attack'],
          randomSeed: seed,
        );
        state = play(
          state: state,
          playerMoveID: 'fire_drowsy',
          opponentMoveID: 'fire_raise_attack',
        );
        // 2 回目の眠気で眠りになり、同じラウンドの相手のターンから失敗の判定が始まる
        final beforeSleep = state;
        state = play(
          state: state,
          playerMoveID: 'fire_drowsy',
          opponentMoveID: 'fire_raise_attack',
        );
        expect(
          lastRoundEvents(
            state: state,
            previous: beforeSleep,
          ).whereType<StatusConditionInflictedEvent>().single.kind,
          StatusConditionKind.sleep,
        );
        // 眠りの間の相手のターンの数と、そのうち失敗したターンの数を数える (失敗しなかったターンは補助技を使う)
        void countSleepTurn({required List<BattleEvent> roundEvents}) {
          sleepTurnCount++;
          final failed = roundEvents.whereType<ActionFailedEvent>().where(
            (event) => event.reason == ActionFailureReason.sleep,
          );
          final opponentMoves = roundEvents.whereType<MoveUsedEvent>().where(
            (event) => event.attackerSide == BattleSideID.opponent,
          );
          if (failed.isEmpty) {
            expect(opponentMoves.single.moveID, 'fire_raise_attack');
          } else {
            sleepFailedCount++;
            expect(opponentMoves, isEmpty);
          }
        }

        countSleepTurn(
          roundEvents: lastRoundEvents(state: state, previous: beforeSleep),
        );
        for (var round = 0; round < 2; round++) {
          if (!state.opponent.activeMember.state.statusConditions.containsKey(
            StatusConditionKind.sleep,
          )) {
            break;
          }
          final previous = state;
          state = play(
            state: state,
            playerMoveID: 'fire_raise_attack',
            opponentMoveID: 'fire_raise_attack',
          );
          countSleepTurn(
            roundEvents: lastRoundEvents(state: state, previous: previous),
          );
        }
        // 眠りの長さは 1〜3 ターンで、3 ターン目の終わりには必ず消える
        expect(
          state.opponent.activeMember.state.statusConditions,
          isNot(contains(StatusConditionKind.sleep)),
          reason: 'seed=$seed',
        );
      }
      // 60 戦の眠りのターン (60〜180) の 5 割前後が失敗する
      expect(sleepTurnCount, inInclusiveRange(60, 180));
      expect(
        sleepFailedCount * 100 / sleepTurnCount,
        inInclusiveRange(35, 65),
        reason: '$sleepFailedCount/$sleepTurnCount',
      );
    });

    test('眠気は素早さを半分にし、眠気の中でもう一度眠気を受けると眠りに置き換わる', () {
      var state = duel(
        playerMoveIDs: ['fire_drowsy'],
        opponentMoveIDs: ['fire_raise_attack'],
      );
      final speedBefore = effectiveStats(
        monster: state.opponent.activeMember,
      ).speed;
      state = play(
        state: state,
        playerMoveID: 'fire_drowsy',
        opponentMoveID: 'fire_raise_attack',
      );
      expect(
        effectiveStats(monster: state.opponent.activeMember).speed,
        speedBefore ~/ 2,
      );
      state = play(
        state: state,
        playerMoveID: 'fire_drowsy',
        opponentMoveID: 'fire_raise_attack',
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
        playerMoveIDs: ['fire_curse'],
        opponentMoveIDs: ['fire_raise_attack'],
        randomSeed: 3,
      );
      final statsBefore = effectiveStats(monster: state.opponent.activeMember);
      state = play(
        state: state,
        playerMoveID: 'fire_curse',
        opponentMoveID: 'fire_raise_attack',
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
        playerMoveID: 'fire_curse',
        opponentMoveID: 'fire_raise_attack',
      );
      expect(
        state.events.whereType<StatusConditionInflictedEvent>().length,
        inflictedCount,
      );
    });

    test('やけどは与える攻撃のダメージを半分にし、受けるダメージを 1.1 倍にする', () {
      final before = duel(
        playerMoveIDs: ['fire_strong'],
        opponentMoveIDs: ['fire_strong'],
      );
      BattleState withBurn({required BattleSideID side, required int stack}) {
        BattleParty withStatus(BattleParty party) => BattleParty(
          members: [
            BattleMonster(
              definition: party.activeMember.definition,
              maximumHitPointsPercent:
                  party.activeMember.maximumHitPointsPercent,
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
          player: side == BattleSideID.player
              ? withStatus(before.player)
              : before.player,
          opponent: side == BattleSideID.opponent
              ? withStatus(before.opponent)
              : before.opponent,
          turnNumber: before.turnNumber,
          randomState: before.randomState,
          events: before.events,
          winner: null,
          battleDate: before.battleDate,
          field: null,
          opponentDamagePercent: 100,
        );
      }

      int playerDamage(BattleState state) => play(
        state: state,
        playerMoveID: 'fire_strong',
        opponentMoveID: 'fire_strong',
      ).events.whereType<MoveUsedEvent>().first.damage;
      final normal = playerDamage(before);
      expect(
        playerDamage(withBurn(side: BattleSideID.player, stack: 1)),
        normal ~/ 2,
      );
      expect(
        playerDamage(withBurn(side: BattleSideID.opponent, stack: 1)),
        normal * 11 ~/ 10,
      );
      expect(
        playerDamage(withBurn(side: BattleSideID.opponent, stack: 3)),
        normal * 13 ~/ 10,
      );
    });

    test('興奮は攻撃を 1.5 倍、防御を半分にする', () {
      var state = duel(
        playerMoveIDs: ['fire_excite'],
        opponentMoveIDs: ['fire_raise_attack'],
      );
      final statsBefore = effectiveStats(monster: state.player.activeMember);
      state = play(
        state: state,
        playerMoveID: 'fire_excite',
        opponentMoveID: 'fire_raise_attack',
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
          playerMoveIDs: ['fire_confuse'],
          opponentMoveIDs: ['fire_raise_attack', 'fire_lower_speed'],
          randomSeed: seed,
        );
        state = play(
          state: state,
          playerMoveID: 'fire_confuse',
          opponentMoveID: 'fire_raise_attack',
        );
        final previous = state;
        state = play(
          state: state,
          playerMoveID: 'fire_confuse',
          opponentMoveID: 'fire_raise_attack',
        );
        final opponentMove = lastRoundEvents(state: state, previous: previous)
            .whereType<MoveUsedEvent>()
            .firstWhere((event) => event.attackerSide == BattleSideID.opponent);
        if (opponentMove.replacedMoveID != null) {
          replacedCount++;
          expect(opponentMove.replacedMoveID, 'fire_raise_attack');
          expect(opponentMove.moveID, 'fire_lower_speed');
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
            playerMoveIDs: ['fire_inaccurate'],
            opponentMoveIDs: ['fire_raise_attack'],
            randomSeed: seed,
          ),
          playerMoveID: 'fire_inaccurate',
          opponentMoveID: 'fire_raise_attack',
        );
        final missed = state.events.whereType<ActionFailedEvent>().where(
          (event) => event.reason == ActionFailureReason.missed,
        );
        if (missed.isNotEmpty) {
          missedCount++;
          expect(missed.single.side, BattleSideID.player);
          expect(missed.single.moveID, 'fire_inaccurate');
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
          playerMoveIDs: ['fire_sure_hit', 'fire_inaccurate'],
          opponentMoveIDs: ['fire_dizzy'],
          randomSeed: seed,
        );
        state = play(
          state: state,
          playerMoveID: 'fire_sure_hit',
          opponentMoveID: 'fire_dizzy',
        );
        expect(
          state.player.activeMember.state.statusConditions,
          contains(StatusConditionKind.dizzy),
        );
        expect(
          moveHitChancePercent(
            move: testMaster.moveByID(moveID: 'fire_inaccurate'),
            attacker: state.player.activeMember,
          ),
          35,
        );
        state = play(
          state: state,
          playerMoveID: 'fire_sure_hit',
          opponentMoveID: 'fire_dizzy',
        );
        expect(state.events.whereType<ActionFailedEvent>(), isEmpty);
      }
    });

    test('使う側の命中を技の命中率に掛け、命中が 100 未満なら命中率 100 の技も外れる (#279)', () {
      // 命中の種族値 40・個体値 31 は 80 + (2 × 40 + 31) × 20 ÷ 271 = 88
      final lowAccuracyAttacker = prepare(
        definition: testDefinition(
          id: 'low-accuracy',
          elementTypeID: 'fire',
          moveIDs: ['fire_strong', 'fire_inaccurate', 'fire_sure_hit'],
          speed: 80,
          accuracyBaseStat: 40,
        ),
      );
      expect(effectiveStats(monster: lowAccuracyAttacker).accuracy, 88);
      // 威力 60 の技は威力の割合で 98%。98 × 88 ÷ 100 = 86
      expect(
        moveHitChancePercent(
          move: testMaster.moveByID(moveID: 'fire_strong'),
          attacker: lowAccuracyAttacker,
        ),
        86,
      );
      expect(
        moveHitChancePercent(
          move: testMaster.moveByID(moveID: 'fire_inaccurate'),
          attacker: lowAccuracyAttacker,
        ),
        44,
      );
      expect(
        moveHitChancePercent(
          move: testMaster.moveByID(moveID: 'fire_sure_hit'),
          attacker: lowAccuracyAttacker,
        ),
        100,
      );
      // 命中 100 のモンスターは技の命中率 (威力の割合を掛けた値) のまま
      expect(
        moveHitChancePercent(
          move: testMaster.moveByID(moveID: 'fire_strong'),
          attacker: prepare(
            definition: testDefinition(
              id: 'full-accuracy',
              elementTypeID: 'fire',
              moveIDs: ['fire_strong'],
              speed: 80,
            ),
          ),
        ),
        98,
      );
    });

    test('一撃必殺は当たれば威力に関係なく相手の HP を 0 にし、PP 1 で外れやすい', () {
      var hitCount = 0;
      const seedCount = 100;
      for (var seed = 1; seed <= seedCount; seed++) {
        final state = play(
          state: duel(
            playerMoveIDs: ['fire_one_hit', 'fire_strong'],
            opponentMoveIDs: ['fire_strong'],
            randomSeed: seed,
          ),
          playerMoveID: 'fire_one_hit',
          opponentMoveID: 'fire_strong',
        );
        final moveUsed = state.events.whereType<MoveUsedEvent>().where(
          (event) => event.attackerSide == BattleSideID.player,
        );
        if (moveUsed.isNotEmpty) {
          hitCount++;
          expect(moveUsed.single.isOneHitKnockout, isTrue);
          expect(moveUsed.single.defenderRemainingHitPoints, 0);
          expect(state.winner, BattleSideID.player);
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
      // 自爆 (威力 200) は威力の割合で命中率 70% のため (#279)、当たった後の規則を確かめるよう自爆が当たる最初の seed を使う
      BattleState hitSelfDestruct({int opponentHitPoints = 250}) =>
          [
            for (var randomSeed = 1; randomSeed <= 20; randomSeed++)
              play(
                state: duel(
                  playerMoveIDs: ['fire_self_destruct'],
                  opponentMoveIDs: ['fire_strong'],
                  randomSeed: randomSeed,
                  opponentHitPoints: opponentHitPoints,
                ),
                playerMoveID: 'fire_self_destruct',
                opponentMoveID: 'fire_strong',
              ),
          ].firstWhere(
            (state) => state.events.whereType<MoveUsedEvent>().any(
              (event) => event.selfDestructed,
            ),
          );
      final state = hitSelfDestruct();
      // 自分が速いため先に自爆する。倒れた相手には後に動く側も技を使わないため、技のログは自爆の 1 件だけ
      final moveUsed = state.events.whereType<MoveUsedEvent>().single;
      expect(moveUsed.attackerSide, BattleSideID.player);
      expect(moveUsed.selfDestructed, isTrue);
      expect(moveUsed.damage, greaterThan(0));
      expect(moveUsed.attackerRemainingHitPoints, 0);
      expect(state.player.activeMember.isFainted, isTrue);
      expect(
        state.events.whereType<MonsterFaintedEvent>().map(
          (event) => event.side,
        ),
        [BattleSideID.player],
      );
      // 相手は技を使っていないので PP も減らない
      expect(
        state.opponent.activeMember.state.remainingPowerPoints['fire_strong'],
        10,
      );
      expect(state.winner, BattleSideID.opponent);

      final mutual = hitSelfDestruct(opponentHitPoints: 1);
      expect(mutual.player.isDefeated, isTrue);
      expect(mutual.opponent.isDefeated, isTrue);
      expect(mutual.winner, BattleSideID.player);
      expect(mutual.events.whereType<MonsterFaintedEvent>(), hasLength(2));
    });

    test('先に動いた側が毒で倒れた時も、後に動く側は倒れた相手に技を使わず、倒れたログは 1 件', () {
      // 毒の持ち主 (自分) を最大 HP が小さく毒 4 重ねで 1 ターンで倒れる状態にする
      final before = duel(
        playerMoveIDs: ['fire_raise_attack'],
        opponentMoveIDs: ['fire_strong'],
      );
      final player = before.player.activeMember;
      final maximumHitPoints = effectiveStats(monster: player).hitPoints;
      final poisoned = BattleState(
        player: BattleParty(
          members: [
            BattleMonster(
              definition: player.definition,
              maximumHitPointsPercent: player.maximumHitPointsPercent,
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
        opponentDamagePercent: 100,
      );
      expect(
        poisonDamage(maximumHitPoints: maximumHitPoints, stackCount: 1),
        greaterThanOrEqualTo(1),
      );
      final state = play(
        state: poisoned,
        playerMoveID: 'fire_raise_attack',
        opponentMoveID: 'fire_strong',
      );
      expect(
        state.events.whereType<MoveUsedEvent>().map(
          (event) => event.attackerSide,
        ),
        [BattleSideID.player],
      );
      expect(
        state.events.whereType<StatusConditionDamageEvent>(),
        hasLength(1),
      );
      expect(
        state.events.whereType<MonsterFaintedEvent>().map(
          (event) => event.side,
        ),
        [BattleSideID.player],
      );
      expect(state.winner, BattleSideID.opponent);
    });

    test('自爆・一撃必殺だけが残った時はわるあがきも選べる', () {
      final state = duel(
        playerMoveIDs: ['fire_one_hit', 'fire_self_destruct'],
        opponentMoveIDs: ['fire_strong'],
      );
      expect(
        () => advanceRound(
          state: state,
          playerAction: const StruggleAction(),
          opponentAction: const UseMoveAction(moveID: 'fire_strong'),
          master: testMaster,
        ),
        returnsNormally,
      );
      expect(
        () => advanceRound(
          state: duel(
            playerMoveIDs: ['fire_one_hit', 'fire_strong'],
            opponentMoveIDs: ['fire_strong'],
          ),
          playerAction: const StruggleAction(),
          opponentAction: const UseMoveAction(moveID: 'fire_strong'),
          master: testMaster,
        ),
        throwsArgumentError,
      );
    });

    test('先制の技は素早さに関係なく先に出る', () {
      final state = play(
        state: duel(
          playerMoveIDs: ['fire_strong'],
          opponentMoveIDs: ['fire_priority'],
        ),
        playerMoveID: 'fire_strong',
        opponentMoveID: 'fire_priority',
      );
      expect(
        state.events.whereType<MoveUsedEvent>().map(
          (event) => event.attackerSide,
        ),
        [BattleSideID.opponent, BattleSideID.player],
      );
    });

    test('状態を解除する技は自分の状態をすべて消す', () {
      var state = duel(
        playerMoveIDs: ['fire_burn', 'fire_poison_support'],
        opponentMoveIDs: ['fire_cure', 'fire_raise_attack'],
      );
      state = play(
        state: state,
        playerMoveID: 'fire_burn',
        opponentMoveID: 'fire_raise_attack',
      );
      state = play(
        state: state,
        playerMoveID: 'fire_poison_support',
        opponentMoveID: 'fire_raise_attack',
      );
      expect(state.opponent.activeMember.state.statusConditions, hasLength(2));
      final previous = state;
      state = play(
        state: state,
        playerMoveID: 'fire_burn',
        opponentMoveID: 'fire_cure',
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
        playerMoveIDs: ['fire_shuffle', 'fire_raise_attack'],
        opponentMoveIDs: ['fire_raise_attack'],
      );
      state = play(
        state: state,
        playerMoveID: 'fire_shuffle',
        opponentMoveID: 'fire_raise_attack',
      );
      expect(state.field?.kind, FieldEffectKind.statShuffle);
      expect(state.field?.remainingRounds, 3);
      expect(state.field?.swappedStatKinds, isNull);
      expect(state.events.whereType<FieldEffectStartedEvent>(), hasLength(1));
      for (var round = 0; round < 3; round++) {
        final previous = state;
        state = play(
          state: state,
          playerMoveID: 'fire_raise_attack',
          opponentMoveID: 'fire_raise_attack',
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
        playerMoveID: 'fire_raise_attack',
        opponentMoveID: 'fire_raise_attack',
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
        playerMoveIDs: ['fire_paralyze', 'fire_strong'],
        opponentMoveIDs: ['fire_strong'],
      );
      var supportCount = 0;
      for (var seed = 1; seed <= 100; seed++) {
        final action = chooseCpuAction(
          state: duel(
            playerMoveIDs: ['fire_paralyze', 'fire_strong'],
            opponentMoveIDs: ['fire_strong'],
            randomSeed: seed,
          ),
          side: BattleSideID.player,
          master: testMaster,
        );
        if (action case UseMoveAction(moveID: 'fire_paralyze')) {
          supportCount++;
        }
      }
      expect(supportCount, inInclusiveRange(10, 40));
      state = play(
        state: state,
        playerMoveID: 'fire_paralyze',
        opponentMoveID: 'fire_strong',
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
            playerMoveIDs: [
              'fire_one_hit',
              'fire_self_destruct',
              'fire_strong',
            ],
            opponentMoveIDs: ['fire_strong'],
            randomSeed: seed,
          ),
          side: BattleSideID.player,
          master: testMaster,
        );
        switch (action) {
          case UseMoveAction(moveID: 'fire_one_hit'):
            oneHitCount++;
          case UseMoveAction(moveID: 'fire_strong'):
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
      for (final moveIDs in [
        ['fire_one_hit', 'fire_self_destruct'],
        ['fire_self_destruct'],
        ['fire_one_hit', 'fire_raise_attack'],
      ]) {
        for (var seed = 1; seed <= 30; seed++) {
          final state = duel(
            playerMoveIDs: moveIDs,
            opponentMoveIDs: ['fire_strong'],
            randomSeed: seed,
          );
          final action = chooseCpuAction(
            state: state,
            side: BattleSideID.player,
            master: testMaster,
          );
          switch (action) {
            case UseMoveAction(moveID: 'fire_one_hit'):
              oneHitCount++;
            case UseMoveAction(moveID: 'fire_raise_attack'):
              break;
            case StruggleAction():
              struggleCount++;
            default:
              fail('HP が満タンの時に自爆を選んだ: $moveIDs seed=$seed: $action');
          }
          // 選んだ行動は advanceRound の検証を通る
          expect(
            () => advanceRound(
              state: state,
              playerAction: action,
              opponentAction: const UseMoveAction(moveID: 'fire_strong'),
              master: testMaster,
            ),
            returnsNormally,
            reason: '$moveIDs seed=$seed: $action',
          );
        }
      }
      expect(oneHitCount, greaterThan(0));
      expect(struggleCount, greaterThan(0));
    });

    test('麻痺と混乱が重なり、補助技が攻撃技に置き換わった時は麻痺の判定を受ける (補助技のままなら受けない)', () {
      final before = duel(
        playerMoveIDs: ['fire_raise_attack'],
        opponentMoveIDs: ['fire_raise_attack', 'fire_strong'],
      );
      BattleState withStatuses({required int seed}) {
        final opponent = before.opponent.activeMember;
        return BattleState(
          player: before.player,
          opponent: BattleParty(
            members: [
              BattleMonster(
                definition: opponent.definition,
                maximumHitPointsPercent: opponent.maximumHitPointsPercent,
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
          opponentDamagePercent: 100,
        );
      }

      var paralyzedCount = 0;
      var replacedAttackCount = 0;
      var supportCount = 0;
      for (var seed = 1; seed <= 200; seed++) {
        final state = play(
          state: withStatuses(seed: seed * 0x9E3779B9 & 0xFFFFFFFF),
          playerMoveID: 'fire_raise_attack',
          opponentMoveID: 'fire_raise_attack',
        );
        final opponentMoveIDs = [
          for (final event in state.events.whereType<MoveUsedEvent>())
            if (event.attackerSide == BattleSideID.opponent) event.moveID,
        ];
        final failed = state.events.whereType<ActionFailedEvent>().where(
          (event) => event.reason == ActionFailureReason.paralysis,
        );
        if (failed.isNotEmpty) {
          // 失敗するのは置き換わった攻撃技だけ
          paralyzedCount++;
          expect(failed.single.moveID, 'fire_strong', reason: 'seed=$seed');
          expect(opponentMoveIDs, isEmpty, reason: 'seed=$seed');
        } else if (opponentMoveIDs.single == 'fire_strong') {
          replacedAttackCount++;
        } else {
          supportCount++;
        }
      }
      // 混乱で置き換わるのが 1/2、置き換わった攻撃技が麻痺で止まるのがその 1/2 なので、止まるのは 1/4 ほど
      expect(paralyzedCount, inInclusiveRange(25, 75));
      expect(replacedAttackCount, inInclusiveRange(25, 75));
      expect(supportCount, inInclusiveRange(70, 130));
    });

    test('続いている入れ替えのフィールドを同じ技で始め直しても、そのラウンドの入れ替えは保たれる', () {
      var state = duel(
        playerMoveIDs: ['fire_shuffle', 'fire_raise_attack'],
        opponentMoveIDs: ['fire_raise_attack'],
      );
      state = play(
        state: state,
        playerMoveID: 'fire_shuffle',
        opponentMoveID: 'fire_raise_attack',
      );
      state = play(
        state: state,
        playerMoveID: 'fire_raise_attack',
        opponentMoveID: 'fire_raise_attack',
      );
      final swappedBefore = state.field!.swappedStatKinds;
      expect(swappedBefore, isNotNull);
      state = play(
        state: state,
        playerMoveID: 'fire_shuffle',
        opponentMoveID: 'fire_raise_attack',
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
            maximumHitPointsPercent: member.maximumHitPointsPercent,
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
                elementTypeID: 'fire',
                moveIDs: ['fire_strong', 'fire_raise_attack'],
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
              elementTypeID: 'grass',
              moveIDs: [
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
      opponentDamagePercent: 100,
    );

    test('交代は先制の技より先に行われ、交代して出たモンスターが相手の技を受ける', () {
      final state = startSwitchBattle();
      final next = advanceRound(
        state: state,
        playerAction: const SwitchMonsterAction(memberIndex: 1),
        opponentAction: const UseMoveAction(moveID: 'fire_priority'),
        master: testMaster,
      );

      final switched = next.events.first as MonsterSwitchedInEvent;
      expect(switched.turnNumber, 1);
      expect(switched.side, BattleSideID.player);
      expect(switched.monsterID, 'player_2');
      expect(switched.withdrawnMonsterID, 'player_1');
      final moveUsed = next.events[1] as MoveUsedEvent;
      expect(moveUsed.turnNumber, 2);
      expect(moveUsed.attackerSide, BattleSideID.opponent);
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
            opponentAction: const UseMoveAction(moveID: 'grass_strong'),
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
          opponentAction: const UseMoveAction(moveID: 'grass_strong'),
          master: testMaster,
        ),
        returnsNormally,
      );
    });

    test('場を離れるとステータスの倍率は等倍に戻り、状態は残る', () {
      var state = advanceRound(
        state: startSwitchBattle(),
        playerAction: const UseMoveAction(moveID: 'fire_raise_attack'),
        opponentAction: const UseMoveAction(moveID: 'fire_curse'),
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
        opponentAction: const UseMoveAction(moveID: 'fire_curse'),
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
        playerAction: const UseMoveAction(moveID: 'fire_raise_attack'),
        opponentAction: const UseMoveAction(moveID: 'fire_block_switch'),
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
            opponentAction: const UseMoveAction(moveID: 'fire_curse'),
            master: testMaster,
          ),
          throwsArgumentError,
        );
        state = advanceRound(
          state: state,
          playerAction: const UseMoveAction(moveID: 'fire_raise_attack'),
          opponentAction: const UseMoveAction(moveID: 'fire_curse'),
          master: testMaster,
        );
        blockedRounds++;
        expect(blockedRounds, lessThanOrEqualTo(3));
      }
      // 相手が先に動いて付けたため、付いたラウンドの自分のターンの終わりで 1 減り、残りの 2 ラウンドだけ封じる
      expect(blockedRounds, 2);
      expect(state.events.whereType<StatusConditionCuredEvent>().last.kinds, [
        StatusConditionKind.switchBlocked,
      ]);
      final next = advanceRound(
        state: state,
        playerAction: const SwitchMonsterAction(memberIndex: 1),
        opponentAction: const UseMoveAction(moveID: 'fire_curse'),
        master: testMaster,
      );
      expect(next.player.activeMemberIndex, 1);
    });

    test('交換不可でも、倒れた時の交代は止まらない', () {
      var state = advanceRound(
        state: startSwitchBattle(playerHitPoints: {0: 1}),
        playerAction: const UseMoveAction(moveID: 'fire_raise_attack'),
        opponentAction: const UseMoveAction(moveID: 'fire_block_switch'),
        master: testMaster,
      );
      expect(isSwitchBlocked(party: state.player), isTrue);
      state = advanceRound(
        state: state,
        playerAction: const UseMoveAction(moveID: 'fire_raise_attack'),
        opponentAction: const UseMoveAction(moveID: 'grass_strong'),
        master: testMaster,
      );
      final switched = state.events.whereType<MonsterSwitchedInEvent>().single;
      expect(switched.monsterID, 'player_2');
      expect(switched.withdrawnMonsterID, isNull);
      expect(state.player.activeMemberIndex, 1);
    });

    test('交代で場に出たモンスターだけがレベルアップの対象になる (先頭→3 体目→倒れて先頭に戻る)', () {
      var state = advanceRound(
        state: startSwitchBattle(playerHitPoints: {2: 1}, opponentHitPoints: 1),
        playerAction: const SwitchMonsterAction(memberIndex: 2),
        opponentAction: const UseMoveAction(moveID: 'grass_strong'),
        master: testMaster,
      );
      // 3 体目は相手の技で倒れ、倒れていない最も前の先頭が戻る
      expect(
        state.events.whereType<MonsterSwitchedInEvent>().map(
          (event) => (event.monsterID, event.withdrawnMonsterID),
        ),
        [('player_3', 'player_1'), ('player_1', null)],
      );
      expect(state.player.activeMemberIndex, 0);
      state = advanceRound(
        state: state,
        playerAction: const UseMoveAction(moveID: 'fire_strong'),
        opponentAction: const UseMoveAction(moveID: 'fire_curse'),
        master: testMaster,
      );
      expect(state.winner, BattleSideID.player);
      expect(state.player.members.map((member) => member.state.level), [
        51,
        50,
        51,
      ]);
      expect(
        state.events
            .whereType<LevelUpEvent>()
            .where((event) => event.side == BattleSideID.player)
            .map((event) => event.monsterID),
        ['player_1', 'player_3'],
      );
    });
  });
}
