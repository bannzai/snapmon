import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';
import 'package:snapmon/domain/monster/stat_calculation.dart';
import 'package:snapmon/domain/random/deterministic_random.dart';

void main() {
  final master = MasterData.fromJson(
    json:
        jsonDecode(File('assets/master/master.json').readAsStringSync())
            as Map<String, dynamic>,
  );
  const description = '赤い陶器のマグカップ。手のひらほどの大きさで硬い';
  const statGradeIds = {
    StatKind.hitPoints: 'medium',
    StatKind.attack: 'low',
    StatKind.defense: 'veryHigh',
    StatKind.speed: 'veryLow',
  };

  test('FNV-1a は既知の値と一致する (実行環境で値が変わらない実装であること)', () {
    // FNV-1a 32 bit の参照値 (http://www.isthe.com/chongo/tech/comp/fnv/ のテストベクタ)
    expect(fnv1a32(text: ''), 0x811C9DC5);
    expect(fnv1a32(text: 'a'), 0xE40C292C);
    expect(fnv1a32(text: 'foobar'), 0xBF9CF968);
  });

  test('同じ説明文・同じ Jev の結果からは同じ種族値・個体値になる', () {
    MonsterStats individualValues() => individualValuesFromSeed(
      seed: individualValueSeed(subjectDescription: description),
    );
    MonsterStats baseStats() =>
        baseStatsFromStatGrades(statGradeIds: statGradeIds, master: master);

    expect(individualValues(), individualValues());
    // 保存済みのモンスターの値を変えないよう、固定の説明文から引いた値を固定する。
    // 期待値は FNV-1a と xorshift32 を任意精度の整数で別実装 (Python) して求めた。
    expect(
      individualValues(),
      const MonsterStats(hitPoints: 1, attack: 5, defense: 22, speed: 25),
    );
    expect(baseStats(), baseStats());
    expect(
      baseStats(),
      const MonsterStats(hitPoints: 80, attack: 60, defense: 120, speed: 40),
    );
  });

  test('個体値はすべて 0 以上 31 以下で、説明文が違えば別の値になる', () {
    final valuesBySeed = <MonsterStats>{};
    for (var index = 0; index < 200; index++) {
      final individualValues = individualValuesFromSeed(
        seed: individualValueSeed(subjectDescription: '$description $index'),
      );
      for (final statKind in StatKind.values) {
        expect(
          individualValues.valueOf(statKind: statKind),
          inInclusiveRange(0, individualValueMaximum),
        );
      }
      valuesBySeed.add(individualValues);
    }
    expect(valuesBySeed.length, greaterThan(150));
  });

  test('段階が master に無い・欠けている時は例外にする', () {
    expect(
      () => baseStatsFromStatGrades(
        statGradeIds: {...statGradeIds, StatKind.speed: 'unknown'},
        master: master,
      ),
      throwsStateError,
    );
    expect(
      () => baseStatsFromStatGrades(
        statGradeIds: {StatKind.hitPoints: 'medium'},
        master: master,
      ),
      throwsStateError,
    );
  });

  test('属性は閾値以上を確率の高い順に上限まで選ぶ', () {
    expect(
      selectElementTypeIds(
        elementProbabilities: {
          'metal': 0.6,
          'glass': 0.9,
          'heat': 0.7,
          'water': 0.2,
        },
        master: master,
      ),
      ['glass', 'heat'],
    );
    expect(
      selectElementTypeIds(
        elementProbabilities: {'metal': 0.49, 'water': 0.1},
        master: master,
      ),
      isEmpty,
    );
  });

  group('ステータスの値の範囲', () {
    const lowest = MonsterStats(
      hitPoints: 40,
      attack: 40,
      defense: 40,
      speed: 40,
    );
    const highest = MonsterStats(
      hitPoints: 120,
      attack: 120,
      defense: 120,
      speed: 120,
    );
    const zero = MonsterStats(hitPoints: 0, attack: 0, defense: 0, speed: 0);
    const maximum = MonsterStats(
      hitPoints: individualValueMaximum,
      attack: individualValueMaximum,
      defense: individualValueMaximum,
      speed: individualValueMaximum,
    );

    test('レベル 1', () {
      expect(
        calculateStats(
          baseStats: lowest,
          individualValues: zero,
          level: 1,
          statCalculationVersion: 1,
        ),
        const MonsterStats(hitPoints: 11, attack: 5, defense: 5, speed: 5),
      );
      expect(
        calculateStats(
          baseStats: highest,
          individualValues: maximum,
          level: 1,
          statCalculationVersion: 1,
        ),
        const MonsterStats(hitPoints: 13, attack: 7, defense: 7, speed: 7),
      );
    });

    test('レベル 999', () {
      expect(
        calculateStats(
          baseStats: lowest,
          individualValues: zero,
          level: 999,
          statCalculationVersion: 1,
        ),
        const MonsterStats(
          hitPoints: 1808,
          attack: 804,
          defense: 804,
          speed: 804,
        ),
      );
      expect(
        calculateStats(
          baseStats: highest,
          individualValues: maximum,
          level: 999,
          statCalculationVersion: 1,
        ),
        const MonsterStats(
          hitPoints: 3716,
          attack: 2712,
          defense: 2712,
          speed: 2712,
        ),
      );
    });

    test('知らない計算手順の版は例外にする', () {
      expect(
        () => calculateStats(
          baseStats: lowest,
          individualValues: zero,
          level: 1,
          statCalculationVersion: 999,
        ),
        throwsArgumentError,
      );
    });
  });
}
