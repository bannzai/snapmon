import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/battle/battle_engine.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/random/deterministic_random.dart';

import '../../sample_data_fixture.dart';

// 計測用 (issue #240)。CPU の技選びの候補ごとに、Lv.1 の見本のモンスター同士の勝率を出す。
void main() {
  final sampleData = loadSampleDataFixture();
  final master = sampleData.definitions;

  BattleAction randomSelectable({
    required BattleState state,
    required BattleSideId side,
    required DeterministicRandom random,
  }) {
    final moves = selectableMoves(
      monster: state.partyOf(side: side).activeMember,
      master: master,
    );
    final hasOrdinary = moves.any(isOrdinaryAttackMove);
    if (!hasOrdinary) {
      return const StruggleAction();
    }
    return UseMoveAction(
      moveId: moves[random.nextUint32() % moves.length].id,
    );
  }

  BattleAction firstSlot({required BattleState state}) {
    final moves = selectableMoves(
      monster: state.player.activeMember,
      master: master,
    );
    if (!moves.any(isOrdinaryAttackMove)) {
      return const StruggleAction();
    }
    return UseMoveAction(moveId: moves.first.id);
  }

  BattleAction cpuWithBestPercent({
    required BattleState state,
    required BattleSideId side,
    required DeterministicRandom random,
    required int bestPercent,
  }) {
    if (random.nextUint32() % 100 < bestPercent) {
      return chooseCpuAction(state: state, side: side, master: master);
    }
    final ordinary = selectableMoves(
      monster: state.partyOf(side: side).activeMember,
      master: master,
    ).where(isOrdinaryAttackMove).toList();
    if (ordinary.isEmpty) {
      return const StruggleAction();
    }
    return UseMoveAction(
      moveId: ordinary[random.nextUint32() % ordinary.length].id,
    );
  }

  test('計測: Lv.1 の見本同士で、プレイヤーの技の選び方と CPU の最善の割合ごとの勝率', () {
    final playerPolicies = <String>['random', 'firstSlot', 'best'];
    final buffer = StringBuffer('\n');
    for (final level in [1, 5]) {
      for (final playerPolicy in playerPolicies) {
        for (final bestPercent in [100, 75, 50, 25, 0]) {
          var wins = 0;
          var battles = 0;
          for (final player in sampleData.monsters) {
            for (final opponent in sampleData.monsters) {
              if (player.artPath == opponent.artPath) {
                continue;
              }
              for (var seed = 1; seed <= 20; seed++) {
                final random = DeterministicRandom(seed: seed * 7919);
                var state = startBattle(
                  playerMembers: [
                    prepareBattleMonster(
                      definition: player.definition,
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
                );
                while (state.winner == null && state.turnNumber < 500) {
                  final playerAction = switch (playerPolicy) {
                    'random' => randomSelectable(
                      state: state,
                      side: BattleSideId.player,
                      random: random,
                    ),
                    'firstSlot' => firstSlot(state: state),
                    _ => chooseCpuAction(
                      state: state,
                      side: BattleSideId.player,
                      master: master,
                    ),
                  };
                  state = advanceRound(
                    state: state,
                    playerAction: playerAction,
                    opponentAction: cpuWithBestPercent(
                      state: state,
                      side: BattleSideId.opponent,
                      random: random,
                      bestPercent: bestPercent,
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
          buffer.writeln(
            'MEASURE level=$level player=$playerPolicy cpuBest=$bestPercent% '
            'playerWin=${(wins * 1000 ~/ battles) / 10}% ($wins/$battles)',
          );
        }
      }
    }
    // ignore: avoid_print
    print(buffer);
  });
}
