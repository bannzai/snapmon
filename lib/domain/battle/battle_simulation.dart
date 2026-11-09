import 'dart:math' as math;

import '../master/master_data.dart';
import '../monster/monster_definition.dart';
import '../monster/monster_stats.dart';
import '../random/deterministic_random.dart';
import 'battle_engine.dart';
import 'battle_state.dart';

/// バトルのシミュレーション (CPU の強さの調整。issue #240・#267)。
/// 実機で何戦もする代わりに、同じ計算 (`advanceRound`) を条件を変えて何度も繰り返し、勝率・ラウンド数・1 ダメージの割合を集計する。
/// 入口は tool/simulate_battles.dart (表を出す) と test/domain/battle/cpu_strength_test.dart (目標の値を守る)。

/// 本番の図鑑のモンスター 6 体の種族値 (2026-11-09 に snapmon-prod から読んだ値。issue #240)。
/// 命中は読んだ時点の値に無く (#279 より前に生まれた)、端末が読む時と同じ既定の種族値にした。
/// 見本のモンスターの種族値は本番より高めのため、利用者の側はこの種族値に見本の属性・技を組み合わせて測る ([simulationPlayerDefinitions])。
const List<MonsterStats> productionBaseStatsSample = [
  MonsterStats(
    hitPoints: 60,
    attack: 40,
    defense: 60,
    speed: 80,
    accuracy: accuracyBaseStatWithoutJudgement,
  ),
  MonsterStats(
    hitPoints: 120,
    attack: 80,
    defense: 100,
    speed: 40,
    accuracy: accuracyBaseStatWithoutJudgement,
  ),
  MonsterStats(
    hitPoints: 60,
    attack: 60,
    defense: 60,
    speed: 80,
    accuracy: accuracyBaseStatWithoutJudgement,
  ),
  MonsterStats(
    hitPoints: 60,
    attack: 40,
    defense: 60,
    speed: 80,
    accuracy: accuracyBaseStatWithoutJudgement,
  ),
  MonsterStats(
    hitPoints: 60,
    attack: 40,
    defense: 40,
    speed: 80,
    accuracy: accuracyBaseStatWithoutJudgement,
  ),
  MonsterStats(
    hitPoints: 60,
    attack: 40,
    defense: 40,
    speed: 80,
    accuracy: accuracyBaseStatWithoutJudgement,
  ),
];

/// シミュレーションの対戦日。技の特殊効果の入力に渡す値で、今の master に日付で変わる効果は無いため固定の日付 (issue #240 の計測日) にする。
final DateTime simulationBattleDate = DateTime(2026, 11, 9);

/// 利用者の側の乱数の seed に掛ける値。バトルの乱数 (seed そのもの) と別の列にするための素数。
const int _playerRandomSeedMultiplier = 7919;

/// シミュレーションで利用者の代わりに技を選ぶ方法。
enum SimulatedPlayerPolicy {
  /// 使える技から乱数で 1 つ選ぶ (相性を考えない利用者)。通常の攻撃技が 1 つも無ければわるあがき。
  randomMove,

  /// CPU と同じ選び方 ([chooseCpuAction]。相性の倍率が最大の攻撃技、1/4 で効果のある補助技)。相性の最善を選ぶ利用者の代わり。
  sameAsCpu,
}

/// シミュレーションの 1 つの条件。利用者 (1 体) と CPU (1 体) を [playerLevel]・[opponentLevel] で戦わせ、
/// CPU の与えるダメージに [opponentDamagePercent] (%)、CPU の最大 HP に [opponentHitPointsPercent] (%) を掛ける。
/// 利用者の技は [playerPolicy] で選び、組み合わせごとに [seedCount] 通りの乱数で戦う。
typedef BattleSimulationCondition = ({
  int playerLevel,
  int opponentLevel,
  int opponentDamagePercent,
  int opponentHitPointsPercent,
  SimulatedPlayerPolicy playerPolicy,
  int seedCount,
});

/// 1 つの条件の集計。`attackHits` は攻撃技・わるあがきが当たった回数 (補助技と一撃必殺を除く)、
/// `oneDamageHits` はそのうちダメージが 1 だった回数 (補正の切り捨てで 1 に潰れた打撃の多さを見る)。
typedef BattleSimulationResult = ({
  int battles,
  int playerWins,
  int totalRounds,
  int maximumRounds,
  int playerAttackHits,
  int playerOneDamageHits,
  int opponentAttackHits,
  int opponentOneDamageHits,
});

/// [definition] の種族値だけを [baseStats] に替えた定義を返す。
MonsterDefinition definitionWithBaseStats({
  required MonsterDefinition definition,
  required MonsterStats baseStats,
}) => MonsterDefinition(
  id: definition.id,
  sourcePhotoReference: definition.sourcePhotoReference,
  name: definition.name,
  encyclopediaText: definition.encyclopediaText,
  elementTypeIds: definition.elementTypeIds,
  learnset: definition.learnset,
  baseStats: baseStats,
  individualValues: definition.individualValues,
  statCalculationVersion: definition.statCalculationVersion,
  masterVersion: definition.masterVersion,
);

