import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';
import 'package:snapmon/domain/random/deterministic_random.dart';

import '../../sample_data_fixture.dart';

// 計測用 (issue #240)。本番の図鑑のモンスター 6 体の種族値 (2026-11-09 に snapmon-prod から読んだ値) の利用者に対し、
// CPU の候補ごとの勝率を出す。
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

  int lowered({required int value, required int amount}) =>
      value - amount < 40 ? 40 : value - amount;

  MonsterStats loweredStats({
    required MonsterStats stats,
    required int amount,
  }) => MonsterStats(
    hitPoints: lowered(value: stats.hitPoints, amount: amount),
    attack: lowered(value: stats.attack, amount: amount),
    defense: lowered(value: stats.defense, amount: amount),
    speed: lowered(value: stats.speed, amount: amount),
  );

  BattleAction randomSelectable({
    required BattleState state,
    required BattleSideId side,
    required DeterministicRandom random,
  }) {
    final moves = selectableMoves(
      monster: state.partyOf(side: side).activeMember,
      master: master,
    );
    if (!moves.any(isOrdinaryAttackMove)) {
      return const StruggleAction();
    }
    return UseMoveAction(moveId: moves[random.nextUint32() % moves.length].id);
  }

  test('計測: 本番の種族値の利用者に対する CPU の候補ごとの勝率', () {
    final buffer = StringBuffer('\n');
    for (final level in [1, 5, 20]) {
      for (final playerPolicy in ['random', 'best']) {
        for (final (damagePercent, cpuBestPercent) in [
          (100, 100),
          (100, 50),
          (75, 100),
          (75, 50),
          (60, 100),
          (50, 100),
        ]) {
          const loweredAmount = 0;
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
                        definition: withBaseStats(
                          definition: opponent.definition,
                          baseStats: loweredStats(
                            stats: opponent.definition.baseStats,
                            amount: loweredAmount,
                          ),
                        ),
                        level: level,
                        experience: 0,
                        master: master,
                      ),
                    ],
                    randomSeed: seed,
                    battleDate: DateTime(2026, 11, 9),
                    opponentDamagePercent: damagePercent,
                  );
                  while (state.winner == null && state.turnNumber < 500) {
                    state = advanceRound(
                      state: state,
                      playerAction: playerPolicy == 'random'
                          ? randomSelectable(
                              state: state,
                              side: BattleSideId.player,
                              random: random,
                            )
                          : chooseCpuAction(
                              state: state,
                              side: BattleSideId.player,
                              master: master,
                            ),
                      opponentAction: random.nextUint32() % 100 < cpuBestPercent
                          ? chooseCpuAction(
                              state: state,
                              side: BattleSideId.opponent,
                              master: master,
                            )
                          : randomSelectable(
                              state: state,
                              side: BattleSideId.opponent,
                              random: random,
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
          buffer.writeln(
            'MEASURE level=$level player=$playerPolicy damage=$damagePercent% cpuBest=$cpuBestPercent% '
            'playerWin=${(wins * 1000 ~/ battles) / 10}% ($wins/$battles)',
          );
        }
      }
    }
    // ignore: avoid_print
    print(buffer);
  });
}
