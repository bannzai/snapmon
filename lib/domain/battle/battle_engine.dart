import 'dart:math' as math;

import '../master/master_data.dart';
import '../master/move.dart';
import '../monster/monster_definition.dart';
import '../monster/monster_state.dart';
import '../monster/stat_calculation.dart';
import '../random/deterministic_random.dart';
import 'battle_state.dart';

/// わるあがきの威力。技を使い切った方が得にならないよう、master の版 1 で最も弱い攻撃技の威力 (40) と同じにした。
const int strugglePower = 40;

/// ダメージの乱数幅の下限 (%)。上限は 100%。同じ組み合わせでも結果が揺れる程度にしつつ、
/// 下限 (0.85) が相性 2 倍・0.5 倍の差を覆さない幅にした。
const int damageRandomMinimumPercent = 85;

/// [definition] のモンスターを、[level]・[experience] で HP・PP を満タンにした状態でバトルに出す。
/// PP は覚える技の一覧のすべての技について持つ (レベルで開放されていない技も、上がった後に使えるよう持っておく)。
BattleMonster prepareBattleMonster({
  required MonsterDefinition definition,
  required int level,
  required int experience,
  required MasterData master,
}) => BattleMonster(
  definition: definition,
  state: MonsterState(
    level: level,
    experience: experience,
    currentHitPoints: calculateStats(
      baseStats: definition.baseStats,
      individualValues: definition.individualValues,
      level: level,
      statCalculationVersion: definition.statCalculationVersion,
    ).hitPoints,
    remainingPowerPoints: {
      for (final learnsetEntry in definition.learnset)
        learnsetEntry.moveId: master
            .moveById(moveId: learnsetEntry.moveId)
            .powerPoints,
    },
  ),
);

/// 両陣営の手持ち ([prepareBattleMonster] で用意した 1〜3 体) でバトルを始める。
/// [randomSeed] は行動順の同速判定とダメージの乱数幅に使い、同じ seed と同じ行動からは同じ結果になる。
BattleState startBattle({
  required List<BattleMonster> playerMembers,
  required List<BattleMonster> opponentMembers,
  required int randomSeed,
}) {
  for (final members in [playerMembers, opponentMembers]) {
    if (members.isEmpty || members.length > maximumPartySize) {
      throw ArgumentError(
        '手持ちは 1 体以上 $maximumPartySize 体以下 (${members.length} 体が渡された)',
      );
    }
  }
  return BattleState(
    player: BattleParty(members: playerMembers, activeMemberIndex: 0),
    opponent: BattleParty(members: opponentMembers, activeMemberIndex: 0),
    turnNumber: 1,
    randomState: DeterministicRandom(seed: randomSeed).state,
    events: const [],
    winner: null,
  );
}

/// [monster] が今使える技 (レベルで開放済みで PP が残っている技) を、覚える技の一覧の順で返す。
/// 攻撃技が 1 つも無ければわるあがき ([StruggleAction]) も選べる (補助技だけが残って決着しなくなるのを防ぐため)。
List<Move> selectableMoves({
  required BattleMonster monster,
  required MasterData master,
}) => [
  for (final learnsetEntry in monster.definition.learnset)
    if (learnsetEntry.unlockLevel <= monster.state.level &&
        (monster.state.remainingPowerPoints[learnsetEntry.moveId] ?? 0) > 0)
      master.moveById(moveId: learnsetEntry.moveId),
];

/// 攻撃側の技の属性 [moveElementTypeId] から、防御側の属性 [defenderElementTypeIds] への倍率を返す。
/// 防御側が属性を複数持つ時は、属性ごとの倍率の積にする。[moveElementTypeId] が null (わるあがき) なら 1。
double totalTypeMultiplier({
  required String? moveElementTypeId,
  required List<String> defenderElementTypeIds,
  required MasterData master,
}) => moveElementTypeId == null
    ? 1
    : defenderElementTypeIds.fold<double>(
        1,
        (product, defenderElementTypeId) =>
            product *
            master.typeMultiplier(
              attackerElementTypeId: moveElementTypeId,
              defenderElementTypeId: defenderElementTypeId,
            ),
      );

/// ダメージを返す。式は documents/game-rules.md「ダメージ式」。
/// [randomPercent] は [damageRandomMinimumPercent] 以上 100 以下の乱数。結果は 1 以上。
int calculateDamage({
  required int attackerLevel,
  required int power,
  required int attack,
  required int defense,
  required double typeMultiplier,
  required int randomPercent,
}) {
  final baseDamage =
      ((2 * attackerLevel ~/ 5 + 2) * power * attack ~/ defense) ~/ 50 + 2;
  return math.max(1, (baseDamage * typeMultiplier * randomPercent ~/ 100));
}

