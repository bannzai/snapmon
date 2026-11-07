import 'dart:math' as math;

import '../master/master_data.dart';
import '../master/move.dart';
import '../monster/monster_definition.dart';
import '../monster/monster_state.dart';
import '../monster/monster_stats.dart';
import '../monster/stat_calculation.dart';
import '../random/deterministic_random.dart';
import 'battle_state.dart';
import 'move_special_effect.dart';

/// わるあがきの威力。技を使い切った方が得にならないよう、master の版 1 で最も弱い攻撃技の威力 (40) と同じにした。
/// 版 2 で足した威力 35 の技より強いが、わるあがきは攻撃技をすべて使い切った後にしか選べず、
/// 同時に持つ他の技 (威力 40〜50) より強くはならないため据え置いた。
const int strugglePower = 40;

/// ダメージの乱数幅の下限 (%)。上限は 100%。同じ組み合わせでも結果が揺れる程度にしつつ、
/// 下限 (0.85) が相性 2 倍・0.5 倍の差を覆さない幅にした。
const int damageRandomMinimumPercent = 85;

/// 補助技で変わるステータスの倍率 (%) の下限 (重ねがけの上限)。master の補助技は 1 回で 25 ずつ変えるため、下げる技を 2 回重ねた所で止まる。
/// 半分より下げると、防御を下げられた側が 1〜2 ターンで倒れて相性と技の選択が勝敗に効かなくなるため半分にした。
const int statModifierPercentMinimum = 50;

/// 補助技で変わるステータスの倍率 (%) の上限 (重ねがけの上限)。上げる技を 4 回重ねた所で止まる。
/// 攻撃技の特殊効果の倍率の上限 (その場で作る技の 200。documents/game-rules.md「技の特殊効果」) と揃え、1 つの効果で 2 倍を超えないようにした。
const int statModifierPercentMaximum = 200;

/// CPU が使える補助技を持つ時に、攻撃技の代わりに補助技を選ぶ確率の分母。1/4 は技の枠 4 つの 1 つ分で、
/// 補助技ばかり選んで攻撃しない CPU にならず、1 戦 (数ターン) に 1 回は補助技を見せる割合にした。
const int cpuSupportMoveChanceDenominator = 4;

/// CPU の技選びの乱数の seed を、バトルの乱数の状態から作る時に混ぜる値 (黄金比の 32bit の定数 0x9E3779B9)。
/// 同じターンの行動順・ダメージの乱数と同じ列を使わないため (同じ値の列だと、同じ速さの時の行動順と CPU の技選びが連動する)。
const int _cpuRandomSeedSalt = 0x9E3779B9;

/// [definition] のモンスターを、[level]・[experience] で HP・PP を満タンにし、ステータスの倍率を等倍にした状態でバトルに出す。
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
    statModifierPercents: const {},
  ),
);

/// [monster] の [statKind] の今の倍率 (%)。補助技で変わっていなければ 100。
int statModifierPercentOf({
  required BattleMonster monster,
  required StatKind statKind,
}) => monster.state.statModifierPercents[statKind] ?? 100;

/// [monster] の今のレベルのステータスに、補助技で変わった倍率を掛けた値 (小数点以下は切り捨て、1 以上) を返す。HP は倍率を持たない。
/// ダメージ・行動順・技の式の変数に使う。
MonsterStats effectiveStats({required BattleMonster monster}) {
  final stats = calculateStats(
    baseStats: monster.definition.baseStats,
    individualValues: monster.definition.individualValues,
    level: monster.state.level,
    statCalculationVersion: monster.definition.statCalculationVersion,
  );
  // 1 未満にしないのは、防御が 0 だとダメージ式が 0 で割るため
  int modified({required StatKind statKind}) => math.max(
    1,
    stats.valueOf(statKind: statKind) *
        statModifierPercentOf(monster: monster, statKind: statKind) ~/
        100,
  );
  return MonsterStats(
    hitPoints: stats.hitPoints,
    attack: modified(statKind: StatKind.attack),
    defense: modified(statKind: StatKind.defense),
    speed: modified(statKind: StatKind.speed),
  );
}

/// 両陣営の手持ち ([prepareBattleMonster] で用意した 1〜3 体) でバトルを始める。
/// [randomSeed] は行動順の同速判定とダメージの乱数幅に使い、同じ seed と同じ行動からは同じ結果になる。
/// [battleDate] は対戦日で、技の特殊効果の入力に渡す。
BattleState startBattle({
  required List<BattleMonster> playerMembers,
  required List<BattleMonster> opponentMembers,
  required int randomSeed,
  required DateTime battleDate,
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
    battleDate: battleDate,
  );
}

