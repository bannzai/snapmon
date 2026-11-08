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
    '他のユーザーの候補を読まず、乱数で決めた CPU トレーナーの名前と、自分の手持ちと同じ数で同じ絵を含まない見本のモンスターと戦う (本人の操作なしに他人の手持ちを相手にしないため)',
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
              iconPath: null,
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
        fetchProfile: () async => null,
        updateDisplayName: ({required displayName}) async => displayName,
        updateIcon: ({required photo}) => throw StateError('updateIcon は呼ばない'),
      );
      final opponents = [
        for (var randomSeed = 1; randomSeed <= 50; randomSeed++)
          await prepareFirstBattleOpponent(
            dexStore: dexStore,
            pvpClient: pvpClient,
            sampleData: sampleData,
            randomSeed: randomSeed,
          ),
      ];
      expect(fetchOpponentsCount, 0);
      expect(
        {for (final opponent in opponents) opponent.opponentName},
        sampleData.cpuTrainerNames.toSet(),
      );
      for (final opponent in opponents) {
        expect(opponent.opponentParty.single.definition.id, isNot('sample-mugmon'));
        expect(opponent.opponentParty.single.level, 1);
        expect(opponent.definitions, dexStore.definitions);
      }
    },
  );
}
