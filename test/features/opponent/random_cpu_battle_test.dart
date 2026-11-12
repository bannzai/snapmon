import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/opponent/random_cpu_battle.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../pvp_client_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// [dexStore] の今の手持ちで、乱数で選んだ CPU との対戦の画面を作る。
  Future<BattleScreen> prepare({required DexStore dexStore}) =>
      prepareRandomCpuBattleScreen(
        dexStore: dexStore,
        pvpClient: fakePvpClient(
          calls: RecordedPvpCalls(),
          fetchOpponents: () async => [],
          extraDefinitions: null,
          battleRecord: null,
          profile: null,
          reportMonster: () async {},
          blockUser: () async {},
          updateDisplayName: ({required displayName}) async => displayName,
          updateIcon: ({required photo}) async => 'users/uid/icons/upload.png',
        ),
        sampleData: sampleData,
        battleRecorder: fakeBattleRecorder(
          calls: RecordedBattleCalls(),
          startBattleRecord: () async => null,
          recordedLevels: const {},
        ),
        cardSharer: fakeCardSharer(
          calls: RecordedShareCalls(),
          artImage: null,
          shareResultStatus: ShareResultStatus.success,
        ),
        playerProfile: null,
      );

  test('手持ちがある時は、その時の手持ちと同じ数の CPU の手持ちで初回の導線ではない対戦の画面を作る', () async {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters);
    final battleScreen = await prepare(dexStore: dexStore);
    expect(
      battleScreen.playerParty.map((monster) => monster.definition.id),
      dexStore.party.map((monster) => monster.definition.id),
    );
    expect(battleScreen.opponentParty, hasLength(dexStore.party.length));
    expect(battleScreen.opponentKind, BattleOpponentKind.cpu);
    expect(battleScreen.firstBattleBornMonster, isNull);
  });

  test('手持ちが空の時は対戦の画面を作らずに StateError を投げる', () async {
    final dexStore = DexStore(definitions: sampleData.definitions);
    expect(dexStore.party, isEmpty);
    await expectLater(prepare(dexStore: dexStore), throwsStateError);
  });
}