/// 1 体が同時に使える技の数。バトル画面の技の枠の数で、生まれた時に Lv.1 でそろう技の数
/// (functions/src/generation/monster_stats.ts の `STARTING_MOVE_COUNT`) と同じ値。
const int maximumEquippedMoveCount = 4;

/// [learnset] のうち、[level] で使える技 (開放済みの技のうち、覚える技の一覧で後ろの [maximumEquippedMoveCount] 個) を一覧の順で返す。
/// 開放済みの技が枠より多い時は、新しく覚えた技が一番古い技と入れ替わる (documents/game-rules.md「技」)。
List<LearnsetEntry> equippedLearnsetEntries({
  required List<LearnsetEntry> learnset,
  required int level,
}) {
  final unlockedEntries = [
    for (final learnsetEntry in learnset)
      if (learnsetEntry.unlockLevel <= level) learnsetEntry,
  ];
  return unlockedEntries.sublist(
    math.max(0, unlockedEntries.length - maximumEquippedMoveCount),
  );
}

/// [monster] が今使える技 ([equippedLearnsetEntries] のうち PP が残っている技) を、覚える技の一覧の順で返す。
/// 攻撃技が 1 つも無ければわるあがき ([StruggleAction]) も選べる (補助技だけが残って決着しなくなるのを防ぐため)。
List<Move> selectableMoves({
  required BattleMonster monster,
  required MasterData master,
}) => [
  for (final learnsetEntry in equippedLearnsetEntries(
    learnset: monster.definition.learnset,
    level: monster.state.level,
  ))
    if ((monster.state.remainingPowerPoints[learnsetEntry.moveId] ?? 0) > 0)
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

/// CPU の行動を返す。効果のある補助技を持つ時は 1/[cpuSupportMoveChanceDenominator] の確率でその中から 1 つを選ぶ。
/// それ以外は、相手の場のモンスターへの相性の倍率が最大の攻撃技を選び、
/// 倍率が同じなら威力が高い技、それも同じなら覚える技の一覧で先の技を選ぶ。使える攻撃技が無ければわるあがき。
/// 効果のある補助技は、HP の回復だけをする技なら HP が減っている時だけ、ステータスを変える技なら変える先のどれかが重ねがけの上限に達していない時だけ。
/// 乱数は [state] の乱数の状態とターン数・陣営から作った別の列で引き、[state] の乱数の状態は進めない
/// (同じ状態からは同じ行動を選び、プレイヤーの行動順・ダメージの乱数を変えないため)。
BattleAction chooseCpuAction({
  required BattleState state,
  required BattleSideId side,
  required MasterData master,
}) {
  final attacker = state.partyOf(side: side).activeMember;
  final defender = state.partyOf(side: _otherSide(side: side)).activeMember;
  final moves = selectableMoves(monster: attacker, master: master);
  bool canStillChange({
    required BattleMonster monster,
    required Map<StatKind, String> statChanges,
  }) => statChanges.keys.any((statKind) {
    final percent = statModifierPercentOf(monster: monster, statKind: statKind);
    return percent > statModifierPercentMinimum &&
        percent < statModifierPercentMaximum;
  });
  final effectiveSupportMoves = [
    for (final move in moves)
      if (move.category == MoveCategory.support &&
          move.specialEffect != null &&
          ((move.specialEffect!.selfHitPointsRecovery != null &&
                  attacker.state.currentHitPoints <
                      effectiveStats(monster: attacker).hitPoints) ||
              canStillChange(
                monster: attacker,
                statChanges: move.specialEffect!.selfStatChanges,
              ) ||
              canStillChange(
                monster: defender,
                statChanges: move.specialEffect!.opponentStatChanges,
              )))
        move,
  ];
  if (effectiveSupportMoves.isNotEmpty) {
    final cpuRandom = DeterministicRandom(
      seed:
          state.randomState ^
          _cpuRandomSeedSalt ^
          (state.turnNumber << 1) ^
          side.index,
    );
    if (cpuRandom.nextUint32() % cpuSupportMoveChanceDenominator == 0) {
      return UseMoveAction(
        moveId:
            effectiveSupportMoves[cpuRandom.nextUint32() %
                    effectiveSupportMoves.length]
                .id,
      );
    }
  }
  Move? bestMove;
  var bestMultiplier = 0.0;
  for (final move in moves) {
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
/// 技の威力には特殊効果の倍率 ([calculateMoveSpecialEffect]) を掛ける (小数点以下は切り捨て)。
/// 補助技はダメージを与えず、特殊効果の式 ([calculateMoveStatusEffect]) でステータスの倍率を変え、HP を回復する。
/// ステータスの倍率は場のモンスターに付き、そのバトルの間 (倒れるまで) 続く。ダメージ・行動順・技の式の変数は倍率を掛けた値 ([effectiveStats]) を使う。
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

  final playerSpeed = effectiveStats(
    monster: parties[BattleSideId.player]!.activeMember,
  ).speed;
  final opponentSpeed = effectiveStats(
    monster: parties[BattleSideId.opponent]!.activeMember,
  ).speed;
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

    final attackerStats = effectiveStats(monster: attacker);
    final defenderStats = effectiveStats(monster: defender);
    final typeMultiplier = totalTypeMultiplier(
      moveElementTypeId: move?.elementTypeId,
      defenderElementTypeIds: defender.definition.elementTypeIds,
      master: master,
    );
    final variables = move == null
        ? null
        : moveExpressionVariables(
            move: move,
            attacker: attacker,
            defender: defender,
            attackerStats: attackerStats,
            defenderStats: defenderStats,
            attackerMovesFirst: attackerSide == order.first,
            battleDate: state.battleDate,
          );
    final specialEffect = move == null
        ? null
        : calculateMoveSpecialEffect(move: move, variables: variables!);
    final statusEffect = move == null
        ? null
        : calculateMoveStatusEffect(move: move, variables: variables!);
    final damage = move != null && move.category == MoveCategory.support
        ? 0
        : calculateDamage(
            attackerLevel: attacker.state.level,
            power: move == null
                ? strugglePower
                // 特殊効果の無い技は威力をそのまま使うため、倍率 100% (1 倍) とみなす
                : move.power * (specialEffect?.powerPercent ?? 100) ~/ 100,
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
    final attackerRemainingHitPoints = math.min(
      attackerStats.hitPoints,
      attacker.state.currentHitPoints + (statusEffect?.hitPointsRecovery ?? 0),
    );
    final attackerStatModifiers = _applyStatChanges(
      monster: attacker,
      side: attackerSide,
      changes: statusEffect?.selfStatChanges ?? const {},
    );
    final defenderStatModifiers = _applyStatChanges(
      monster: defender,
      side: defenderSide,
      changes: statusEffect?.opponentStatChanges ?? const {},
    );

    parties[attackerSide] = _replaceActiveMemberState(
      party: parties[attackerSide]!,
      state: attacker.state.copyWith(
        currentHitPoints: attackerRemainingHitPoints,
        remainingPowerPoints: move == null
            ? null
            : {
                ...attacker.state.remainingPowerPoints,
                move.id: attacker.state.remainingPowerPoints[move.id]! - 1,
              },
        statModifierPercents: attackerStatModifiers.percents,
      ),
    );
    parties[defenderSide] = _replaceActiveMemberState(
      party: parties[defenderSide]!,
      state: defender.state.copyWith(
        currentHitPoints: defenderRemainingHitPoints,
        statModifierPercents: defenderStatModifiers.percents,
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
        specialEffect: specialEffect,
        statModifierChanges: [
          ...attackerStatModifiers.changes,
          ...defenderStatModifiers.changes,
        ],
        recoveredHitPoints:
            attackerRemainingHitPoints - attacker.state.currentHitPoints,
        attackerRemainingHitPoints: attackerRemainingHitPoints,
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
    battleDate: state.battleDate,
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

/// [monster] ([side] の場のモンスター) のステータスの倍率に [changes] (倍率に足す値) を足し、重ねがけの上限
/// ([statModifierPercentMinimum]〜[statModifierPercentMaximum]) で丸めた倍率と、変化の結果 (値が 0 の変化は除く) を返す。
({Map<StatKind, int> percents, List<StatModifierChange> changes})
_applyStatChanges({
  required BattleMonster monster,
  required BattleSideId side,
  required Map<StatKind, int> changes,
}) {
  final percents = {...monster.state.statModifierPercents};
  final statModifierChanges = <StatModifierChange>[];
  for (final MapEntry(key: statKind, value: change) in changes.entries) {
    if (change == 0) {
      continue;
    }
    final previousPercent = statModifierPercentOf(
      monster: monster,
      statKind: statKind,
    );
    final newPercent = (previousPercent + change).clamp(
      statModifierPercentMinimum,
      statModifierPercentMaximum,
    );
    percents[statKind] = newPercent;
    statModifierChanges.add(
      StatModifierChange(
        side: side,
        statKind: statKind,
        previousPercent: previousPercent,
        newPercent: newPercent,
      ),
    );
  }
  return (percents: percents, changes: statModifierChanges);
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
