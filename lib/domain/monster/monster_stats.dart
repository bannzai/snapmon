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
}

/// HP・攻撃・防御・素早さの 4 つの値の組。種族値・個体値・計算したステータスのどれにも使う。
class MonsterStats {
  /// 4 つの値の組を作る。
  const MonsterStats({
    required this.hitPoints,
    required this.attack,
    required this.defense,
    required this.speed,
  });

  /// 体力 (HP)。
  final int hitPoints;

  /// 攻撃。
  final int attack;

  /// 防御。
  final int defense;

  /// 素早さ。
  final int speed;

  /// [statKind] の値を返す。
  int valueOf({required StatKind statKind}) => switch (statKind) {
    StatKind.hitPoints => hitPoints,
    StatKind.attack => attack,
    StatKind.defense => defense,
    StatKind.speed => speed,
  };

  @override
  bool operator ==(Object other) =>
      other is MonsterStats &&
      other.hitPoints == hitPoints &&
      other.attack == attack &&
      other.defense == defense &&
      other.speed == speed;

  @override
  int get hashCode => Object.hash(hitPoints, attack, defense, speed);

  @override
  String toString() =>
      'MonsterStats(hitPoints: $hitPoints, attack: $attack, defense: $defense, speed: $speed)';
}
