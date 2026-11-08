import '../monster/monster_stats.dart';

/// 状態 (状態異常) の種類。効果と続く長さは documents/game-rules.md「状態」が正で、
/// 計算は lib/domain/battle/battle_engine.dart が行う。
enum StatusConditionKind {
  /// 毒。持ち主のターンの終わりに、最大 HP × 重なり / 16 のダメージを受ける。毒の技を受けるたびに重なりが増える。
  poison,

  /// 麻痺。次の自分のターンに攻撃技 (わるあがきを含む) が失敗する。補助技は使える。
  paralysis,

  /// 気絶。次の自分のターンに全ての行動が失敗する。
  stun,

  /// やけど。与える攻撃のダメージが半分になり、受けるダメージが (10 + 重なり) / 10 倍になる。
  burn,

  /// 眠気。素早さが半分になる。眠気の中でもう一度眠気を受けると眠りになる。
  drowsy,

  /// 眠り。1〜3 ターンの間、全ての行動が失敗する。
  sleep,

  /// 呪い。攻撃・防御・素早さのどれか 1 つ (付与の時に決まる) が半分になる。重ねられない。
  curse,

  /// 混乱。2〜4 ターンの間、1/2 の確率で選んだ技の代わりに他の使える技が出る。
  confusion,

  /// 眩暈。3 ターンの間、技の命中率が 70% になる。
  dizzy,

  /// 興奮。攻撃が 1.5 倍、防御が半分になる。
  excited,

  /// 凍結。1〜3 ターンの間、全ての行動が失敗する。技のダメージを受けると解ける。
  frozen,
}

/// 続く長さが決まっている状態 (ターン数で消える状態) と、そのターン数の範囲 (最小・最大)。
/// ここに無い状態は倒れるまで続く。
const Map<StatusConditionKind, ({int minimum, int maximum})>
statusConditionDurationRanges = {
  StatusConditionKind.paralysis: (minimum: 1, maximum: 1),
  StatusConditionKind.stun: (minimum: 1, maximum: 1),
  StatusConditionKind.sleep: (minimum: 1, maximum: 3),
  StatusConditionKind.confusion: (minimum: 2, maximum: 4),
  StatusConditionKind.dizzy: (minimum: 3, maximum: 3),
  StatusConditionKind.frozen: (minimum: 1, maximum: 3),
};

/// 重なりを持つ状態 (毒・やけど) の重なりの上限。毒は 4 (最大 HP の 1/4 のダメージ)、やけどは 5 (受けるダメージ 1.5 倍) で止める。
const Map<StatusConditionKind, int> statusConditionStackMaximums = {
  StatusConditionKind.poison: 4,
  StatusConditionKind.burn: 5,
};

/// 全ての行動が失敗する状態。
const Set<StatusConditionKind> incapacitatingStatusConditionKinds = {
  StatusConditionKind.stun,
  StatusConditionKind.sleep,
  StatusConditionKind.frozen,
};

/// バトル中のモンスター 1 体に付いている状態 1 つ。
class StatusCondition {
  /// 状態を作る。
  const StatusCondition({
    required this.kind,
    required this.remainingTurns,
    required this.stackCount,
    required this.cursedStatKind,
  });

  /// 状態の種類。
  final StatusConditionKind kind;

  /// 残りのターン数。持ち主のターンの終わりに 1 減り、0 になると消える。倒れるまで続く状態は null。
  final int? remainingTurns;

  /// 重なりの数 (毒・やけど)。重なりを持たない状態は 1。
  final int stackCount;

  /// 呪いで半分になるステータス。呪い以外は null。
  final StatKind? cursedStatKind;

  /// 指定した値だけを置き換えた状態を返す。
  StatusCondition copyWith({int? remainingTurns, int? stackCount}) =>
      StatusCondition(
        kind: kind,
        remainingTurns: remainingTurns ?? this.remainingTurns,
        stackCount: stackCount ?? this.stackCount,
        cursedStatKind: cursedStatKind,
      );
}

/// 技の特殊効果が付与する状態と、その確率。
class StatusConditionInfliction {
  /// 付与する状態を作る。
  const StatusConditionInfliction({
    required this.kind,
    required this.chancePercent,
  });

  /// 付与する状態。
  final StatusConditionKind kind;

  /// 付与する確率 (%)。100 なら必ず付与する。
  final int chancePercent;
}

/// フィールドの効果の種類。両陣営の場のモンスターにかかり、技で始まりラウンド数で終わる。
enum FieldEffectKind {
  /// 入れ替え。各ラウンドの始めに攻撃・防御・素早さから 2 つを選び、両陣営の場のモンスターでその 2 つの値を入れ替える。
  statShuffle,
}

/// フィールドの効果が続くラウンド数。技を使ったラウンドの次のラウンドから数える。
const int fieldEffectDurationRounds = 3;

/// バトル中のフィールドの効果。
class BattleField {
  /// フィールドの効果を作る。
  const BattleField({
    required this.kind,
    required this.remainingRounds,
    required this.swappedStatKinds,
  });

  /// 効果の種類。
  final FieldEffectKind kind;

  /// 残りのラウンド数。ラウンドの始めに 1 減り、0 のラウンドの始めに消える。
  final int remainingRounds;

  /// 今のラウンドで入れ替わっているステータスの組。入れ替えがまだ無いラウンド (技を使ったラウンド) は null。
  final (StatKind, StatKind)? swappedStatKinds;
}
