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
import 'status_condition.dart';

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

/// 眩暈の時の命中率の倍率 (%)。命中率 100 の技が 7 割で当たる程度にし、3 ターンの間に 1 回は外れる体感になる値にした。
const int dizzyAccuracyPercent = 70;

/// 気絶・眠り・凍結・麻痺の持ち主が、自分のターンに行動を止められる確率 (%)。
/// 必ず止めると付けられた側が一方的に何もできないため確率にした (issue #260 の「確定はきつい」)。
/// 混乱が別の技を出す確率 (1/2) と揃え、1 ターンだけの麻痺・気絶でも付ける意味が残る 5 割にした。
const int actionPreventingStatusConditionChancePercent = 50;

/// 毒のダメージの分母。最大 HP × 重なり / この値のダメージを、持ち主のターンの終わりに受ける。
/// 重なり 1 で 16 ターン、上限の重なり 4 で 4 ターンかけて倒れる速さにした。
const int poisonDamageDenominator = 16;

/// CPU が使える補助技を持つ時に、攻撃技の代わりに補助技を選ぶ確率の分母。1/4 は技の枠 4 つの 1 つ分で、
/// 補助技ばかり選んで攻撃しない CPU にならず、1 戦 (数ラウンド) に 1 回は補助技を見せる割合にした。
const int cpuSupportMoveChanceDenominator = 4;

/// CPU が一撃必殺の技を持つ時にそれを選ぶ確率の分母。命中率が低く外れると 1 ターンを失うため、補助技と同じ 1/4 にした。
const int cpuOneHitKnockoutChanceDenominator = 4;

/// CPU が自爆の技を選ぶ時の、自分の残り HP の最大 HP に対する割合の分母。残り HP がこの割合 (1/4) 以下の時だけ 1/2 の確率で選ぶ。
const int cpuSelfDestructHitPointsDenominator = 4;

/// CPU との対戦で、CPU が与えるダメージに掛ける割合 (%)。根拠は documents/DIRECTION.md「決めたこと」の 2026-11-09 の行 (issue #240)。
/// 本番の種族値の利用者が技を乱数で選ぶ時の Lv.1 の勝率を 6 割以上にする値のうち、Lv.20 で相性の最善を選ぶ利用者の勝率が 75% を超えない値
/// (test/domain/battle/cpu_strength_test.dart と同じ組み合わせの 900 戦で、100% は 38.1%、75% は 51.3%、60% は 60.0%、50% は 66.3%。
/// 50% の時の Lv.20 の最善を選ぶ利用者は 52.1%)。60% は目標の境目で、乱数の幅 (約 ±3 ポイント) で下回るため 50% にした。
/// Lv.1 はステータスの式の切り捨てでどのモンスターも HP 12〜13・攻撃 5〜7 にそろい、種族値を下げても勝率が 5 割前後で止まるため、ダメージで補正する。
const int cpuDamagePercent = 50;

/// CPU の技選びの乱数の seed を、バトルの乱数の状態から作る時に混ぜる値 (黄金比の 32bit の定数 0x9E3779B9)。
/// 同じラウンドの行動順・ダメージの乱数と同じ列を使わないため (同じ値の列だと、同じ速さの時の行動順と CPU の技選びが連動する)。
const int _cpuRandomSeedSalt = 0x9E3779B9;

/// [definition] のモンスターを、[level]・[experience] で HP・PP を満タンにし、ステータスの倍率を等倍、状態なしにしてバトルに出す。
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
    statusConditions: const {},
  ),
);

/// [monster] の [statKind] の今の倍率 (%)。補助技で変わっていなければ 100。
int statModifierPercentOf({
  required BattleMonster monster,
  required StatKind statKind,
}) => monster.state.statModifierPercents[statKind] ?? 100;

/// [monster] の今のレベルのステータスに、補助技で変わった倍率と状態の効果 (眠気・呪い・興奮) を掛け、
/// フィールドの入れ替え ([field]) を反映した値 (小数点以下は切り捨て、1 以上) を返す。HP は倍率を持たない。
/// ダメージ・行動順・技の式の変数に使う。
MonsterStats effectiveStats({
  required BattleMonster monster,
  BattleField? field,
}) {
  final stats = calculateStats(
    baseStats: monster.definition.baseStats,
    individualValues: monster.definition.individualValues,
    level: monster.state.level,
    statCalculationVersion: monster.definition.statCalculationVersion,
  );
  final statusConditions = monster.state.statusConditions;
  // 1 未満にしないのは、防御が 0 だとダメージ式が 0 で割るため
  int modified({required StatKind statKind}) {
    var value =
        stats.valueOf(statKind: statKind) *
        statModifierPercentOf(monster: monster, statKind: statKind) ~/
        100;
    if (statusConditions[StatusConditionKind.curse]?.cursedStatKind ==
        statKind) {
      value ~/= 2;
    }
    if (statKind == StatKind.speed &&
        statusConditions.containsKey(StatusConditionKind.drowsy)) {
      value ~/= 2;
    }
    if (statusConditions.containsKey(StatusConditionKind.excited)) {
      value = switch (statKind) {
        StatKind.attack => value * 3 ~/ 2,
        StatKind.defense => value ~/ 2,
        StatKind.hitPoints || StatKind.speed => value,
      };
    }
    return math.max(1, value);
  }

  final modifiedStats = {
    for (final statKind in modifiableStatKinds)
      statKind: modified(statKind: statKind),
  };
  if (field?.swappedStatKinds case (final first, final second)) {
    final firstValue = modifiedStats[first]!;
    modifiedStats[first] = modifiedStats[second]!;
    modifiedStats[second] = firstValue;
  }
  return MonsterStats(
    hitPoints: stats.hitPoints,
    attack: modifiedStats[StatKind.attack]!,
    defense: modifiedStats[StatKind.defense]!,
    speed: modifiedStats[StatKind.speed]!,
  );
}

