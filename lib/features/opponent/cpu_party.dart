import 'dart:math' as math;

import '../../domain/monster/monster_state.dart';
import '../../domain/random/deterministic_random.dart';
import '../dex/owned_monster.dart';

/// CPU の手持ちのレベルを、中心 ([cpuCenterLevel]。自分の手持ちの平均にトレーナーごとのずれを足した値) からどれだけ揺らすか
/// (#15 の「相手のレベルは自分の平均 ±2」)。
const int cpuLevelSpread = 2;

/// [party] (1 体以上) のレベルの平均 (切り捨て)。
int averagePartyLevel({required List<OwnedMonster> party}) =>
    party.fold<int>(0, (sum, monster) => sum + monster.level) ~/ party.length;

/// CPU トレーナーの手持ちのレベルの中心 ([playerParty] (1 体以上) の平均に [levelOffset] を足した値を 1 以上 [maximumLevel] 以下に収めたもの)。
int cpuCenterLevel({
  required List<OwnedMonster> playerParty,
  required int levelOffset,
}) => math.min(
  maximumLevel,
  math.max(1, averagePartyLevel(party: playerParty) + levelOffset),
);

/// CPU の手持ちを返す。[monsters] (見本のモンスター) のレベルを、[cpuCenterLevel] ±[cpuLevelSpread] の範囲で
/// [randomSeed] から 1 体ずつ決め直す (1 以上 [maximumLevel] 以下に収める)。同じ引数からは同じ手持ちになる。
List<OwnedMonster> buildCpuParty({
  required List<OwnedMonster> monsters,
  required List<OwnedMonster> playerParty,
  required int levelOffset,
  required int randomSeed,
}) {
  final random = DeterministicRandom(seed: randomSeed);
  final centerLevel = cpuCenterLevel(
    playerParty: playerParty,
    levelOffset: levelOffset,
  );
  return [
    for (final monster in monsters)
      OwnedMonster(
        definition: monster.definition,
        level: math.min(
          maximumLevel,
          math.max(
            1,
            centerLevel +
                random.nextIntInRange(
                  minimum: -cpuLevelSpread,
                  maximum: cpuLevelSpread,
                ),
          ),
        ),
        artPath: monster.artPath,
        definitionIds: monster.definitionIds,
        decoration: monster.decoration,
        decorationVersion: monster.decorationVersion,
      ),
  ];
}
