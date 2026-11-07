import 'monster_stats.dart';

/// レベルの上限 (DIRECTION.md「ゲームの仕様」の「上限は 999」)。
const int maximumLevel = 999;

/// モンスターの変わる部分。レベル・経験は戦うたびに増えて保存し、
/// HP・PP の残りとステータスの倍率はバトルの中だけで変わる (バトルの開始時に満タンと等倍へ戻す)。
class MonsterState {
  /// モンスターの状態を作る。
  const MonsterState({
    required this.level,
    required this.experience,
    required this.currentHitPoints,
    required this.remainingPowerPoints,
    required this.statModifierPercents,
  });

  /// レベル (1 以上 [maximumLevel] 以下)。
  final int level;

  /// 場に出て決着まで戦ったバトルの回数の累計 (勝敗を問わない)。レベルが上限に達した後も増える。
  final int experience;

  /// バトル中の HP の残り。0 で倒れている。
  final int currentHitPoints;

  /// バトル中の技ごとの PP の残り。キーは技の識別子。
  final Map<String, int> remainingPowerPoints;

  /// バトル中に補助技で変わったステータスの倍率 (%。100 が等倍)。キーは変えられるステータス (攻撃・防御・素早さ) で、
  /// 無いステータスは 100 (lib/domain/battle/battle_engine.dart の `statModifierPercentOf`)。
  final Map<StatKind, int> statModifierPercents;

  /// 指定した値だけを置き換えた状態を返す。
  MonsterState copyWith({
    int? level,
    int? experience,
    int? currentHitPoints,
    Map<String, int>? remainingPowerPoints,
    Map<StatKind, int>? statModifierPercents,
  }) => MonsterState(
    level: level ?? this.level,
    experience: experience ?? this.experience,
    currentHitPoints: currentHitPoints ?? this.currentHitPoints,
    remainingPowerPoints: remainingPowerPoints ?? this.remainingPowerPoints,
    statModifierPercents: statModifierPercents ?? this.statModifierPercents,
  );
}
