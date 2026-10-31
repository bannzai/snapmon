import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/capture/first_battle.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';

import '../../monster_generator_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  test(
    '他のユーザーの候補を読まず、自分の手持ちと同じ見本のモンスターを持たない CPU トレーナーと戦う (本人の操作なしに他人の手持ちを相手にしないため)',
    () async {
      // 本番と同じく、生まれたモンスターを手持ちに入れた後の図鑑で相手を決める (CPU の手持ちのレベルを自分の手持ちに合わせるため)
      final dexStore = DexStore(definitions: sampleData.definitions)
        ..applyServerSnapshot(
          monsters: [sampleData.monsterById(monsterId: 'sample-mugmon')],
          partyMonsterIds: ['sample-mugmon'],
          definitions: null,
        );
      var fetchOpponentsCount = 0;
      final pvpClient = PvpClient(
        fetchOpponents: () async {
          fetchOpponentsCount++;
          return [
            PvpOpponent(
              opponentUid: 'opponent-uid-1',
              displayName: 'ろうそくや',
              monsters: [generatedWaxMonster(monsterId: 'opponent-wax-1')],
            ),
          ];
        },
        fetchDefinitions: ({required base, required definitionIds}) =>
            throw StateError('fetchDefinitions は呼ばない'),
        reportMonster:
            ({required monsterOwnerUid, required monsterId, required reason}) =>
                throw StateError('reportMonster は呼ばない'),
        blockUser: ({required blockedUid}) =>
            throw StateError('blockUser は呼ばない'),
        fetchBattleRecord: () async => null,
        fetchDisplayName: () async => null,
        updateDisplayName: ({required displayName}) async => displayName,
      );
      final cpuTrainerNames = {
        for (var randomSeed = 1; randomSeed <= 50; randomSeed++)
          (await prepareFirstBattleOpponent(
            dexStore: dexStore,
            pvpClient: pvpClient,
            sampleData: sampleData,
            randomSeed: randomSeed,
          )).opponentName,
      };
      expect(fetchOpponentsCount, 0);
      expect(cpuTrainerNames, {
        for (final cpuTrainer in sampleData.cpuTrainers)
          if (!cpuTrainer.monsterIds.contains('sample-mugmon')) cpuTrainer.name,
      });
    },
  );

  test('自分の手持ちと同じ見本のモンスターを持つ CPU トレーナーを除き、全員が除かれる時は全員を残す', () {
    final cpuTrainerIds = excludeCpuTrainersWithSameArt(
      sampleData: sampleData,
      playerParty: [sampleData.monsterById(monsterId: 'sample-mugmon')],
    ).map((cpuTrainer) => cpuTrainer.id);
    expect(cpuTrainerIds, hasLength(sampleData.cpuTrainers.length - 1));
    for (final cpuTrainer in sampleData.cpuTrainers) {
      expect(
        cpuTrainerIds.contains(cpuTrainer.id),
        !cpuTrainer.monsterIds.contains('sample-mugmon'),
        reason: cpuTrainer.id,
      );
    }
    expect(
      excludeCpuTrainersWithSameArt(
        sampleData: sampleData,
        playerParty: sampleData.monsters,
      ),
      sampleData.cpuTrainers,
    );
  });

  test('chooseFirstBattleCpuTrainer は seed によって別の CPU トレーナーになり、同じ seed では同じトレーナーになる', () {
    expect(
      {
        for (var randomSeed = 1; randomSeed <= 50; randomSeed++)
          chooseFirstBattleCpuTrainer(
            cpuTrainers: sampleData.cpuTrainers,
            randomSeed: randomSeed,
          ).id,
      },
      {for (final cpuTrainer in sampleData.cpuTrainers) cpuTrainer.id},
    );
    expect(
      chooseFirstBattleCpuTrainer(
        cpuTrainers: sampleData.cpuTrainers,
        randomSeed: 7,
      ).id,
      chooseFirstBattleCpuTrainer(
        cpuTrainers: sampleData.cpuTrainers,
        randomSeed: 7,
      ).id,
    );
  });
}
