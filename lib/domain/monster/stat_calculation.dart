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
/// 引く順番は HP・攻撃・防御・素早さ・命中で固定する (順番を変えると既存の値が変わるため。命中は #279 で最後に足した)。
MonsterStats individualValuesFromSeed({required int seed}) {
  final random = DeterministicRandom(seed: seed);
  int next() =>
      random.nextIntInRange(minimum: 0, maximum: individualValueMaximum);
  return MonsterStats(
    hitPoints: next(),
    attack: next(),
    defense: next(),
    speed: next(),
    accuracy: next(),
  );
}

/// Jev が判定したステータスごとの段階 [statGradeIDs] (段階の `id`) から種族値を返す。
/// 段階が master に無い・ステータスの段階が欠けている時は [StateError] を投げる。
MonsterStats baseStatsFromStatGrades({
  required Map<StatKind, String> statGradeIDs,
  required MasterData master,
}) {
  int baseStatOf({required StatKind statKind}) {
    final statGradeID = statGradeIDs[statKind];
    if (statGradeID == null) {
      throw StateError('${statKind.name} の段階が判定結果に無い');
    }
    return master.statGrades
        .firstWhere(
          (statGrade) => statGrade.id == statGradeID,
          orElse: () => throw StateError('段階 $statGradeID が master に無い'),
        )
        .baseStat;
  }

  return MonsterStats(
    hitPoints: baseStatOf(statKind: StatKind.hitPoints),
    attack: baseStatOf(statKind: StatKind.attack),
    defense: baseStatOf(statKind: StatKind.defense),
    speed: baseStatOf(statKind: StatKind.speed),
    accuracy: baseStatOf(statKind: StatKind.accuracy),
  );
}

/// Jev が判定した属性ごとの当てはまりの確率 [elementProbabilities] から、モンスターの属性を返す。
/// 確率が master の閾値以上の属性を確率の高い順 (同じなら ID 順) に上限まで選ぶ。
/// 空の一覧を返した時は master に合う属性が無く、その場で新しい属性を作る経路に進む
/// (ADR 0001「master に無い属性・技」)。
List<String> selectElementTypeIDs({
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

/// [statKind] の種族値 [baseStats] と個体値 [individualValues] が、取り得る最大 (master [master] の段階のうち
/// 最大の種族値と個体値の上限) に対してどれだけかを 0 以上 1 以下で返す。
/// カードのステータスの目盛りに使う。レベルの項を含めないのは、レベル 1 では実際の値が 11〜13・5〜7 に
/// 潰れて段階の差が見えないため (documents/game-rules.md「ステータスの計算式」)。
/// [master] に段階が無い時は [StateError] を投げる。
double statStrengthRatio({
  required StatKind statKind,
  required MonsterStats baseStats,
  required MonsterStats individualValues,
  required MasterData master,
}) {
  if (master.statGrades.isEmpty) {
    throw StateError('master にステータスの段階が無い');
  }
  return ((2 * baseStats.valueOf(statKind: statKind) +
              individualValues.valueOf(statKind: statKind)) /
          (2 *
                  master.statGrades
                      .map((statGrade) => statGrade.baseStat)
                      .reduce((left, right) => left > right ? left : right) +
              individualValueMaximum))
      // 上限・下限を double で渡す。int の 0・1 だと、はみ出た時に clamp がその int を返し、native では
      // double の戻り値に合わず実行時に TypeError になる (dart-lang/sdk#39652)
      .clamp(0.0, 1.0);
}

/// 命中の下限 (%)。種族値と個体値が最も低いモンスターでも、命中率 100 の技が 8 割 5 分ほど当たる値にした
/// (issue #279「だいたい当たれば良い」。眩暈の 70% より外れにくくするため)。
const int accuracyStatMinimumPercent = 80;

/// 命中の幅 (%)。種族値と個体値が最も高いモンスターで命中が 100 になるよう、[accuracyStatMinimumPercent] との和を 100 にした。
const int accuracyStatRangePercent = 20;

/// 命中の式の分母。種族値の段階の最大 (master の statGrades の `veryHigh` の 120) と個体値の上限の (2 × 120 + 31)。
/// master の段階を後で変えても保存済みのモンスターの命中が変わらないよう、master から引かずに固定した。
const int accuracyStatScaleDenominator = 2 * 120 + individualValueMaximum;

/// 種族値・個体値・レベルから実際のステータスを返す。
/// [statCalculationVersion] はモンスターに保存した計算手順の版で、知らない版なら [ArgumentError] を投げる。
/// 式は documents/game-rules.md「ステータスの計算式」。命中は割合 (%) のためレベルで変わらない。
/// 命中は #279 で版 1 に足した式で、版を上げなかったのは、版 1 の他の値の式を変えず、命中を持たずに保存されたモンスターも
/// 既定の種族値・個体値 ([accuracyBaseStatWithoutJudgement]・[accuracyIndividualValueWithoutJudgement]) で同じ式を使うため。
MonsterStats calculateStats({
  required MonsterStats baseStats,
  required MonsterStats individualValues,
  required int level,
  required int statCalculationVersion,
}) {
  switch (statCalculationVersion) {
    case 1:
      int scaled({required StatKind statKind}) =>
          (2 * baseStats.valueOf(statKind: statKind) +
              individualValues.valueOf(statKind: statKind)) *
          level ~/
          100;
      return MonsterStats(
        hitPoints: scaled(statKind: StatKind.hitPoints) + level + 10,
        attack: scaled(statKind: StatKind.attack) + 5,
        defense: scaled(statKind: StatKind.defense) + 5,
        speed: scaled(statKind: StatKind.speed) + 5,
        accuracy:
            accuracyStatMinimumPercent +
            (2 * baseStats.accuracy + individualValues.accuracy) *
                accuracyStatRangePercent ~/
                accuracyStatScaleDenominator,
      );
    default:
      throw ArgumentError('ステータスの計算手順の版 $statCalculationVersion を知らない');
  }
}
