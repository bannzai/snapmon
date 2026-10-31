import '../../domain/master/master_data.dart';
import '../../domain/random/deterministic_random.dart';
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
/// 相手は CPU トレーナーだけで、自分の手持ちと同じ絵の見本のモンスターを持つトレーナーを除いた中から ([excludeCpuTrainersWithSameArt])
/// [randomSeed] で選ぶ ([chooseFirstBattleCpuTrainer])。他のユーザーの手持ち (Functions の fetchOpponents) は相手にしない
/// (本人の操作なしに他人の手持ちを CPU に操作させないため。issue #130)。CPU トレーナーの手持ちのレベルは自分の手持ちに合わせる ([buildCpuParty])。
/// 図鑑の定義を読み直せない時は例外を投げる ([prepareBattleDefinitions])。
Future<FirstBattleOpponent> prepareFirstBattleOpponent({
  required DexStore dexStore,
  required PvpClient pvpClient,
  required SampleData sampleData,
  required int randomSeed,
}) async {
  final cpuTrainer = chooseFirstBattleCpuTrainer(
    cpuTrainers: excludeCpuTrainersWithSameArt(
      sampleData: sampleData,
      playerParty: dexStore.party,
    ),
    randomSeed: randomSeed,
  );
  return (
    opponentName: cpuTrainer.name,
    opponentParty: buildCpuParty(
      monsters: [
        for (final monsterId in cpuTrainer.monsterIds)
          sampleData.monsterById(monsterId: monsterId),
      ],
      playerParty: dexStore.party,
    ),
    definitions: await prepareBattleDefinitions(
      dexStore: dexStore,
      pvpClient: pvpClient,
      pvpOpponentMonsters: null,
    ),
  );
}

/// [sampleData] の CPU トレーナーから、[playerParty] のどれかと同じ絵 (同じ画像のパス) の見本のモンスターを持つトレーナーを除いて返す。
/// 自分の手持ちに見本のモンスターがいるのは DEBUG ビルドの見本の生成・投入の時で、それ以外の手持ちの絵は Storage にあり見本と重ならない。
/// 全員が除かれる時は全員を返す (相手がいないよりは同じ絵の方がよいため)。
List<SampleOpponent> excludeCpuTrainersWithSameArt({
  required SampleData sampleData,
  required List<OwnedMonster> playerParty,
}) {
  final playerArtPaths = {for (final monster in playerParty) ?monster.artPath};
  final cpuTrainers = [
    for (final cpuTrainer in sampleData.cpuTrainers)
      if (!cpuTrainer.monsterIds.any(
        (monsterId) => playerArtPaths.contains(
          sampleData.monsterById(monsterId: monsterId).artPath,
        ),
      ))
        cpuTrainer,
  ];
  return cpuTrainers.isEmpty ? sampleData.cpuTrainers : cpuTrainers;
}

/// 初回のバトルの相手を [cpuTrainers] (1 人以上) から [randomSeed] で 1 人選ぶ。同じ引数からは同じ相手になる。
SampleOpponent chooseFirstBattleCpuTrainer({
  required List<SampleOpponent> cpuTrainers,
  required int randomSeed,
}) =>
    cpuTrainers[DeterministicRandom(
      seed: randomSeed,
    ).nextIntInRange(minimum: 0, maximum: cpuTrainers.length - 1)];
