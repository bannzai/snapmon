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
