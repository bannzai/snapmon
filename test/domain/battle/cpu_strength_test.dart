import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/domain/battle/battle_simulation.dart';
import 'package:snapmon/domain/battle/battle_state.dart';

import '../../sample_data_fixture.dart';

// CPU の強さ (issue #240・#267)。計測は lib/domain/battle/battle_simulation.dart (利用者の側は本番の図鑑の 6 体の種族値に
// 見本の属性・技、CPU の側は見本のモンスター) で、目標の値は documents/DIRECTION.md「決めたこと」の 2026-11-09 の #267 の行。
void main() {
  final sampleData = loadSampleDataFixture();
  final master = sampleData.definitions;
  final sampleDefinitions = [
    for (final monster in sampleData.monsters) monster.definition,
  ];
  final playerDefinitions = simulationPlayerDefinitions(
    sampleDefinitions: sampleDefinitions,
  );

  /// 利用者 Lv.[playerLevel]・CPU Lv.[opponentLevel] で戦わせた時の集計。補正の既定値は、アプリが CPU 戦で使う今の値
  /// ([cpuDamagePercent]・[cpuHitPointsPercent]) で、目標を守るテストがアプリと同じ条件を測るため。
  BattleSimulationResult simulate({
    required int playerLevel,
    required int opponentLevel,
    required SimulatedPlayerPolicy policy,
    int opponentDamagePercent = cpuDamagePercent,
    int opponentHitPointsPercent = cpuHitPointsPercent,
  }) => simulateBattles(
    master: master,
    playerDefinitions: playerDefinitions,
    opponentDefinitions: sampleDefinitions,
    condition: (
      playerLevel: playerLevel,
      opponentLevel: opponentLevel,
      opponentDamagePercent: opponentDamagePercent,
      opponentHitPointsPercent: opponentHitPointsPercent,
      playerPolicy: policy,
      // 180 組 × 5 で 1 条件 900 戦になり、値を決めた tool/simulate_battles.dart の既定と同じ戦数で目標を確かめるため
      seedCount: 5,
    ),
  );

  /// [count] / [total] を % で返す。
  double percent({required int count, required int total}) =>
      count * 100 / total;

  test('初回のバトル (Lv.1) で、技を乱数で選ぶ利用者が CPU に 6 割以上勝つ', () {
    final result = simulate(
      playerLevel: 1,
      opponentLevel: 1,
      policy: SimulatedPlayerPolicy.randomMove,
    );
    expect(
      percent(count: result.playerWins, total: result.battles),
      greaterThanOrEqualTo(60),
      reason: '${result.playerWins}/${result.battles}',
    );
  });

  test('Lv.20 で相性の最善を選ぶ利用者の勝率は 75% を超えない (CPU が弱すぎない)', () {
    final result = simulate(
      playerLevel: 20,
      opponentLevel: 20,
      policy: SimulatedPlayerPolicy.sameAsCpu,
    );
    expect(
      percent(count: result.playerWins, total: result.battles),
      lessThanOrEqualTo(75),
      reason: '${result.playerWins}/${result.battles}',
    );
  });

  test(
    'Lv.4 対 Lv.2 で、CPU の打撃のうち 1 ダメージに潰れるものは 3 割以下 (issue #267 の「1 ダメージしか受けない」)',
    () {
      final result = simulate(
        playerLevel: 4,
        opponentLevel: 2,
        policy: SimulatedPlayerPolicy.randomMove,
      );
      expect(
        percent(
          count: result.opponentOneDamageHits,
          total: result.opponentAttackHits,
        ),
        lessThanOrEqualTo(30),
        reason: '${result.opponentOneDamageHits}/${result.opponentAttackHits}',
      );
    },
  );

  test('補正しない (100%) と、Lv.1 で技を乱数で選ぶ利用者は CPU に半分も勝てない (issue #240 の再現)', () {
    final result = simulate(
      playerLevel: 1,
      opponentLevel: 1,
      policy: SimulatedPlayerPolicy.randomMove,
      opponentDamagePercent: 100,
      opponentHitPointsPercent: 100,
    );
    expect(
      percent(count: result.playerWins, total: result.battles),
      lessThan(50),
      reason: '${result.playerWins}/${result.battles}',
    );
  });

  test('同じ条件のシミュレーションは同じ結果になる (seed で決まる)', () {
    BattleSimulationResult run() => simulate(
      playerLevel: 4,
      opponentLevel: 2,
      policy: SimulatedPlayerPolicy.randomMove,
    );
    expect(run(), run());
  });

  test('最大 HP の割合は切り捨てで 1 以上になり、100 ならステータスの計算式の HP のまま', () {
    final definition = sampleDefinitions[0];
    final full = maximumHitPoints(
      definition: definition,
      level: 10,
      maximumHitPointsPercent: 100,
    );
    expect(
      maximumHitPoints(
        definition: definition,
        level: 10,
        maximumHitPointsPercent: 70,
      ),
      full * 70 ~/ 100,
    );
    expect(
      maximumHitPoints(
        definition: definition,
        level: 1,
        maximumHitPointsPercent: 1,
      ),
      1,
    );
  });

  test('最大 HP の割合は、始めの HP・回復の上限・技の式の変数・毒のダメージの最大 HP に掛かる', () {
    final reduced = prepareBattleMonster(
      definition: sampleDefinitions[0],
      level: 30,
      experience: 0,
      actionCardMoveIds: const [],
      master: master,
      maximumHitPointsPercent: 50,
    );
    final full = prepareBattleMonster(
      definition: sampleDefinitions[0],
      level: 30,
      experience: 0,
      actionCardMoveIds: const [],
      master: master,
      maximumHitPointsPercent: 100,
    );
    expect(reduced.state.currentHitPoints, full.state.currentHitPoints ~/ 2);
    expect(
      effectiveStats(monster: reduced).hitPoints,
      full.state.currentHitPoints ~/ 2,
    );
    expect(
      effectiveStats(monster: reduced).attack,
      effectiveStats(monster: full).attack,
    );
  });

  test('相手の陣営が与えるダメージだけに割合が掛かり、利用者の陣営のダメージは変わらない', () {
    List<MoveUsedEvent> firstRound({required int opponentDamagePercent}) {
      final state = startBattle(
        playerMembers: [
          prepareBattleMonster(
            definition: sampleDefinitions[0],
            level: 30,
            experience: 0,
            actionCardMoveIds: const [],
            master: master,
            maximumHitPointsPercent: 100,
          ),
        ],
        opponentMembers: [
          prepareBattleMonster(
            definition: sampleDefinitions[1],
            level: 30,
            experience: 0,
            actionCardMoveIds: const [],
            master: master,
            maximumHitPointsPercent: 100,
          ),
        ],
        randomSeed: 1,
        battleDate: simulationBattleDate,
        opponentDamagePercent: opponentDamagePercent,
      );
      return advanceRound(
        state: state,
        playerAction: chooseCpuAction(
          state: state,
          side: BattleSideId.player,
          master: master,
        ),
        opponentAction: chooseCpuAction(
          state: state,
          side: BattleSideId.opponent,
          master: master,
        ),
        master: master,
      ).events.whereType<MoveUsedEvent>().toList();
    }

    int damageBy({
      required List<MoveUsedEvent> events,
      required BattleSideId side,
    }) => events.singleWhere((event) => event.attackerSide == side).damage;

    final unchanged = firstRound(opponentDamagePercent: 100);
    final halved = firstRound(opponentDamagePercent: 50);
    expect(
      damageBy(events: halved, side: BattleSideId.player),
      damageBy(events: unchanged, side: BattleSideId.player),
    );
    expect(
      damageBy(events: halved, side: BattleSideId.opponent),
      damageBy(events: unchanged, side: BattleSideId.opponent) * 50 ~/ 100,
    );
  });
}
