import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/cpu_party.dart';

import '../../monster_generator_fixture.dart';
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

  /// 見本のモンスター全員を、[playerLevels] の自分の手持ちに合わせた CPU の手持ちにしたもののレベル。
  List<int> cpuPartyLevels({required List<int> playerLevels}) => [
    for (final monster in buildCpuParty(
      monsters: sampleData.monsters,
      playerParty: partyWithLevels(levels: playerLevels),
    ))
      monster.level,
  ];

  test('Lv.1 の手持ち 1 体に対して、CPU の手持ちはどれも Lv.1 になる', () {
    expect(cpuPartyLevels(playerLevels: [1]), everyElement(1));
  });

  test('Lv.5 と Lv.6 の手持ちに対して、CPU の手持ちはどれも平均 (切り捨て) の Lv.5 になる', () {
    expect(cpuPartyLevels(playerLevels: [5, 6]), everyElement(5));
  });

  test('CPU の手持ちは渡したモンスターの並びのまま', () {
    expect(
      buildCpuParty(
        monsters: sampleData.monsters,
        playerParty: partyWithLevels(levels: [10, 20, 31]),
      ).map((monster) => monster.definition.id),
      sampleData.monsters.map((monster) => monster.definition.id),
    );
  });

  group('chooseRandomCpuOpponent', () {
    // 見本の手持ち 3 体 (先頭の 3 体) と同じ絵の見本のモンスターは相手に出ない
    final playerParty = sampleData.monsters.take(3).toList();
    final playerArtPaths = {for (final monster in playerParty) monster.artPath};
    final opponents = [
      for (var randomSeed = 1; randomSeed <= 100; randomSeed++)
        chooseRandomCpuOpponent(
          sampleData: sampleData,
          playerParty: playerParty,
          randomSeed: randomSeed,
        ),
    ];

    test('名前は CPU トレーナーの名前から選び、seed によって全員が出る', () {
      expect({
        for (final opponent in opponents) opponent.opponentName,
      }, sampleData.cpuTrainerNames.toSet());
    });

    test('手持ちは自分の手持ちと同じ数で、重複せず、自分の手持ちと同じ絵を含まず、レベルは自分の手持ちの平均', () {
      for (final opponent in opponents) {
        expect(opponent.opponentParty, hasLength(playerParty.length));
        expect({
          for (final monster in opponent.opponentParty) monster.definition.id,
        }, hasLength(playerParty.length));
        for (final monster in opponent.opponentParty) {
          expect(playerArtPaths.contains(monster.artPath), isFalse);
          expect(monster.level, averagePartyLevel(party: playerParty));
        }
      }
    });

    test('手持ちの組み合わせ (並びを含む) は seed によって変わる', () {
      expect({
        for (final opponent in opponents)
          opponent.opponentParty
              .map((monster) => monster.definition.id)
              .join(','),
      }, hasLength(greaterThan(1)));
    });

    test('同じ seed からは同じ相手になる', () {
      RandomCpuOpponent choose() => chooseRandomCpuOpponent(
        sampleData: sampleData,
        playerParty: playerParty,
        randomSeed: 7,
      );
      expect(choose().opponentName, choose().opponentName);
      expect(
        choose().opponentParty.map((monster) => monster.definition.id),
        choose().opponentParty.map((monster) => monster.definition.id),
      );
    });

    test('手持ちが 1 体なら相手も 1 体で、見本の絵を持たない (生成した) 手持ちはどの見本のモンスターも除かない', () {
      final generatedParty = [generatedWaxMonster(monsterId: 'm1')];
      expect(
        {
          for (var randomSeed = 1; randomSeed <= 100; randomSeed++)
            chooseRandomCpuOpponent(
              sampleData: sampleData,
              playerParty: generatedParty,
              randomSeed: randomSeed,
            ).opponentParty.single.definition.id,
        },
        {for (final monster in sampleData.monsters) monster.definition.id},
      );
    });
  });
}
