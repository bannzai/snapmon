import '../../domain/master/master_data.dart';
import '../../sample/sample_data.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../opponent/battle_definitions.dart';
import '../opponent/cpu_party.dart';
import '../opponent/pvp_client.dart';

/// 初回の導線 (手持ちが空の時に写真を選んでそのまま戦う 1 戦目) の対戦相手 (CPU トレーナー) と、その対戦に使う定義。
typedef FirstBattleOpponent = ({
  String opponentName,
  List<OwnedMonster> opponentParty,
  MasterData definitions,
});

/// 生まれたモンスターを手持ちに入れた後の [dexStore] の手持ちと戦う、初回のバトルの相手を決める。
/// 相手は対戦タブと同じく [randomSeed] で決めた CPU の相手 ([chooseRandomCpuOpponent]) で、他のユーザーの手持ち
/// (Functions の fetchOpponents) は相手にしない (本人の操作なしに他人の手持ちを CPU に操作させないため。issue #130)。
/// 図鑑の定義を読み直せない時は例外を投げる ([prepareBattleDefinitions])。
Future<FirstBattleOpponent> prepareFirstBattleOpponent({
  required DexStore dexStore,
  required PvpClient pvpClient,
  required SampleData sampleData,
  required int randomSeed,
}) async {
  final cpuOpponent = chooseRandomCpuOpponent(
    sampleData: sampleData,
    playerParty: dexStore.party,
    randomSeed: randomSeed,
  );
  return (
    opponentName: cpuOpponent.opponentName,
    opponentParty: cpuOpponent.opponentParty,
    definitions: await prepareBattleDefinitions(
      dexStore: dexStore,
      pvpClient: pvpClient,
      pvpOpponentMonsters: null,
    ),
  );
}
