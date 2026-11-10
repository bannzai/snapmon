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
  const statGradeIDs = {
    StatKind.hitPoints: 'medium',
    StatKind.attack: 'low',
    StatKind.defense: 'veryHigh',
    StatKind.speed: 'veryLow',
    StatKind.accuracy: 'high',
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
        baseStatsFromStatGrades(statGradeIDs: statGradeIDs, master: master);

    expect(individualValues(), individualValues());
    // 保存済みのモンスターの値を変えないよう、固定の説明文から引いた値を固定する。
    // 期待値は FNV-1a と xorshift32 を任意精度の整数で別実装 (Python) して求めた。
    expect(
      individualValues(),
      const MonsterStats(
        hitPoints: 1,
        attack: 5,
        defense: 22,
        speed: 25,
        accuracy: 17,
      ),
    );
    expect(baseStats(), baseStats());
    expect(
      baseStats(),
      const MonsterStats(
        hitPoints: 80,
        attack: 60,
        defense: 120,
        speed: 40,
        accuracy: 100,
      ),
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
        statGradeIDs: {...statGradeIDs, StatKind.speed: 'unknown'},
        master: master,
      ),
      throwsStateError,
    );
    expect(
      () => baseStatsFromStatGrades(
        statGradeIDs: {StatKind.hitPoints: 'medium'},
        master: master,
      ),
      throwsStateError,
    );
  });

  test('属性は閾値以上を確率の高い順に上限まで選ぶ', () {
    expect(
      selectElementTypeIDs(
        elementProbabilities: {
          'steel': 0.6,
          'light': 0.9,
          'fire': 0.7,
          'water': 0.2,
        },
        master: master,
      ),
      ['light', 'fire'],
    );
    expect(
      selectElementTypeIDs(
        // 閾値 (master の elementSelection.probabilityThreshold = 0.5) より下
        elementProbabilities: {'steel': 0.49, 'water': 0.1},
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
      accuracy: 40,
    );
    const highest = MonsterStats(
      hitPoints: 120,
      attack: 120,
      defense: 120,
      speed: 120,
      accuracy: 120,
    );
    const zero = MonsterStats(
      hitPoints: 0,
      attack: 0,
      defense: 0,
      speed: 0,
      accuracy: 0,
    );
    const maximum = MonsterStats(
      hitPoints: individualValueMaximum,
      attack: individualValueMaximum,
      defense: individualValueMaximum,
      speed: individualValueMaximum,
      accuracy: individualValueMaximum,
    );

    test('レベル 1', () {
      expect(
        calculateStats(
          baseStats: lowest,
          individualValues: zero,
          level: 1,
          statCalculationVersion: 1,
        ),
        const MonsterStats(
          hitPoints: 11,
          attack: 5,
          defense: 5,
          speed: 5,
          accuracy: 85,
        ),
      );
      expect(
        calculateStats(
          baseStats: highest,
          individualValues: maximum,
          level: 1,
          statCalculationVersion: 1,
        ),
        const MonsterStats(
          hitPoints: 13,
          attack: 7,
          defense: 7,
          speed: 7,
          accuracy: 100,
        ),
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
          // 命中は割合のためレベルで変わらない
          accuracy: 85,
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
          accuracy: 100,
        ),
      );
    });

    test('命中を持たずに保存されたモンスター (#279 より前) は、既定の種族値・個体値で命中 92 になる', () {
      const json = {'hitPoints': 80, 'attack': 80, 'defense': 80, 'speed': 80};
      expect(
        calculateStats(
          baseStats: MonsterStats.fromJson(
            json: json,
            accuracyWithoutJudgement: accuracyBaseStatWithoutJudgement,
          ),
          individualValues: MonsterStats.fromJson(
            json: json,
            accuracyWithoutJudgement: accuracyIndividualValueWithoutJudgement,
          ),
          level: 1,
          statCalculationVersion: 1,
        ).accuracy,
        92,
      );
      // 保存された命中があればそれを使う
      expect(
        MonsterStats.fromJson(
          json: {...json, 'accuracy': 120},
          accuracyWithoutJudgement: accuracyBaseStatWithoutJudgement,
        ).accuracy,
        120,
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

    test('ステータスの目盛りは種族値と個体値の最大で 1、最小で (2 × 40) / (2 × 120 + 31)', () {
      expect(
        statStrengthRatio(
          statKind: StatKind.attack,
          baseStats: highest,
          individualValues: maximum,
          master: master,
        ),
        1,
      );
      expect(
        statStrengthRatio(
          statKind: StatKind.attack,
          baseStats: lowest,
          individualValues: zero,
          master: master,
        ),
        closeTo(80 / 271, 1e-9),
      );
      // 段階の最大を超える種族値 (後から master の最大の段階が下がった時等) は 1 に収める。
      // 収めた値が double であること (clamp の上限を int で渡すと int が返る) も確かめる
      final clamped = statStrengthRatio(
        statKind: StatKind.attack,
        baseStats: const MonsterStats(
          hitPoints: 130,
          attack: 130,
          defense: 130,
          speed: 130,
          accuracy: 130,
        ),
        individualValues: maximum,
        master: master,
      );
      expect(clamped, 1.0);
      expect(clamped, isA<double>());
      // レベルの項を含めないため、ステータスの種類ごとの種族値・個体値だけで決まる
      expect(
        statStrengthRatio(
          statKind: StatKind.defense,
          baseStats: const MonsterStats(
            hitPoints: 40,
            attack: 40,
            defense: 120,
            speed: 40,
            accuracy: 40,
          ),
          individualValues: const MonsterStats(
            hitPoints: 0,
            attack: 0,
            defense: 31,
            speed: 0,
            accuracy: 0,
          ),
          master: master,
        ),
        1,
      );
    });

    test('ステータスの段階が無い定義では目盛りを計算できず例外にする', () {
      expect(
        () => statStrengthRatio(
          statKind: StatKind.attack,
          baseStats: lowest,
          individualValues: zero,
          master: const MasterData(
            version: 1,
            elementTypes: [],
            typeChart: {},
            moves: [],
            effects: [],
            statGrades: [],
            elementSelection: null,
          ),
        ),
        throwsStateError,
      );
    });
  });
}
