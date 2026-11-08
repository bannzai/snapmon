import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';
import 'package:snapmon/domain/random/deterministic_random.dart';

import '../../sample_data_fixture.dart';

// CPU の強さ (issue #240)。利用者の側は、本番の図鑑のモンスター 6 体の種族値 (2026-11-09 に snapmon-prod から読んだ値) に
// 見本のモンスターの属性・技を組み合わせ、CPU の側は見本のモンスターのまま戦わせる。
void main() {
  final sampleData = loadSampleDataFixture();
  final master = sampleData.definitions;
  const productionBaseStats = [
    MonsterStats(hitPoints: 60, attack: 40, defense: 60, speed: 80),
    MonsterStats(hitPoints: 120, attack: 80, defense: 100, speed: 40),
    MonsterStats(hitPoints: 60, attack: 60, defense: 60, speed: 80),
    MonsterStats(hitPoints: 60, attack: 40, defense: 60, speed: 80),
    MonsterStats(hitPoints: 60, attack: 40, defense: 40, speed: 80),
    MonsterStats(hitPoints: 60, attack: 40, defense: 40, speed: 80),
  ];

  /// [definition] の種族値だけを [baseStats] に替えた定義を返す。
  MonsterDefinition withBaseStats({
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

  /// 利用者の側が使える技から乱数で 1 つを選ぶ (技の相性を考えずに選ぶ利用者の代わり)。
  BattleAction randomSelectable({
    required BattleState state,
    required DeterministicRandom random,
  }) {
    final moves = selectableMoves(
      monster: state.player.activeMember,
      master: master,
    );
    if (!moves.any(isOrdinaryAttackMove)) {
      return const StruggleAction();
    }
    return UseMoveAction(moveId: moves[random.nextUint32() % moves.length].id);
  }

  /// Lv.[level] で、本番の種族値の利用者が乱数で技を選び、CPU が [chooseCpuAction] で選ぶ時の、利用者の勝ち数と対戦数を返す。
  ({int wins, int battles}) playerWins({
    required int level,
    required int opponentDamagePercent,
  }) {
    var wins = 0;
    var battles = 0;
    for (final baseStats in productionBaseStats) {
      for (final player in sampleData.monsters) {
        for (final opponent in sampleData.monsters) {
          if (player.artPath == opponent.artPath) {
            continue;
          }
          for (var seed = 1; seed <= 5; seed++) {
            final random = DeterministicRandom(seed: seed * 7919);
            var state = startBattle(
              playerMembers: [
                prepareBattleMonster(
                  definition: withBaseStats(
                    definition: player.definition,
                    baseStats: baseStats,
                  ),
                  level: level,
                  experience: 0,
                  master: master,
                ),
              ],
              opponentMembers: [
                prepareBattleMonster(
                  definition: opponent.definition,
                  level: level,
                  experience: 0,
                  master: master,
                ),
              ],
              randomSeed: seed,
              battleDate: DateTime(2026, 11, 9),
              opponentDamagePercent: opponentDamagePercent,
            );
            while (state.winner == null) {
              state = advanceRound(
                state: state,
                playerAction: randomSelectable(state: state, random: random),
                opponentAction: chooseCpuAction(
                  state: state,
                  side: BattleSideId.opponent,
                  master: master,
                ),
                master: master,
              );
            }
            battles++;
            if (state.winner == BattleSideId.player) {
              wins++;
            }
          }
        }
      }
    }
    return (wins: wins, battles: battles);
  }

  test('初回のバトル (Lv.1) で、技を乱数で選ぶ利用者が CPU に 6 割以上勝つ', () {
    final result = playerWins(
      level: 1,
      opponentDamagePercent: cpuDamagePercent,
    );
    expect(
      result.wins * 100 / result.battles,
      greaterThanOrEqualTo(60),
      reason: '${result.wins}/${result.battles}',
    );
  });

  test('補正しない (100%) と、Lv.1 で技を乱数で選ぶ利用者は CPU に半分も勝てない (issue #240 の再現)', () {
    final result = playerWins(level: 1, opponentDamagePercent: 100);
    expect(
      result.wins * 100 / result.battles,
      lessThan(50),
      reason: '${result.wins}/${result.battles}',
    );
  });

  test('相手の陣営が与えるダメージだけに割合が掛かり、利用者の陣営のダメージは変わらない', () {
    List<MoveUsedEvent> firstRound({required int opponentDamagePercent}) {
      final state = startBattle(
        playerMembers: [
          prepareBattleMonster(
            definition: sampleData.monsters[0].definition,
            level: 30,
            experience: 0,
            master: master,
          ),
        ],
        opponentMembers: [
          prepareBattleMonster(
            definition: sampleData.monsters[1].definition,
            level: 30,
            experience: 0,
            master: master,
          ),
        ],
        randomSeed: 1,
        battleDate: DateTime(2026, 11, 9),
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
