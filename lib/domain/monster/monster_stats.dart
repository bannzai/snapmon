/// ステータスの種類。
enum StatKind {
  /// 体力 (HP)。
  hitPoints,

  /// 攻撃。
  attack,

  /// 防御。
  defense,

  /// 素早さ。
  speed,

  /// 命中。計算したステータスでは、使う技の命中率が 100 未満の時にそれに掛ける割合 (%)。
  accuracy,
}

/// 命中を持たずに保存された (#279 より前に生まれた) モンスターの、命中の種族値。
/// Jev の段階が無いため、段階の真ん中の「ふつう」(master の statGrades の `medium`) の種族値にした。
const int accuracyBaseStatWithoutJudgement = 80;

/// 命中を持たずに保存された (#279 より前に生まれた) モンスターの、命中の個体値。
/// 説明文から引き直すと端末とサーバーで別の処理が要るため、個体値の範囲 (0〜31) の真ん中にした。
const int accuracyIndividualValueWithoutJudgement = 15;

/// HP・攻撃・防御・素早さ・命中の 5 つの値の組。種族値・個体値・計算したステータスのどれにも使う。
class MonsterStats {
  /// 5 つの値の組を作る。
  const MonsterStats({
    required this.hitPoints,
    required this.attack,
    required this.defense,
    required this.speed,
    required this.accuracy,
  });

  /// `hitPoints`・`attack`・`defense`・`speed`・`accuracy` を持つ JSON から値の組を読む。
  /// `accuracy` は #279 より前に生まれたモンスターに無く、無ければ [accuracyWithoutJudgement] にする。
  factory MonsterStats.fromJson({
    required Map<String, dynamic> json,
    required int accuracyWithoutJudgement,
  }) => MonsterStats(
    hitPoints: json['hitPoints'] as int,
    attack: json['attack'] as int,
    defense: json['defense'] as int,
    speed: json['speed'] as int,
    accuracy: json['accuracy'] as int? ?? accuracyWithoutJudgement,
  );

  /// 体力 (HP)。
  final int hitPoints;

  /// 攻撃。
  final int attack;

  /// 防御。
  final int defense;

  /// 素早さ。
  final int speed;

  /// 命中。
  final int accuracy;

  /// [statKind] の値を返す。
  int valueOf({required StatKind statKind}) => switch (statKind) {
    StatKind.hitPoints => hitPoints,
    StatKind.attack => attack,
    StatKind.defense => defense,
    StatKind.speed => speed,
    StatKind.accuracy => accuracy,
  };

  @override
  bool operator ==(Object other) =>
      other is MonsterStats &&
      other.hitPoints == hitPoints &&
      other.attack == attack &&
      other.defense == defense &&
      other.speed == speed &&
      other.accuracy == accuracy;

  @override
  int get hashCode => Object.hash(hitPoints, attack, defense, speed, accuracy);

  @override
  String toString() =>
      'MonsterStats(hitPoints: $hitPoints, attack: $attack, defense: $defense, speed: $speed, accuracy: $accuracy)';
}
