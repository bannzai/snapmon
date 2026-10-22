import 'dart:math' as math;

import '../../domain/monster/monster_state.dart';
import '../../domain/random/deterministic_random.dart';
import '../dex/owned_monster.dart';

/// CPU の手持ちのレベルを、自分の手持ちの平均からどれだけ揺らすか (#15 の「相手のレベルは自分の平均 ±2」)。
const int cpuLevelSpread = 2;

/// [party] (1 体以上) のレベルの平均 (切り捨て)。
int averagePartyLevel({required List<OwnedMonster> party}) =>
    party.fold<int>(0, (sum, monster) => sum + monster.level) ~/ party.length;

/// CPU の手持ちを返す。[monsters] (見本のモンスター) のレベルを、[playerParty] (1 体以上) の平均 ±[cpuLevelSpread] の範囲で
/// [randomSeed] から 1 体ずつ決め直す (1 以上 [maximumLevel] 以下に収める)。同じ引数からは同じ手持ちになる。
List<OwnedMonster> buildCpuParty({
  required List<OwnedMonster> monsters,
  required List<OwnedMonster> playerParty,
  required int randomSeed,
}) {
  final random = DeterministicRandom(seed: randomSeed);
  final playerAverageLevel = averagePartyLevel(party: playerParty);
  return [
    for (final monster in monsters)
      OwnedMonster(
        definition: monster.definition,
        level: math.min(
          maximumLevel,
          math.max(
            1,
            playerAverageLevel +
                random.nextIntInRange(
                  minimum: -cpuLevelSpread,
                  maximum: cpuLevelSpread,
                ),
          ),
        ),
      ),
  ];
}
