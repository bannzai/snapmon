import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/first_battle.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';

import '../../monster_generator_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  test(
    '候補の先頭の相手の定義を読めない時は、例外にせず CPU トレーナーと戦う (もう一度試しても同じ相手で止まり続けないため)',
    () async {
      // 本番と同じく、生まれたモンスターを手持ちに入れた後の図鑑で相手を決める (CPU の手持ちのレベルを自分の手持ちに合わせるため)
      final dexStore = DexStore(definitions: sampleData.definitions)
        ..applyServerSnapshot(
          monsters: [sampleData.monsterById(monsterId: 'sample-mugmon')],
          partyMonsterIds: ['sample-mugmon'],
          definitions: null,
        );
      final opponent = await prepareFirstBattleOpponent(
        dexStore: dexStore,
        pvpClient: PvpClient(
          fetchOpponents: () async => [
            PvpOpponent(
              opponentUid: 'opponent-uid-1',
              displayName: 'ろうそくや',
              monsters: [generatedWaxMonster(monsterId: 'opponent-wax-1')],
            ),
          ],
          fetchDefinitions: ({required base, required definitionIds}) =>
              throw Exception('permission-denied'),
          reportMonster:
              ({
                required monsterOwnerUid,
                required monsterId,
                required reason,
              }) => throw StateError('reportMonster は呼ばない'),
          blockUser: ({required blockedUid}) =>
              throw StateError('blockUser は呼ばない'),
          fetchBattleRecord: () async => null,
          fetchDisplayName: () async => null,
          updateDisplayName: ({required displayName}) async => displayName,
        ),
        sampleData: sampleData,
        randomSeed: 1,
        cpuTrainerName: 'CPU トレーナー',
      );
      expect(opponent.opponentKind, BattleOpponentKind.cpu);
      expect(opponent.pvpOpponent, isNull);
      expect(opponent.opponentName, 'CPU トレーナー');
    },
  );
}
