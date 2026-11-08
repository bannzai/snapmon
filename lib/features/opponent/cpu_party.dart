import '../../domain/random/deterministic_random.dart';
import '../../sample/sample_data.dart';
import '../dex/owned_monster.dart';

/// [party] (1 体以上) のレベルの平均 (切り捨て)。
int averagePartyLevel({required List<OwnedMonster> party}) =>
    party.fold<int>(0, (sum, monster) => sum + monster.level) ~/ party.length;

/// CPU の手持ちを返す。[monsters] (見本のモンスター) のレベルを、どれも [playerParty] (1 体以上) の平均と同じにする。
/// どの CPU トレーナーでも同じレベルで、手持ちの数の差はレベルで埋めない (2026-10-30 の DIRECTION.md「決めたこと」)。
List<OwnedMonster> buildCpuParty({
  required List<OwnedMonster> monsters,
  required List<OwnedMonster> playerParty,
}) => [
  for (final monster in monsters)
    OwnedMonster(
      definition: monster.definition,
      level: averagePartyLevel(party: playerParty),
      artPath: monster.artPath,
      definitionIds: monster.definitionIds,
      decoration: monster.decoration,
      decorationVersion: monster.decorationVersion,
    ),
];

/// 乱数で決めた CPU の相手。トレーナーの名前と、自分の手持ちに合わせたレベルの手持ち。
typedef RandomCpuOpponent = ({
  String opponentName,
  List<OwnedMonster> opponentParty,
});

/// [randomSeed] で CPU の相手を決める (対戦の相手は毎回ランダム。issue #217)。名前は [sampleData] の CPU トレーナーの名前から 1 つ、
/// 手持ちは見本のモンスターから [playerParty] (1 体以上) と同じ数を重複なく選び、レベルは自分の手持ちの平均に合わせる ([buildCpuParty])。
/// [playerParty] のどれかと同じ絵 (同じ画像のパス) の見本のモンスターは選ばない。自分の手持ちに見本のモンスターがいるのは
/// DEBUG ビルドの見本の生成・投入の時で、それ以外の手持ちの絵は Storage にあり見本と重ならない。見本のモンスターは手持ちの
/// 上限の 2 倍以上いる (test/sample/sample_data_test.dart で検査する) ため、除いても必ず数が足りる。同じ引数からは同じ相手になる。
RandomCpuOpponent chooseRandomCpuOpponent({
  required SampleData sampleData,
  required List<OwnedMonster> playerParty,
  required int randomSeed,
}) {
  final random = DeterministicRandom(seed: randomSeed);
  final playerArtPaths = {for (final monster in playerParty) ?monster.artPath};
  final candidates = [
    for (final monster in sampleData.monsters)
      if (!playerArtPaths.contains(monster.artPath)) monster,
  ];
  return (
    opponentName:
        sampleData.cpuTrainerNames[random.nextIntInRange(
          minimum: 0,
          maximum: sampleData.cpuTrainerNames.length - 1,
        )],
    opponentParty: buildCpuParty(
      monsters: [
        for (var index = 0; index < playerParty.length; index++)
          candidates.removeAt(
            random.nextIntInRange(minimum: 0, maximum: candidates.length - 1),
          ),
      ],
      playerParty: playerParty,
    ),
  );
}
