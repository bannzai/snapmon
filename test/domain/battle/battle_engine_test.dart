import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/master/element_type.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/domain/master/move.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';

/// バトルの規則だけを確かめるための小さな master。fire は grass に 2 倍、grass は fire に 0.5 倍。
const testMaster = MasterData(
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
    ),
  ],
  effects: [],
  statGrades: [],
  elementSelection: null,
);

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
    current = advanceTurn(
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
    );
    MoveUsedEvent firstHit(BattleState battleState) => advanceTurn(
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
    }) => advanceTurn(
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
    );
    expect(
      () => advanceTurn(
        state: state,
        playerAction: const StruggleAction(),
        opponentAction: const UseMoveAction(moveId: 'grass_weak'),
        master: testMaster,
      ),
      throwsArgumentError,
    );
    for (var turn = 0; turn < 2; turn++) {
      state = advanceTurn(
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
      () => advanceTurn(
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
    final afterStruggle = advanceTurn(
      state: state,
      playerAction: const StruggleAction(),
      opponentAction: const StruggleAction(),
      master: testMaster,
    );
    final struggleEvents = afterStruggle.events
        .whereType<MoveUsedEvent>()
        .where((event) => event.turnNumber == state.turnNumber);
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
        () => advanceTurn(
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
    BattleSideId firstAttacker({required int randomSeed}) => advanceTurn(
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
    );
    while (state.winner == null) {
      state = advanceTurn(
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
      ),
      throwsArgumentError,
    );
    expect(
      () => startBattle(
        playerMembers: [member, member, member, member],
        opponentMembers: [member],
        randomSeed: 1,
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
}
