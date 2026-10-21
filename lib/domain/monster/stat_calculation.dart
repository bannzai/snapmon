import '../master/master_data.dart';
import '../random/deterministic_random.dart';
import 'monster_stats.dart';

/// 新しく生まれるモンスターに保存するステータスの計算手順の版。
/// 式を変える時は版を上げて [calculateStats] に分岐を足し、古い版の式は消さない
/// (保存済みのモンスターの値を変えないため。ADR 0001「属性・技・ステータスの判定」)。
const int currentStatCalculationVersion = 1;

/// 個体値の上限。種族値 1 段 (20) の差を個体値で埋めきらない幅にするため 31 にした
/// (レベル 100 で種族値 1 段の差は (2 × 20) = 40、個体値の差は最大 31)。
const int individualValueMaximum = 31;

/// 保存した被写体の説明文 [subjectDescription] から、個体値を引く seed を返す。
int individualValueSeed({required String subjectDescription}) =>
    fnv1a32(text: subjectDescription);

/// [seed] から個体値 (各 0 以上 [individualValueMaximum] 以下) を決定的に引く。
/// 引く順番は HP・攻撃・防御・素早さで固定する (順番を変えると既存の値が変わるため)。
MonsterStats individualValuesFromSeed({required int seed}) {
  final random = DeterministicRandom(seed: seed);
  int next() =>
      random.nextIntInRange(minimum: 0, maximum: individualValueMaximum);
  return MonsterStats(
    hitPoints: next(),
    attack: next(),
    defense: next(),
    speed: next(),
  );
}

/// Jev が判定したステータスごとの段階 [statGradeIds] (段階の `id`) から種族値を返す。
/// 段階が master に無い・ステータスの段階が欠けている時は [StateError] を投げる。
MonsterStats baseStatsFromStatGrades({
  required Map<StatKind, String> statGradeIds,
  required MasterData master,
}) {
  int baseStatOf(StatKind statKind) {
    final statGradeId = statGradeIds[statKind];
    if (statGradeId == null) {
      throw StateError('${statKind.name} の段階が判定結果に無い');
    }
    return master.statGrades
        .firstWhere(
          (statGrade) => statGrade.id == statGradeId,
          orElse: () => throw StateError('段階 $statGradeId が master に無い'),
        )
        .baseStat;
  }

  return MonsterStats(
    hitPoints: baseStatOf(StatKind.hitPoints),
    attack: baseStatOf(StatKind.attack),
    defense: baseStatOf(StatKind.defense),
    speed: baseStatOf(StatKind.speed),
  );
}

/// Jev が判定した属性ごとの当てはまりの確率 [elementProbabilities] から、モンスターの属性を返す。
/// 確率が master の閾値以上の属性を確率の高い順 (同じなら ID 順) に上限まで選ぶ。
/// 空の一覧を返した時は master に合う属性が無く、その場で新しい属性を作る経路に進む
/// (ADR 0001「master に無い属性・技」)。
List<String> selectElementTypeIds({
  required Map<String, double> elementProbabilities,
  required MasterData master,
}) {
  final elementSelection = master.elementSelection;
  if (elementSelection == null) {
    throw StateError('master に elementSelection が無い');
  }
  final candidates =
      elementProbabilities.entries
          .where(
            (entry) => entry.value >= elementSelection.probabilityThreshold,
          )
          .toList()
        ..sort(
          (left, right) => left.value != right.value
              ? right.value.compareTo(left.value)
              : left.key.compareTo(right.key),
        );
  return [
    for (final candidate in candidates.take(elementSelection.maximumCount))
      candidate.key,
  ];
}

/// 種族値・個体値・レベルから実際のステータスを返す。
/// [statCalculationVersion] はモンスターに保存した計算手順の版で、知らない版なら [ArgumentError] を投げる。
/// 式は documents/game-rules.md「ステータスの計算式」。
MonsterStats calculateStats({
  required MonsterStats baseStats,
  required MonsterStats individualValues,
  required int level,
  required int statCalculationVersion,
}) {
  switch (statCalculationVersion) {
    case 1:
      int scaled(StatKind statKind) =>
          (2 * baseStats.valueOf(statKind: statKind) +
              individualValues.valueOf(statKind: statKind)) *
          level ~/
          100;
      return MonsterStats(
        hitPoints: scaled(StatKind.hitPoints) + level + 10,
        attack: scaled(StatKind.attack) + 5,
        defense: scaled(StatKind.defense) + 5,
        speed: scaled(StatKind.speed) + 5,
      );
    default:
      throw ArgumentError('ステータスの計算手順の版 $statCalculationVersion を知らない');
  }
}
