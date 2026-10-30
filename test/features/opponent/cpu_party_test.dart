import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/cpu_party.dart';

import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

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

  /// [cpuTrainerMonsterIds] の CPU トレーナーの手持ちを、[playerLevels] の自分の手持ちに合わせて作ったもののレベル。
  List<int> cpuPartyLevels({
    required List<String> cpuTrainerMonsterIds,
    required List<int> playerLevels,
  }) => [
    for (final monster in buildCpuParty(
      monsters: [
        for (final monsterId in cpuTrainerMonsterIds)
          sampleData.monsterById(monsterId: monsterId),
      ],
      playerParty: partyWithLevels(levels: playerLevels),
    ))
      monster.level,
  ];

  test('Lv.1 の手持ち 1 体に対して、どの CPU トレーナーの手持ちも Lv.1 になる', () {
    for (final cpuTrainer in sampleData.cpuTrainers) {
      expect(
        cpuPartyLevels(
          cpuTrainerMonsterIds: cpuTrainer.monsterIds,
          playerLevels: [1],
        ),
        everyElement(1),
        reason: cpuTrainer.id,
      );
    }
  });

  test('Lv.5 と Lv.6 の手持ちに対して、どの CPU トレーナーの手持ちも平均 (切り捨て) の Lv.5 になる', () {
    for (final cpuTrainer in sampleData.cpuTrainers) {
      expect(
        cpuPartyLevels(
          cpuTrainerMonsterIds: cpuTrainer.monsterIds,
          playerLevels: [5, 6],
        ),
        everyElement(5),
        reason: cpuTrainer.id,
      );
    }
  });

  test('CPU の手持ちは見本のモンスターの並びのまま', () {
    final cpuTrainer = sampleData.cpuTrainers.first;
    expect(
      buildCpuParty(
        monsters: [
          for (final monsterId in cpuTrainer.monsterIds)
            sampleData.monsterById(monsterId: monsterId),
        ],
        playerParty: partyWithLevels(levels: [10, 20, 31]),
      ).map((monster) => monster.definition.id),
      cpuTrainer.monsterIds.map(
        (monsterId) =>
            sampleData.monsterById(monsterId: monsterId).definition.id,
      ),
    );
  });
}