/// 利用者の側の定義。[sampleDefinitions] (見本のモンスター) の属性・技に [productionBaseStatsSample] の各種族値を組み合わせた一覧
/// (見本 6 体 × 種族値 6 通り = 36 件)。CPU の側は見本のモンスターをそのまま使う。
List<MonsterDefinition> simulationPlayerDefinitions({
  required List<MonsterDefinition> sampleDefinitions,
}) => [
  for (final baseStats in productionBaseStatsSample)
    for (final definition in sampleDefinitions)
      definitionWithBaseStats(definition: definition, baseStats: baseStats),
];

/// [playerDefinitions] の各 1 体と [opponentDefinitions] の各 1 体 (同じ `id` の組は除く) を [condition] で戦わせ、集計を返す。
/// CPU の技は [chooseCpuAction] で選ぶ。同じ引数からは同じ結果になる。
BattleSimulationResult simulateBattles({
  required MasterData master,
  required List<MonsterDefinition> playerDefinitions,
  required List<MonsterDefinition> opponentDefinitions,
  required BattleSimulationCondition condition,
}) {
  var battles = 0;
  var playerWins = 0;
  var totalRounds = 0;
  var maximumRounds = 0;
  var playerAttackHits = 0;
  var playerOneDamageHits = 0;
  var opponentAttackHits = 0;
  var opponentOneDamageHits = 0;
  for (final playerDefinition in playerDefinitions) {
    for (final opponentDefinition in opponentDefinitions) {
      if (playerDefinition.id == opponentDefinition.id) {
        continue;
      }
      for (var seed = 1; seed <= condition.seedCount; seed++) {
        final finished = _playBattle(
          master: master,
          playerDefinition: playerDefinition,
          opponentDefinition: opponentDefinition,
          condition: condition,
          seed: seed,
        );
        battles++;
        if (finished.winner == BattleSideId.player) {
          playerWins++;
        }
        // roundNumber は次に解決するラウンドの番号のため、戦ったラウンド数はその 1 つ前
        final rounds = finished.roundNumber - 1;
        totalRounds += rounds;
        maximumRounds = math.max(maximumRounds, rounds);
        for (final event in finished.events.whereType<MoveUsedEvent>()) {
          // 補助技はダメージ 0、一撃必殺は残り HP をそのまま削るため、ダメージ式を通った打撃だけを数える
          if (event.damage == 0 || event.isOneHitKnockout) {
            continue;
          }
          if (event.attackerSide == BattleSideId.player) {
            playerAttackHits++;
            if (event.damage == 1) {
              playerOneDamageHits++;
            }
          } else {
            opponentAttackHits++;
            if (event.damage == 1) {
              opponentOneDamageHits++;
            }
          }
        }
      }
    }
  }
  return (
    battles: battles,
    playerWins: playerWins,
    totalRounds: totalRounds,
    maximumRounds: maximumRounds,
    playerAttackHits: playerAttackHits,
    playerOneDamageHits: playerOneDamageHits,
    opponentAttackHits: opponentAttackHits,
    opponentOneDamageHits: opponentOneDamageHits,
  );
}

/// [seed] の乱数で 1 戦を決着まで進め、決着した状態を返す。
BattleState _playBattle({
  required MasterData master,
  required MonsterDefinition playerDefinition,
  required MonsterDefinition opponentDefinition,
  required BattleSimulationCondition condition,
  required int seed,
}) {
  final playerRandom = DeterministicRandom(
    seed: seed * _playerRandomSeedMultiplier,
  );
  // シミュレーションは master の定義の覚える技だけで戦わせ、Action Card で覚えさせた技は持たせない (両陣営とも空)
  var state = startBattle(
    playerMembers: [
      prepareBattleMonster(
        definition: playerDefinition,
        level: condition.playerLevel,
        experience: 0,
        actionCardMoveIds: const [],
        master: master,
        maximumHitPointsPercent: 100,
      ),
    ],
    opponentMembers: [
      prepareBattleMonster(
        definition: opponentDefinition,
        level: condition.opponentLevel,
        experience: 0,
        actionCardMoveIds: const [],
        master: master,
        maximumHitPointsPercent: condition.opponentHitPointsPercent,
      ),
    ],
    randomSeed: seed,
    battleDate: simulationBattleDate,
    opponentDamagePercent: condition.opponentDamagePercent,
  );
  while (state.winner == null) {
    state = advanceRound(
      state: state,
      playerAction: _playerAction(
        state: state,
        policy: condition.playerPolicy,
        random: playerRandom,
        master: master,
      ),
      opponentAction: chooseCpuAction(
        state: state,
        side: BattleSideId.opponent,
        master: master,
      ),
      master: master,
    );
  }
  return state;
}

/// [policy] で利用者の行動を選ぶ。
BattleAction _playerAction({
  required BattleState state,
  required SimulatedPlayerPolicy policy,
  required DeterministicRandom random,
  required MasterData master,
}) {
  switch (policy) {
    case SimulatedPlayerPolicy.randomMove:
      final moves = selectableMoves(
        monster: state.player.activeMember,
        master: master,
      );
      if (!moves.any(isOrdinaryAttackMove)) {
        return const StruggleAction();
      }
      return UseMoveAction(
        moveId: moves[random.nextUint32() % moves.length].id,
      );
    case SimulatedPlayerPolicy.sameAsCpu:
      return chooseCpuAction(
        state: state,
        side: BattleSideId.player,
        master: master,
      );
  }
}
