import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/cpu_party.dart';
import 'package:snapmon/sample/sample_data.dart';

import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();
  final cpuMonsters = [
    for (final monsterId
        in sampleData.opponents
            .firstWhere((opponent) => opponent.id == cpuOpponentId)
            .monsterIds)
      sampleData.monsterById(monsterId: monsterId),
  ];

  /// 見本のモンスターを [levels] のレベルにした手持ち。
  List<OwnedMonster> partyWithLevels({required List<int> levels}) => [
    for (final (index, level) in levels.indexed)
      OwnedMonster(
        definition: sampleData.monsters[index].definition,
        level: level,
        artPath: null,
        definitionIds: const [],
        decoration: null,
        decorationVersion: null,
      ),
  ];

  test('CPU トレーナーは見本のモンスターを 3 体持つ', () {
    expect(cpuMonsters, hasLength(3));
  });

  test('CPU の手持ちのレベルは自分の手持ちの平均 ±2 に収まり、同じ seed からは同じになる', () {
    final playerParty = partyWithLevels(levels: [10, 20, 31]);
    expect(averagePartyLevel(party: playerParty), 20);
    for (var randomSeed = 1; randomSeed <= 50; randomSeed++) {
      final cpuParty = buildCpuParty(
        monsters: cpuMonsters,
        playerParty: playerParty,
        randomSeed: randomSeed,
      );
      expect(
        cpuParty.map((monster) => monster.definition.id),
        cpuMonsters.map((monster) => monster.definition.id),
      );
      for (final monster in cpuParty) {
        expect(monster.level, inInclusiveRange(18, 22));
      }
      expect(
        buildCpuParty(
          monsters: cpuMonsters,
          playerParty: playerParty,
          randomSeed: randomSeed,
        ).map((monster) => monster.level),
        cpuParty.map((monster) => monster.level),
      );
    }
  });

  test('自分の手持ちのレベルが低くても CPU のレベルは 1 を下回らない', () {
    for (var randomSeed = 1; randomSeed <= 50; randomSeed++) {
      for (final monster in buildCpuParty(
        monsters: cpuMonsters,
        playerParty: partyWithLevels(levels: [1]),
        randomSeed: randomSeed,
      )) {
        expect(monster.level, inInclusiveRange(1, 3));
      }
    }
  });
}
