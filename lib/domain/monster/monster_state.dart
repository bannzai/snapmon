import '../battle/status_condition.dart';
import 'monster_stats.dart';

/// レベルの上限 (DIRECTION.md「ゲームの仕様」の「上限は 999」)。
const int maximumLevel = 999;

/// モンスターの変わる部分。レベル・経験は戦うたびに増えて保存し、Action Card で覚えさせた技は覚えさせる・忘れさせるたびに保存し、
/// HP・PP の残り・ステータスの倍率・状態はバトルの中だけで変わる (バトルの開始時に満タン・等倍・状態なしへ戻す)。
class MonsterState {
  /// モンスターの状態を作る。
  const MonsterState({
    required this.level,
    required this.experience,
    required this.actionCardMoveIds,
    required this.currentHitPoints,
    required this.remainingPowerPoints,
    required this.statModifierPercents,
    required this.statusConditions,
  });

  /// レベル (1 以上 [maximumLevel] 以下)。
  final int level;

  /// 場に出て決着まで戦ったバトルの回数の累計 (勝敗を問わない)。レベルが上限に達した後も増える。
  final int experience;

  /// Action Card で覚えさせた技の ID (覚えさせた順。`users/{uid}/monsters/{monsterId}.actionCardMoveIds`)。技の枠の決め方は
  /// lib/domain/battle/battle_engine.dart の `equippedMoveIds`。
  final List<String> actionCardMoveIds;

  /// バトル中の HP の残り。0 で倒れている。
  final int currentHitPoints;

  /// バトル中の技ごとの PP の残り。キーは技の識別子。
  final Map<String, int> remainingPowerPoints;

  /// バトル中に補助技で変わったステータスの倍率 (%。100 が等倍)。キーは変えられるステータス (攻撃・防御・素早さ) で、
  /// 無いステータスは 100 (lib/domain/battle/battle_engine.dart の `statModifierPercentOf`)。
  final Map<StatKind, int> statModifierPercents;

  /// バトル中に付いている状態。同じ種類の状態は 1 つだけ持つ。
  final Map<StatusConditionKind, StatusCondition> statusConditions;

  /// 指定した値だけを置き換えた状態を返す。
  MonsterState copyWith({
    int? level,
    int? experience,
    int? currentHitPoints,
    Map<String, int>? remainingPowerPoints,
    Map<StatKind, int>? statModifierPercents,
    Map<StatusConditionKind, StatusCondition>? statusConditions,
  }) => MonsterState(
    level: level ?? this.level,
    experience: experience ?? this.experience,
    actionCardMoveIds: actionCardMoveIds,
    currentHitPoints: currentHitPoints ?? this.currentHitPoints,
    remainingPowerPoints: remainingPowerPoints ?? this.remainingPowerPoints,
    statModifierPercents: statModifierPercents ?? this.statModifierPercents,
    statusConditions: statusConditions ?? this.statusConditions,
  );
}