/// CPU の行動を返す。相手の場のモンスターへの相性の倍率が最大の攻撃技を選び、
/// 倍率が同じなら威力が高い技、それも同じなら覚える技の一覧で先の技を選ぶ。使える攻撃技が無ければわるあがき。
BattleAction chooseCpuAction({
  required BattleState state,
  required BattleSideId side,
  required MasterData master,
}) {
  final attacker = state.partyOf(side: side).activeMember;
  final defender = state.partyOf(side: _otherSide(side: side)).activeMember;
  Move? bestMove;
  var bestMultiplier = 0.0;
  for (final move in selectableMoves(monster: attacker, master: master)) {
    if (move.category != MoveCategory.attack) {
      continue;
    }
    final multiplier = totalTypeMultiplier(
      moveElementTypeId: move.elementTypeId,
      defenderElementTypeIds: defender.definition.elementTypeIds,
      master: master,
    );
    if (bestMove == null ||
        multiplier > bestMultiplier ||
        (multiplier == bestMultiplier && move.power > bestMove.power)) {
      bestMove = move;
      bestMultiplier = multiplier;
    }
  }
  return bestMove == null
      ? const StruggleAction()
      : UseMoveAction(moveId: bestMove.id);
}

/// 両陣営の行動 [playerAction]・[opponentAction] で 1 ターンを解決し、次の状態を返す。
/// 場のモンスターの素早さが高い順に行動し (同じなら乱数)、倒れたモンスターはそのターンの行動を失う。
/// ターンの終わりに倒れたモンスターを手持ちの次のモンスターと交代し、手持ちがすべて倒れた側が負ける。
/// 決着がついたら勝敗を問わず両陣営の、場に出たことがある手持ちのレベルを 1 上げる (上限 [maximumLevel]。
/// DIRECTION.md「必要な機能」の「1 戦ごとに、戦闘に出た手持ちのレベルが勝敗に関係なく 1 上がる」)。
/// 決着済みの状態・選べない行動 (PP が 0 か未開放の技、使える攻撃技があるのにわるあがき) には例外を投げる。
BattleState advanceTurn({
  required BattleState state,
  required BattleAction playerAction,
  required BattleAction opponentAction,
  required MasterData master,
}) {
  if (state.winner != null) {
    throw StateError('決着済みのバトルは進められない');
  }
  final actions = {
    BattleSideId.player: playerAction,
    BattleSideId.opponent: opponentAction,
  };
  for (final entry in actions.entries) {
    _validateAction(
      monster: state.partyOf(side: entry.key).activeMember,
      action: entry.value,
      master: master,
    );
  }

  final random = DeterministicRandom(seed: state.randomState);
  final parties = {
    BattleSideId.player: state.player,
    BattleSideId.opponent: state.opponent,
  };
  final events = [...state.events];

  int speedOf({required BattleSideId side}) {
    final monster = parties[side]!.activeMember;
    return calculateStats(
      baseStats: monster.definition.baseStats,
      individualValues: monster.definition.individualValues,
      level: monster.state.level,
      statCalculationVersion: monster.definition.statCalculationVersion,
    ).speed;
  }

  final playerSpeed = speedOf(side: BattleSideId.player);
  final opponentSpeed = speedOf(side: BattleSideId.opponent);
  final playerMovesFirst = playerSpeed != opponentSpeed
      ? playerSpeed > opponentSpeed
      : random.nextUint32() % 2 == 0;
  final order = playerMovesFirst
      ? [BattleSideId.player, BattleSideId.opponent]
      : [BattleSideId.opponent, BattleSideId.player];

  for (final attackerSide in order) {
    final attacker = parties[attackerSide]!.activeMember;
    if (attacker.isFainted) {
      continue;
    }
    final defenderSide = _otherSide(side: attackerSide);
    final defender = parties[defenderSide]!.activeMember;
    final action = actions[attackerSide]!;
    final move = switch (action) {
      UseMoveAction(:final moveId) => master.moveById(moveId: moveId),
      StruggleAction() => null,
    };

    final attackerStats = calculateStats(
      baseStats: attacker.definition.baseStats,
      individualValues: attacker.definition.individualValues,
      level: attacker.state.level,
      statCalculationVersion: attacker.definition.statCalculationVersion,
    );
    final defenderStats = calculateStats(
      baseStats: defender.definition.baseStats,
      individualValues: defender.definition.individualValues,
      level: defender.state.level,
      statCalculationVersion: defender.definition.statCalculationVersion,
    );
    final typeMultiplier = totalTypeMultiplier(
      moveElementTypeId: move?.elementTypeId,
      defenderElementTypeIds: defender.definition.elementTypeIds,
      master: master,
    );
    final damage = move != null && move.category == MoveCategory.support
        ? 0
        : calculateDamage(
            attackerLevel: attacker.state.level,
            power: move?.power ?? strugglePower,
            attack: attackerStats.attack,
            defense: defenderStats.defense,
            typeMultiplier: typeMultiplier,
            randomPercent: random.nextIntInRange(
              minimum: damageRandomMinimumPercent,
              maximum: 100,
            ),
          );
    final defenderRemainingHitPoints = math.max(
      0,
      defender.state.currentHitPoints - damage,
    );

    if (move != null) {
      parties[attackerSide] = _replaceActiveMemberState(
        party: parties[attackerSide]!,
        state: attacker.state.copyWith(
          remainingPowerPoints: {
            ...attacker.state.remainingPowerPoints,
            move.id: attacker.state.remainingPowerPoints[move.id]! - 1,
          },
        ),
      );
    }
    parties[defenderSide] = _replaceActiveMemberState(
      party: parties[defenderSide]!,
      state: defender.state.copyWith(
        currentHitPoints: defenderRemainingHitPoints,
      ),
    );
    events.add(
      MoveUsedEvent(
        turnNumber: state.turnNumber,
        attackerSide: attackerSide,
        attackerMonsterId: attacker.definition.id,
        moveId: move?.id,
        typeMultiplier: typeMultiplier,
        damage: damage,
        defenderRemainingHitPoints: defenderRemainingHitPoints,
      ),
    );
    if (defenderRemainingHitPoints == 0) {
      events.add(
        MonsterFaintedEvent(
          turnNumber: state.turnNumber,
          side: defenderSide,
          monsterId: defender.definition.id,
        ),
      );
    }
  }

  BattleSideId? winner;
  for (final side in BattleSideId.values) {
    final party = parties[side]!;
    if (!party.activeMember.isFainted) {
      continue;
    }
    if (party.isDefeated) {
      winner = _otherSide(side: side);
      continue;
    }
    final nextMemberIndex = party.members.indexWhere(
      (member) => !member.isFainted,
    );
    parties[side] = BattleParty(
      members: party.members,
      activeMemberIndex: nextMemberIndex,
    );
    events.add(
      MonsterSwitchedInEvent(
        turnNumber: state.turnNumber,
        side: side,
        monsterId: party.members[nextMemberIndex].definition.id,
      ),
    );
  }

  if (winner != null) {
    for (final side in BattleSideId.values) {
      final party = parties[side]!;
      // 交代は倒れていない最も前のモンスターを出し、倒れるのは場に出ている間だけのため、
      // 手持ちは先頭から順に場に出る。場に出たことがあるのは activeMemberIndex 以下の位置のモンスター。
      parties[side] = BattleParty(
        members: [
          for (final (memberIndex, member) in party.members.indexed)
            memberIndex <= party.activeMemberIndex
                ? BattleMonster(
                    definition: member.definition,
                    state: member.state.copyWith(
                      level: math.min(member.state.level + 1, maximumLevel),
                      experience: member.state.experience + 1,
                    ),
                  )
                : member,
        ],
        activeMemberIndex: party.activeMemberIndex,
      );
      for (final member in parties[side]!.members.take(
        party.activeMemberIndex + 1,
      )) {
        events.add(
          LevelUpEvent(
            turnNumber: state.turnNumber,
            side: side,
            monsterId: member.definition.id,
            newLevel: member.state.level,
          ),
        );
      }
    }
    events.add(
      BattleFinishedEvent(turnNumber: state.turnNumber, winner: winner),
    );
  }

  return BattleState(
    player: parties[BattleSideId.player]!,
    opponent: parties[BattleSideId.opponent]!,
    turnNumber: state.turnNumber + 1,
    randomState: random.state,
    events: events,
    winner: winner,
  );
}