/// 両陣営の手持ち ([prepareBattleMonster] で用意した 1〜3 体) でバトルを始める。
/// [randomSeed] は行動順の同速判定・ダメージの乱数幅・命中・状態・状態で行動が止まるか・混乱・入れ替えに使い、同じ seed と同じ行動からは同じ結果になる。
/// [battleDate] は対戦日で、技の特殊効果の入力に渡す。
/// [opponentDamagePercent] は相手の陣営が与えるダメージに掛ける割合 (%) で、CPU との対戦は [cpuDamagePercent]、補正しないなら 100。
BattleState startBattle({
  required List<BattleMonster> playerMembers,
  required List<BattleMonster> opponentMembers,
  required int randomSeed,
  required DateTime battleDate,
  required int opponentDamagePercent,
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
    field: null,
    opponentDamagePercent: opponentDamagePercent,
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

/// [learnset] のモンスターが [previousLevel] から [newLevel] に上がった時の技の枠 ([equippedLearnsetEntries]) の変化を返す。
/// `learnedEntries` は新しく枠に入った技、`forgottenEntries` は入れ替わりで枠から外れた技で、どちらも覚える技の一覧の順。
/// 枠が変わらなければどちらも空 (バトルの後に覚えた技を知らせるため。#247)。
({List<LearnsetEntry> learnedEntries, List<LearnsetEntry> forgottenEntries})
equippedLearnsetChanges({
  required List<LearnsetEntry> learnset,
  required int previousLevel,
  required int newLevel,
}) {
  final previousEntries = equippedLearnsetEntries(
    learnset: learnset,
    level: previousLevel,
  );
  final newEntries = equippedLearnsetEntries(
    learnset: learnset,
    level: newLevel,
  );
  return (
    learnedEntries: [
      for (final learnsetEntry in newEntries)
        if (!previousEntries.contains(learnsetEntry)) learnsetEntry,
    ],
    forgottenEntries: [
      for (final learnsetEntry in previousEntries)
        if (!newEntries.contains(learnsetEntry)) learnsetEntry,
    ],
  );
}

/// [learnset] のうち [level] より後に開放される技の、最も低い開放レベル。もう覚える技が無ければ null。
int? nextLearnsetUnlockLevel({
  required List<LearnsetEntry> learnset,
  required int level,
}) => learnset
    .map((learnsetEntry) => learnsetEntry.unlockLevel)
    .where((unlockLevel) => unlockLevel > level)
    .fold<int?>(
      null,
      (lowest, unlockLevel) =>
          lowest == null ? unlockLevel : math.min(lowest, unlockLevel),
    );

/// [move] が通常の攻撃技 (自爆・一撃必殺を除く攻撃技) か。わるあがきを選べるのはこれが 1 つも残っていない時で、
/// 自爆と一撃必殺だけが残った時に自爆か賭けしか選べなくならないようにする (version 9 の技の枠には自爆と一撃必殺だけが残るレベル帯がある)。
bool isOrdinaryAttackMove(Move move) =>
    move.category == MoveCategory.attack &&
    !(move.specialEffect?.selfDestructs ?? false) &&
    !(move.specialEffect?.isOneHitKnockout ?? false);

/// [monster] が今使える技 ([equippedLearnsetEntries] のうち PP が残っている技) を、覚える技の一覧の順で返す。
/// 通常の攻撃技 ([isOrdinaryAttackMove]) が 1 つも無ければわるあがき ([StruggleAction]) も選べる (補助技だけが残って決着しなくなるのを防ぐため)。
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

/// [move] を [defender] に使った時にダメージに掛かる相性の倍率を返す。技のボタンに相性を出すために使う。
/// 相性が効かない技 (ダメージの無い補助技と、相性に関係なく HP を 0 にする一撃必殺) は null を返す
/// ([advanceRound] のダメージの計算と、ログに相性を出さない技の規則 (documents/game-rules.md「補助技」「一撃必殺」) と揃える)。
double? moveTypeMultiplierAgainst({
  required Move move,
  required BattleMonster defender,
  required MasterData master,
}) =>
    move.category == MoveCategory.support ||
        (move.specialEffect?.isOneHitKnockout ?? false)
    ? null
    : totalTypeMultiplier(
        moveElementTypeId: move.elementTypeId,
        defenderElementTypeIds: defender.definition.elementTypeIds,
        master: master,
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

/// 毒の重なり [stackCount] で、最大 HP [maximumHitPoints] のモンスターが 1 ターンに受けるダメージ (1 以上)。
int poisonDamage({required int maximumHitPoints, required int stackCount}) =>
    math.max(1, maximumHitPoints * stackCount ~/ poisonDamageDenominator);

/// [move] (わるあがきは null) の今回の命中率 (%)。必中の技は 100。眩暈の時は [dizzyAccuracyPercent] を掛ける。
int moveHitChancePercent({
  required Move? move,
  required BattleMonster attacker,
}) {
  if (move?.specialEffect?.isSureHit ?? false) {
    return 100;
  }
  final accuracy = move?.accuracy ?? defaultMoveAccuracyPercent;
  return attacker.state.statusConditions.containsKey(StatusConditionKind.dizzy)
      ? accuracy * dizzyAccuracyPercent ~/ 100
      : accuracy;
}

/// [monster] に状態 [kind] を付けようとした時に、何かが変わるか (CPU が効果のある補助技を選ぶ判定に使う)。
/// 重なる状態は上限まで、眠気は眠りになるまで、他は持っていなければ変わる。
bool canInflictStatusCondition({
  required BattleMonster monster,
  required StatusConditionKind kind,
}) {
  final current = monster.state.statusConditions[kind];
  final stackMaximum = statusConditionStackMaximums[kind];
  if (stackMaximum != null) {
    return current == null || current.stackCount < stackMaximum;
  }
  return switch (kind) {
    StatusConditionKind.drowsy => !monster.state.statusConditions.containsKey(
      StatusConditionKind.sleep,
    ),
    StatusConditionKind.curse || StatusConditionKind.excited => current == null,
    _ => true,
  };
}

/// CPU の行動を返す。効果のある補助技を持つ時は 1/[cpuSupportMoveChanceDenominator] の確率でその中から 1 つを選ぶ。
/// 一撃必殺の技を持つ時は 1/[cpuOneHitKnockoutChanceDenominator] の確率で、自爆の技は残り HP が最大 HP の
/// 1/[cpuSelfDestructHitPointsDenominator] 以下の時に 1/2 の確率で選ぶ。
/// それ以外は、相手の場のモンスターへの相性の倍率が最大の攻撃技 (一撃必殺・自爆を除く) を選び、
/// 倍率が同じなら威力 × 命中率が高い技、それも同じなら覚える技の一覧で先の技を選ぶ。通常の攻撃技が無ければわるあがき
/// (一撃必殺・自爆だけが残っていても、上の確率と HP の条件で選ばなかった時は使わない。利用者がわるあがきを選べる条件と同じ)。
/// 効果のある補助技は、HP の回復だけをする技なら HP が減っている時だけ、ステータスを変える技なら変える先のどれかが重ねがけの上限に達していない時、
/// 状態を付ける技なら付ける先に変化がある時、状態を解除する技なら自分に状態がある時、フィールドの技ならフィールドが無い時だけ。
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
  final cpuRandom = DeterministicRandom(
    seed:
        state.randomState ^
        _cpuRandomSeedSalt ^
        (state.turnNumber << 1) ^
        side.index,
  );
  bool canStillChange({
    required BattleMonster monster,
    required Map<StatKind, String> statChanges,
  }) => statChanges.keys.any((statKind) {
    final percent = statModifierPercentOf(monster: monster, statKind: statKind);
    return percent > statModifierPercentMinimum &&
        percent < statModifierPercentMaximum;
  });
  bool isEffectiveSupportMove({required Move move}) {
    final specialEffect = move.specialEffect;
    if (move.category != MoveCategory.support || specialEffect == null) {
      return false;
    }
    return (specialEffect.selfHitPointsRecovery != null &&
            attacker.state.currentHitPoints <
                effectiveStats(monster: attacker).hitPoints) ||
        canStillChange(
          monster: attacker,
          statChanges: specialEffect.selfStatChanges,
        ) ||
        canStillChange(
          monster: defender,
          statChanges: specialEffect.opponentStatChanges,
        ) ||
        specialEffect.selfStatusConditions.any(
          (infliction) => canInflictStatusCondition(
            monster: attacker,
            kind: infliction.kind,
          ),
        ) ||
        specialEffect.opponentStatusConditions.any(
          (infliction) => canInflictStatusCondition(
            monster: defender,
            kind: infliction.kind,
          ),
        ) ||
        (specialEffect.curesSelfStatusConditions &&
            attacker.state.statusConditions.isNotEmpty) ||
        (specialEffect.fieldEffect != null && state.field == null);
  }

  final effectiveSupportMoves = [
    for (final move in moves)
      if (isEffectiveSupportMove(move: move)) move,
  ];
  if (effectiveSupportMoves.isNotEmpty &&
      cpuRandom.nextUint32() % cpuSupportMoveChanceDenominator == 0) {
    return UseMoveAction(
      moveId:
          effectiveSupportMoves[cpuRandom.nextUint32() %
                  effectiveSupportMoves.length]
              .id,
    );
  }
  final oneHitKnockoutMove = moves
      .where((move) => move.specialEffect?.isOneHitKnockout ?? false)
      .firstOrNull;
  if (oneHitKnockoutMove != null &&
      cpuRandom.nextUint32() % cpuOneHitKnockoutChanceDenominator == 0) {
    return UseMoveAction(moveId: oneHitKnockoutMove.id);
  }
  final selfDestructMove = moves
      .where((move) => move.specialEffect?.selfDestructs ?? false)
      .firstOrNull;
  if (selfDestructMove != null &&
      attacker.state.currentHitPoints * cpuSelfDestructHitPointsDenominator <=
          effectiveStats(monster: attacker).hitPoints &&
      cpuRandom.nextUint32() % 2 == 0) {
    return UseMoveAction(moveId: selfDestructMove.id);
  }
  Move? bestMove;
  var bestMultiplier = 0.0;
  for (final move in moves) {
    if (!isOrdinaryAttackMove(move)) {
      continue;
    }
    final multiplier = totalTypeMultiplier(
      moveElementTypeId: move.elementTypeId,
      defenderElementTypeIds: defender.definition.elementTypeIds,
      master: master,
    );
    if (bestMove == null ||
        multiplier > bestMultiplier ||
        (multiplier == bestMultiplier &&
            move.power * move.accuracy > bestMove.power * bestMove.accuracy)) {
      bestMove = move;
      bestMultiplier = multiplier;
    }
  }
  // 通常の攻撃技が無ければわるあがき。一撃必殺・自爆は上の確率と HP の条件で選ばなかった時に使わない (利用者と同じ規則で、自爆を強いない)
  return bestMove == null
      ? const StruggleAction()
      : UseMoveAction(moveId: bestMove.id);
}

/// 両陣営の行動 [playerAction]・[opponentAction] で 1 ラウンド (両陣営 1 ターンずつ) を解決し、次の状態を返す。
///
/// ラウンドの始めに入れ替えのフィールドがあれば、残りのラウンドが 0 なら終わり、あれば攻撃・防御・素早さから 2 つを乱数で選んで入れ替える。
/// 交代 ([SwitchMonsterAction]) は技より先に行い、ターンの終わりの処理をしない。技どうしは先制の度合いが高い技が先、
/// 同じなら場のモンスターの素早さが高い順に行動し (同じなら乱数)、倒れたモンスターはそのターンの行動を失う。
/// 各ターンは、気絶・眠り・凍結なら [actionPreventingStatusConditionChancePercent] の確率で行動が失敗し (PP を使わない)、混乱なら 1/2 の確率で選んだ技の代わりに
/// 他の使える技が出て、麻痺なら実際に出る技が攻撃技かわるあがきの時に同じ確率で失敗し (PP を使わない)、命中率 (眩暈なら 70%) で外れる (PP を使う)。当たった技は、一撃必殺なら相手の HP を 0 にし、攻撃技なら威力に特殊効果の倍率
/// ([calculateMoveSpecialEffect]) を掛けたダメージ (やけどなら与えるダメージが半分、受ける側がやけどなら (10 + 重なり) / 10 倍) を与える。
/// 続けて特殊効果の式 ([calculateMoveStatusEffect]) でステータスの倍率を変え、HP を回復し、状態を付け・解除し、フィールドを始め、自爆する。
/// ダメージを受けた凍結は解け、毒の技を受けた毒は重なりが増える。ターンの終わりに毒のダメージを受け、残りのターンを持つ状態が 1 減って 0 なら消える。
/// ステータスの倍率と状態は場のモンスターに付き、倍率は交代で場を離れると等倍に戻り、状態はそのバトルの間 (倒れるまで) 続く。
/// ダメージ・行動順・技の式の変数は倍率と状態を反映した値 ([effectiveStats]) を使う。
/// ラウンドの終わりに倒れたモンスターを手持ちの次のモンスターと交代し、手持ちがすべて倒れた側が負ける。
/// 決着がついたら勝敗を問わず両陣営の、場に出たことがある手持ちのレベルを 1 上げる (上限 [maximumLevel]。
/// DIRECTION.md「必要な機能」の「1 戦ごとに、戦闘に出た手持ちのレベルが勝敗に関係なく 1 上がる」)。
/// 決着済みの状態・選べない行動 (PP が 0 か未開放の技、使える攻撃技があるのにわるあがき、倒れている・場にいるモンスターや
/// 交換不可の間の交代) には例外を投げる。
BattleState advanceRound({
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
      party: state.partyOf(side: entry.key),
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
  var field = state.field;
  final lastTurnNumber = state.turnNumber + 1;

  if (field != null) {
    if (field.remainingRounds <= 0) {
      events.add(
        FieldEffectEndedEvent(turnNumber: state.turnNumber, kind: field.kind),
      );
      field = null;
    } else {
      // 攻撃・防御・素早さから 2 つを選ぶ組は 3 通り
      final statKinds = switch (random.nextUint32() % 3) {
        0 => (StatKind.attack, StatKind.defense),
        1 => (StatKind.attack, StatKind.speed),
        _ => (StatKind.defense, StatKind.speed),
      };
      field = BattleField(
        kind: field.kind,
        remainingRounds: field.remainingRounds - 1,
        swappedStatKinds: statKinds,
      );
      events.add(
        FieldEffectShuffledEvent(
          turnNumber: state.turnNumber,
          statKinds: statKinds,
        ),
      );
    }
  }

  Move? moveOf({required BattleAction action}) => switch (action) {
    UseMoveAction(:final moveId) => master.moveById(moveId: moveId),
    StruggleAction() || SwitchMonsterAction() => null,
  };
  final playerSwitches = playerAction is SwitchMonsterAction;
  final playerPriority = moveOf(action: playerAction)?.priority ?? 0;
  final opponentPriority = moveOf(action: opponentAction)?.priority ?? 0;
  final playerSpeed = effectiveStats(
    monster: parties[BattleSideId.player]!.activeMember,
    field: field,
  ).speed;
  final opponentSpeed = effectiveStats(
    monster: parties[BattleSideId.opponent]!.activeMember,
    field: field,
  ).speed;
  // 交代は先制の度合い・素早さに関係なく技より先に行う (交代したモンスターが相手の技を受ける)
  final playerMovesFirst =
      playerSwitches != (opponentAction is SwitchMonsterAction)
      ? playerSwitches
      : playerPriority != opponentPriority
      ? playerPriority > opponentPriority
      : playerSpeed != opponentSpeed
      ? playerSpeed > opponentSpeed
      : random.nextUint32() % 2 == 0;
  final order = playerMovesFirst
      ? [BattleSideId.player, BattleSideId.opponent]
      : [BattleSideId.opponent, BattleSideId.player];

  void replaceActiveState({
    required BattleSideId side,
    required MonsterState monsterState,
  }) {
    parties[side] = _replaceActiveMemberState(
      party: parties[side]!,
      state: monsterState,
    );
  }

  for (final (turnIndex, attackerSide) in order.indexed) {
    final turnNumber = state.turnNumber + turnIndex;
    final attackerBeforeTurn = parties[attackerSide]!.activeMember;
    if (attackerBeforeTurn.isFainted) {
      continue;
    }
    final action = actions[attackerSide]!;
    // 交代は技ではないため、行動を止める状態 (気絶・眠り・凍結) でも行う。場を離れるモンスターのステータスの倍率は
    // 等倍に戻り、状態は残る。交代のターンはターンの終わりの処理 (毒のダメージ・残りのターン) をしない
    // (どちらのモンスターも場で行動していないため。documents/game-rules.md「1 ラウンドの流れ」)
    if (action case SwitchMonsterAction(:final memberIndex)) {
      final party = parties[attackerSide]!;
      parties[attackerSide] = BattleParty(
        members: [
          for (final (index, member) in party.members.indexed)
            index == party.activeMemberIndex
                ? BattleMonster(
                    definition: member.definition,
                    state: member.state.copyWith(
                      statModifierPercents: const {},
                    ),
                  )
                : member,
        ],
        activeMemberIndex: memberIndex,
      );
      events.add(
        MonsterSwitchedInEvent(
          turnNumber: turnNumber,
          side: attackerSide,
          monsterId: party.members[memberIndex].definition.id,
          withdrawnMonsterId: attackerBeforeTurn.definition.id,
        ),
      );
      continue;
    }
    final defenderSide = _otherSide(side: attackerSide);
    // 先に動いた側が自爆や毒で倒れていたら、後に動く側は技を使わない (倒れた相手に当てて PP を使い、倒れたログが重ならないため)。
    // 状態の残りのターンと毒のダメージは、行動しないターンでも進める
    if (parties[defenderSide]!.activeMember.isFainted) {
      _endTurn(
        parties: parties,
        side: attackerSide,
        turnNumber: turnNumber,
        events: events,
      );
      continue;
    }
    final selectedMove = moveOf(action: action);
    final attackerStatusConditions = attackerBeforeTurn.state.statusConditions;

    // 状態ごとに判定し、最初に止めた状態を失敗の理由にする。firstOrNull で止まるため、止めた後の状態の乱数は引かない
    final incapacitatingKind = incapacitatingStatusConditionKinds
        .where(attackerStatusConditions.containsKey)
        .where((_) => _rollsActionPrevention(random: random))
        .firstOrNull;
    if (incapacitatingKind != null) {
      events.add(
        ActionFailedEvent(
          turnNumber: turnNumber,
          side: attackerSide,
          monsterId: attackerBeforeTurn.definition.id,
          moveId: selectedMove?.id,
          reason: switch (incapacitatingKind) {
            StatusConditionKind.stun => ActionFailureReason.stun,
            StatusConditionKind.sleep => ActionFailureReason.sleep,
            _ => ActionFailureReason.frozen,
          },
        ),
      );
      _endTurn(
        parties: parties,
        side: attackerSide,
        turnNumber: turnNumber,
        events: events,
      );
      continue;
    }

    var move = selectedMove;
    String? replacedMoveId;
    if (move != null &&
        attackerStatusConditions.containsKey(StatusConditionKind.confusion)) {
      final otherMoves = [
        for (final candidate in selectableMoves(
          monster: attackerBeforeTurn,
          master: master,
        ))
          if (candidate.id != move.id) candidate,
      ];
      if (otherMoves.isNotEmpty && random.nextUint32() % 2 == 0) {
        replacedMoveId = move.id;
        move = otherMoves[random.nextUint32() % otherMoves.length];
      }
    }
    // 麻痺の判定は、混乱で置き換わった後の実際に出る技で行う (補助技を選んで攻撃技に置き換わった時も麻痺の判定を掛けるため)。
    // 乱数は攻撃技かわるあがきの時だけ引く (補助技は麻痺で止まらないため)
    if (attackerStatusConditions.containsKey(StatusConditionKind.paralysis) &&
        (move == null || move.category == MoveCategory.attack) &&
        _rollsActionPrevention(random: random)) {
      events.add(
        ActionFailedEvent(
          turnNumber: turnNumber,
          side: attackerSide,
          monsterId: attackerBeforeTurn.definition.id,
          moveId: move?.id,
          reason: ActionFailureReason.paralysis,
        ),
      );
      _endTurn(
        parties: parties,
        side: attackerSide,
        turnNumber: turnNumber,
        events: events,
      );
      continue;
    }
    final attacker = attackerBeforeTurn;
    final remainingPowerPoints = move == null
        ? attacker.state.remainingPowerPoints
        : {
            ...attacker.state.remainingPowerPoints,
            move.id: attacker.state.remainingPowerPoints[move.id]! - 1,
          };

    final hitChance = moveHitChancePercent(move: move, attacker: attacker);
    if (hitChance < 100 &&
        random.nextIntInRange(minimum: 1, maximum: 100) > hitChance) {
      replaceActiveState(
        side: attackerSide,
        monsterState: attacker.state.copyWith(
          remainingPowerPoints: remainingPowerPoints,
        ),
      );
      events.add(
        ActionFailedEvent(
          turnNumber: turnNumber,
          side: attackerSide,
          monsterId: attacker.definition.id,
          moveId: move?.id,
          reason: ActionFailureReason.missed,
        ),
      );
      _endTurn(
        parties: parties,
        side: attackerSide,
        turnNumber: turnNumber,
        events: events,
      );
      continue;
    }

    final defender = parties[defenderSide]!.activeMember;
    final attackerStats = effectiveStats(monster: attacker, field: field);
    final defenderStats = effectiveStats(monster: defender, field: field);
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
    final isOneHitKnockout = move?.specialEffect?.isOneHitKnockout ?? false;
    final int damage;
    if (isOneHitKnockout) {
      damage = defender.state.currentHitPoints;
    } else if (move != null && move.category == MoveCategory.support) {
      damage = 0;
    } else {
      var calculated = calculateDamage(
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
      if (attacker.state.statusConditions.containsKey(
        StatusConditionKind.burn,
      )) {
        calculated = math.max(1, calculated ~/ 2);
      }
      final defenderBurn =
          defender.state.statusConditions[StatusConditionKind.burn];
      if (defenderBurn != null) {
        calculated = calculated * (10 + defenderBurn.stackCount) ~/ 10;
      }
      if (attackerSide == BattleSideId.opponent) {
        calculated = math.max(
          1,
          calculated * state.opponentDamagePercent ~/ 100,
        );
      }
      damage = calculated;
    }
    final defenderRemainingHitPoints = math.max(
      0,
      defender.state.currentHitPoints - damage,
    );
    final recoveredHitPoints =
        math.min(
          attackerStats.hitPoints,
          attacker.state.currentHitPoints +
              (statusEffect?.hitPointsRecovery ?? 0),
        ) -
        attacker.state.currentHitPoints;
    final selfDestructs = move?.specialEffect?.selfDestructs ?? false;
    final attackerRemainingHitPoints = selfDestructs
        ? 0
        : attacker.state.currentHitPoints + recoveredHitPoints;
    final attackerStatModifierChanges = _statModifierChanges(
      monster: attacker,
      side: attackerSide,
      changes: statusEffect?.selfStatChanges ?? const {},
    );
    final defenderStatModifierChanges = _statModifierChanges(
      monster: defender,
      side: defenderSide,
      changes: statusEffect?.opponentStatChanges ?? const {},
    );

    replaceActiveState(
      side: attackerSide,
      monsterState: attacker.state.copyWith(
        currentHitPoints: attackerRemainingHitPoints,
        remainingPowerPoints: remainingPowerPoints,
        statModifierPercents: _appliedStatModifierPercents(
          monster: attacker,
          changes: attackerStatModifierChanges,
        ),
      ),
    );
    replaceActiveState(
      side: defenderSide,
      monsterState: defender.state.copyWith(
        currentHitPoints: defenderRemainingHitPoints,
        statModifierPercents: _appliedStatModifierPercents(
          monster: defender,
          changes: defenderStatModifierChanges,
        ),
      ),
    );
    events.add(
      MoveUsedEvent(
        turnNumber: turnNumber,
        attackerSide: attackerSide,
        attackerMonsterId: attacker.definition.id,
        moveId: move?.id,
        typeMultiplier: typeMultiplier,
        damage: damage,
        defenderRemainingHitPoints: defenderRemainingHitPoints,
        specialEffect: specialEffect,
        statModifierChanges: [
          ...attackerStatModifierChanges,
          ...defenderStatModifierChanges,
        ],
        recoveredHitPoints: recoveredHitPoints,
        attackerRemainingHitPoints: attackerRemainingHitPoints,
        replacedMoveId: replacedMoveId,
        isOneHitKnockout: isOneHitKnockout,
        selfDestructed: selfDestructs,
      ),
    );

    // 状態の変化。ダメージの後に行い、倒れたモンスターには付けない
    final moveSpecialEffect = move?.specialEffect;
    if (damage > 0 && defenderRemainingHitPoints > 0) {
      final defenderAfterDamage = parties[defenderSide]!.activeMember;
      if (defenderAfterDamage.state.statusConditions.containsKey(
        StatusConditionKind.frozen,
      )) {
        replaceActiveState(
          side: defenderSide,
          monsterState: defenderAfterDamage.state.copyWith(
            statusConditions: {...defenderAfterDamage.state.statusConditions}
              ..remove(StatusConditionKind.frozen),
          ),
        );
        events.add(
          StatusConditionCuredEvent(
            turnNumber: turnNumber,
            side: defenderSide,
            monsterId: defenderAfterDamage.definition.id,
            kinds: const [StatusConditionKind.frozen],
            cause: StatusConditionCureCause.damaged,
          ),
        );
      }
      if (move != null &&
          move.elementTypeId == poisonElementTypeId &&
          move.category == MoveCategory.attack &&
          parties[defenderSide]!.activeMember.state.statusConditions
              .containsKey(StatusConditionKind.poison)) {
        _inflictStatusCondition(
          parties: parties,
          side: defenderSide,
          kind: StatusConditionKind.poison,
          turnNumber: turnNumber,
          events: events,
          random: random,
        );
      }
    }
    if (moveSpecialEffect != null) {
      for (final (side, inflictions) in [
        (attackerSide, moveSpecialEffect.selfStatusConditions),
        (defenderSide, moveSpecialEffect.opponentStatusConditions),
      ]) {
        for (final infliction in inflictions) {
          if (parties[side]!.activeMember.isFainted) {
            continue;
          }
          if (infliction.chancePercent < 100 &&
              random.nextIntInRange(minimum: 1, maximum: 100) >
                  infliction.chancePercent) {
            continue;
          }
          _inflictStatusCondition(
            parties: parties,
            side: side,
            kind: infliction.kind,
            turnNumber: turnNumber,
            events: events,
            random: random,
          );
        }
      }
      final attackerAfterEffects = parties[attackerSide]!.activeMember;
      if (moveSpecialEffect.curesSelfStatusConditions &&
          !attackerAfterEffects.isFainted &&
          attackerAfterEffects.state.statusConditions.isNotEmpty) {
        events.add(
          StatusConditionCuredEvent(
            turnNumber: turnNumber,
            side: attackerSide,
            monsterId: attackerAfterEffects.definition.id,
            kinds: attackerAfterEffects.state.statusConditions.keys.toList(),
            cause: StatusConditionCureCause.move,
          ),
        );
        replaceActiveState(
          side: attackerSide,
          monsterState: attackerAfterEffects.state.copyWith(
            statusConditions: const {},
          ),
        );
      }
      if (moveSpecialEffect.fieldEffect case final fieldEffectKind?) {
        // 続いている同じフィールドを始め直す時は、このラウンドの始めに決まった入れ替えを保ち (後攻だけ入れ替え前の値で計算しないため)、残りのラウンドだけ戻す
        field = BattleField(
          kind: fieldEffectKind,
          remainingRounds: fieldEffectDurationRounds,
          swappedStatKinds: field?.kind == fieldEffectKind
              ? field!.swappedStatKinds
              : null,
        );
        events.add(
          FieldEffectStartedEvent(
            turnNumber: turnNumber,
            side: attackerSide,
            kind: fieldEffectKind,
          ),
        );
      }
    }
    if (defenderRemainingHitPoints == 0) {
      events.add(
        MonsterFaintedEvent(
          turnNumber: turnNumber,
          side: defenderSide,
          monsterId: defender.definition.id,
        ),
      );
    }
    if (selfDestructs) {
      events.add(
        MonsterFaintedEvent(
          turnNumber: turnNumber,
          side: attackerSide,
          monsterId: attacker.definition.id,
        ),
      );
    }
    _endTurn(
      parties: parties,
      side: attackerSide,
      turnNumber: turnNumber,
      events: events,
    );
  }

  // 両陣営の手持ちがすべて倒れた時 (自爆で相打ち) は利用者の勝ちにする (documents/game-rules.md「勝敗」)
  final winner = parties[BattleSideId.opponent]!.isDefeated
      ? BattleSideId.player
      : parties[BattleSideId.player]!.isDefeated
      ? BattleSideId.opponent
      : null;
  for (final side in BattleSideId.values) {
    final party = parties[side]!;
    if (!party.activeMember.isFainted || party.isDefeated) {
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
        turnNumber: lastTurnNumber,
        side: side,
        monsterId: party.members[nextMemberIndex].definition.id,
        withdrawnMonsterId: null,
      ),
    );
  }

  if (winner != null) {
    for (final side in BattleSideId.values) {
      final party = parties[side]!;
      // 自分からの交代で手持ちは順不同に場に出るため、場に出たことがあるモンスターはログから求める
      // (先頭のモンスターと、交代で場に出たモンスター)
      final participantMonsterIds = {
        party.members.first.definition.id,
        for (final event in events)
          if (event is MonsterSwitchedInEvent && event.side == side)
            event.monsterId,
      };
      parties[side] = BattleParty(
        members: [
          for (final member in party.members)
            participantMonsterIds.contains(member.definition.id)
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
      for (final member in parties[side]!.members.where(
        (member) => participantMonsterIds.contains(member.definition.id),
      )) {
        events.add(
          LevelUpEvent(
            turnNumber: lastTurnNumber,
            side: side,
            monsterId: member.definition.id,
            newLevel: member.state.level,
          ),
        );
      }
    }
    events.add(BattleFinishedEvent(turnNumber: lastTurnNumber, winner: winner));
  }

  return BattleState(
    player: parties[BattleSideId.player]!,
    opponent: parties[BattleSideId.opponent]!,
    turnNumber: state.turnNumber + 2,
    randomState: random.state,
    events: events,
    winner: winner,
    battleDate: state.battleDate,
    field: field,
    opponentDamagePercent: state.opponentDamagePercent,
  );
}

/// 毒の属性の識別子 (master の `elementTypes`)。この属性の攻撃技を受けた毒のモンスターは毒の重なりが増える。
const String poisonElementTypeId = 'poison';

/// [side] の場のモンスターに状態 [kind] を付け、変化があれば [events] に [StatusConditionInflictedEvent] を足す。
/// 重なる状態 (毒・やけど) は上限まで重なりが増え、眠気は 2 回目で眠りに置き換わり、呪い・興奮は 2 回目は変わらない。
/// 残りのターンを持つ状態は、既に持っていれば残りを引き直す。眠りを付ける時は眠気を消す。
void _inflictStatusCondition({
  required Map<BattleSideId, BattleParty> parties,
  required BattleSideId side,
  required StatusConditionKind kind,
  required int turnNumber,
  required List<BattleEvent> events,
  required DeterministicRandom random,
}) {
  final monster = parties[side]!.activeMember;
  final statusConditions = {...monster.state.statusConditions};
  final current = statusConditions[kind];
  StatusConditionKind? replacedKind;
  StatusCondition? inflicted;
  final stackMaximum = statusConditionStackMaximums[kind];
  if (stackMaximum != null) {
    if (current == null) {
      inflicted = StatusCondition(
        kind: kind,
        remainingTurns: null,
        stackCount: 1,
        cursedStatKind: null,
      );
    } else if (current.stackCount < stackMaximum) {
      inflicted = current.copyWith(stackCount: current.stackCount + 1);
    }
  } else {
    switch (kind) {
      case StatusConditionKind.drowsy:
        if (statusConditions.containsKey(StatusConditionKind.sleep)) {
          break;
        }
        if (current != null) {
          replacedKind = StatusConditionKind.drowsy;
          statusConditions.remove(StatusConditionKind.drowsy);
          inflicted = StatusCondition(
            kind: StatusConditionKind.sleep,
            remainingTurns: _randomDuration(
              kind: StatusConditionKind.sleep,
              random: random,
            ),
            stackCount: 1,
            cursedStatKind: null,
          );
        } else {
          inflicted = const StatusCondition(
            kind: StatusConditionKind.drowsy,
            remainingTurns: null,
            stackCount: 1,
            cursedStatKind: null,
          );
        }
      case StatusConditionKind.curse:
        if (current == null) {
          inflicted = StatusCondition(
            kind: kind,
            remainingTurns: null,
            stackCount: 1,
            cursedStatKind:
                modifiableStatKinds[random.nextUint32() %
                    modifiableStatKinds.length],
          );
        }
      case StatusConditionKind.excited:
        if (current == null) {
          inflicted = StatusCondition(
            kind: kind,
            remainingTurns: null,
            stackCount: 1,
            cursedStatKind: null,
          );
        }
      case StatusConditionKind.sleep:
        if (statusConditions.remove(StatusConditionKind.drowsy) != null) {
          replacedKind = StatusConditionKind.drowsy;
        }
        inflicted = StatusCondition(
          kind: kind,
          remainingTurns: _randomDuration(kind: kind, random: random),
          stackCount: 1,
          cursedStatKind: null,
        );
      case StatusConditionKind.paralysis ||
          StatusConditionKind.stun ||
          StatusConditionKind.confusion ||
          StatusConditionKind.dizzy ||
          StatusConditionKind.frozen ||
          StatusConditionKind.switchBlocked:
        inflicted = StatusCondition(
          kind: kind,
          remainingTurns: _randomDuration(kind: kind, random: random),
          stackCount: 1,
          cursedStatKind: null,
        );
      case StatusConditionKind.poison || StatusConditionKind.burn:
        // 重なる状態は上で扱う
        break;
    }
  }
  if (inflicted == null) {
    return;
  }
  statusConditions[inflicted.kind] = inflicted;
  parties[side] = _replaceActiveMemberState(
    party: parties[side]!,
    state: monster.state.copyWith(statusConditions: statusConditions),
  );
  events.add(
    StatusConditionInflictedEvent(
      turnNumber: turnNumber,
      side: side,
      monsterId: monster.definition.id,
      kind: inflicted.kind,
      stackCount: inflicted.stackCount,
      replacedKind: replacedKind,
      cursedStatKind: inflicted.cursedStatKind,
    ),
  );
}

/// 気絶・眠り・凍結・麻痺の 1 つが、このターンの行動を止めるかを [random] で決める。
/// [actionPreventingStatusConditionChancePercent] の確率で true を返し、乱数を 1 つ進める。
bool _rollsActionPrevention({required DeterministicRandom random}) =>
    random.nextIntInRange(minimum: 1, maximum: 100) <=
    actionPreventingStatusConditionChancePercent;

/// 残りのターンを持つ状態 [kind] の残りのターン数を引く。範囲の最小と最大が同じ状態は乱数を引かない。
int _randomDuration({
  required StatusConditionKind kind,
  required DeterministicRandom random,
}) {
  final range = statusConditionDurationRanges[kind]!;
  return range.minimum == range.maximum
      ? range.minimum
      : random.nextIntInRange(minimum: range.minimum, maximum: range.maximum);
}

/// [side] のターンの終わりの処理。場のモンスターが倒れていなければ毒のダメージを受け (0 になれば倒れる)、
/// 残りのターンを持つ状態を 1 減らして 0 になった状態を消す。
void _endTurn({
  required Map<BattleSideId, BattleParty> parties,
  required BattleSideId side,
  required int turnNumber,
  required List<BattleEvent> events,
}) {
  final monster = parties[side]!.activeMember;
  if (monster.isFainted) {
    return;
  }
  var currentHitPoints = monster.state.currentHitPoints;
  final poison = monster.state.statusConditions[StatusConditionKind.poison];
  if (poison != null) {
    final damage = poisonDamage(
      maximumHitPoints: effectiveStats(monster: monster).hitPoints,
      stackCount: poison.stackCount,
    );
    currentHitPoints = math.max(0, currentHitPoints - damage);
    events.add(
      StatusConditionDamageEvent(
        turnNumber: turnNumber,
        side: side,
        monsterId: monster.definition.id,
        kind: StatusConditionKind.poison,
        damage: damage,
        remainingHitPoints: currentHitPoints,
      ),
    );
  }
  final statusConditions = <StatusConditionKind, StatusCondition>{};
  final expiredKinds = <StatusConditionKind>[];
  for (final MapEntry(key: kind, value: condition)
      in monster.state.statusConditions.entries) {
    final remainingTurns = condition.remainingTurns;
    if (remainingTurns == null) {
      statusConditions[kind] = condition;
    } else if (remainingTurns - 1 <= 0) {
      expiredKinds.add(kind);
    } else {
      statusConditions[kind] = condition.copyWith(
        remainingTurns: remainingTurns - 1,
      );
    }
  }
  parties[side] = _replaceActiveMemberState(
    party: parties[side]!,
    state: monster.state.copyWith(
      currentHitPoints: currentHitPoints,
      statusConditions: statusConditions,
    ),
  );
  if (currentHitPoints == 0) {
    events.add(
      MonsterFaintedEvent(
        turnNumber: turnNumber,
        side: side,
        monsterId: monster.definition.id,
      ),
    );
  } else if (expiredKinds.isNotEmpty) {
    events.add(
      StatusConditionCuredEvent(
        turnNumber: turnNumber,
        side: side,
        monsterId: monster.definition.id,
        kinds: expiredKinds,
        cause: StatusConditionCureCause.expired,
      ),
    );
  }
}

/// [side] の相手の陣営を返す。
BattleSideId _otherSide({required BattleSideId side}) => switch (side) {
  BattleSideId.player => BattleSideId.opponent,
  BattleSideId.opponent => BattleSideId.player,
};

/// [party] の手持ちのうち、自分から交代して場に出せるモンスターの位置 (倒れていない・場に出ていない)。
List<int> switchableMemberIndices({required BattleParty party}) => [
  for (final (index, member) in party.members.indexed)
    if (index != party.activeMemberIndex && !member.isFainted) index,
];

/// [party] の場のモンスターが交換不可 ([StatusConditionKind.switchBlocked]) で、自分から交代できないか。
bool isSwitchBlocked({required BattleParty party}) => party
    .activeMember
    .state
    .statusConditions
    .containsKey(StatusConditionKind.switchBlocked);

/// [action] を [party] の場のモンスターが選べるかを確かめ、選べなければ [ArgumentError] を投げる。
void _validateAction({
  required BattleParty party,
  required BattleAction action,
  required MasterData master,
}) {
  final moves = selectableMoves(monster: party.activeMember, master: master);
  switch (action) {
    case SwitchMonsterAction(:final memberIndex):
      if (!switchableMemberIndices(party: party).contains(memberIndex)) {
        throw ArgumentError('手持ちの $memberIndex 番目は倒れているか場に出ているため、交代できない');
      }
      if (isSwitchBlocked(party: party)) {
        throw ArgumentError('交換不可の状態のため、交代できない');
      }
    case UseMoveAction(:final moveId):
      if (!moves.any((move) => move.id == moveId)) {
        throw ArgumentError('技 $moveId は PP が 0 か、まだ使えない');
      }
    case StruggleAction():
      if (moves.any(isOrdinaryAttackMove)) {
        throw ArgumentError('使える攻撃技があるため、わるあがきは選べない');
      }
  }
}

/// [monster] ([side] の場のモンスター) のステータスの倍率に [changes] (倍率に足す値) を足し、重ねがけの上限
/// ([statModifierPercentMinimum]〜[statModifierPercentMaximum]) で丸めた変化の結果を返す。値が 0 の変化は除く。
List<StatModifierChange> _statModifierChanges({
  required BattleMonster monster,
  required BattleSideId side,
  required Map<StatKind, int> changes,
}) => [
  for (final MapEntry(key: statKind, value: change) in changes.entries)
    if (change != 0)
      StatModifierChange(
        side: side,
        statKind: statKind,
        previousPercent: statModifierPercentOf(
          monster: monster,
          statKind: statKind,
        ),
        newPercent:
            (statModifierPercentOf(monster: monster, statKind: statKind) +
                    change)
                .clamp(statModifierPercentMinimum, statModifierPercentMaximum),
      ),
];

/// [monster] のステータスの倍率に [changes] の変わった後の倍率を反映した倍率の一覧を返す。
Map<StatKind, int> _appliedStatModifierPercents({
  required BattleMonster monster,
  required List<StatModifierChange> changes,
}) => {
  ...monster.state.statModifierPercents,
  for (final change in changes) change.statKind: change.newPercent,
};

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