/// [side] の相手の陣営を返す。
BattleSideId _otherSide({required BattleSideId side}) => switch (side) {
  BattleSideId.player => BattleSideId.opponent,
  BattleSideId.opponent => BattleSideId.player,
};

/// [action] を [monster] が選べるかを確かめ、選べなければ [ArgumentError] を投げる。
void _validateAction({
  required BattleMonster monster,
  required BattleAction action,
  required MasterData master,
}) {
  final moves = selectableMoves(monster: monster, master: master);
  switch (action) {
    case UseMoveAction(:final moveId):
      if (!moves.any((move) => move.id == moveId)) {
        throw ArgumentError('技 $moveId は PP が 0 か、まだ使えない');
      }
    case StruggleAction():
      if (moves.any((move) => move.category == MoveCategory.attack)) {
        throw ArgumentError('使える攻撃技があるため、わるあがきは選べない');
      }
  }
}

/// [party] の場のモンスターの状態を [state] に置き換えた陣営を返す。
BattleParty _replaceActiveMemberState({
  required BattleParty party,
  required MonsterState state,
}) => BattleParty(
  members: [
    for (final (index, member) in party.members.indexed)
      index == party.activeMemberIndex
          ? BattleMonster(definition: member.definition, state: state)
          : member,
  ],
  activeMemberIndex: party.activeMemberIndex,
);
