import '../monster/monster_definition.dart';
import '../monster/monster_state.dart';
import '../monster/monster_stats.dart';
import 'status_condition.dart';

/// 手持ちの数の上限 (DIRECTION.md「ゲームの仕様」の「手持ちは 3 体まで」)。
const int maximumPartySize = 3;

/// バトルの陣営。CPU 対戦では [opponent] が CPU、非同期 PvP では相手の手持ちを CPU が操作する。
enum BattleSideId {
  /// 端末を操作している利用者の陣営。
  player,

  /// 相手の陣営。
  opponent,
}

/// バトルに出ている 1 体。生まれた時に決まる部分と変わる部分の組。
class BattleMonster {
  /// バトルに出ている 1 体を作る。
  const BattleMonster({required this.definition, required this.state});

  /// 生まれた時に決まる部分。
  final MonsterDefinition definition;

  /// 変わる部分 (レベル・経験・HP・PP の残り・ステータスの倍率・状態)。
  final MonsterState state;

  /// HP が 0 で倒れているか。
  bool get isFainted => state.currentHitPoints <= 0;
}

/// 一方の陣営の手持ちと、場に出ているモンスター。
class BattleParty {
  /// 陣営を作る。
  const BattleParty({required this.members, required this.activeMemberIndex});

  /// 手持ち (1 体以上 [maximumPartySize] 体以下)。
  final List<BattleMonster> members;

  /// 場に出ているモンスターの [members] の位置。
  final int activeMemberIndex;

  /// 場に出ているモンスター。
  BattleMonster get activeMember => members[activeMemberIndex];

  /// 手持ちがすべて倒れているか。
  bool get isDefeated => members.every((member) => member.isFainted);
}

/// 自分のターンに陣営が選ぶ行動。
sealed class BattleAction {
  const BattleAction();
}

/// 技を使う行動。
class UseMoveAction extends BattleAction {
  /// 技を使う行動を作る。
  const UseMoveAction({required this.moveId});

  /// 使う技の識別子。
  final String moveId;
}

/// 使える攻撃技が無い (PP が 0 か補助技しか残っていない) 時の行動 (わるあがき)。
class StruggleAction extends BattleAction {
  /// わるあがきの行動を作る。
  const StruggleAction();
}

/// バトルのログの 1 件。画面はこの列を順に再生して演出する。
sealed class BattleEvent {
  const BattleEvent({required this.turnNumber});

  /// 起きたターンの番号 (1 から)。ターンは片方の陣営の 1 回の行動で、両陣営が 1 ターンずつ行動する区切りがラウンド
  /// (documents/game-rules.md「用語」)。ラウンド r の先に動く側のターンが 2r-1、後に動く側が 2r。
  final int turnNumber;
}

/// 補助技の効果で、場のモンスター 1 体のステータスの倍率が変わろうとした結果。
class StatModifierChange {
  /// ステータスの倍率の変化を作る。
  const StatModifierChange({
    required this.side,
    required this.statKind,
    required this.previousPercent,
    required this.newPercent,
  });

  /// 倍率が変わったモンスターの陣営。
  final BattleSideId side;

  /// 変わったステータス (攻撃・防御・素早さ)。
  final StatKind statKind;

  /// 変わる前の倍率 (%)。
  final int previousPercent;

  /// 変わった後の倍率 (%)。重ねがけの上限に当たって変わらなかった時は [previousPercent] と同じ。
  final int newPercent;
}

/// 技 (またはわるあがき) を使った。
class MoveUsedEvent extends BattleEvent {
  /// 技を使ったログを作る。
  const MoveUsedEvent({
    required super.turnNumber,
    required this.attackerSide,
    required this.attackerMonsterId,
    required this.moveId,
    required this.typeMultiplier,
    required this.damage,
    required this.defenderRemainingHitPoints,
    required this.specialEffect,
    required this.statModifierChanges,
    required this.recoveredHitPoints,
    required this.attackerRemainingHitPoints,
    this.replacedMoveId,
    this.isOneHitKnockout = false,
    this.selfDestructed = false,
  });

  /// 技を使った陣営。
  final BattleSideId attackerSide;

  /// 技を使ったモンスターの識別子。
  final String attackerMonsterId;

  /// 使った技の識別子。わるあがきの時は null。
  final String? moveId;

  /// 属性の相性の倍率 (防御側の属性ごとの倍率の積)。
  final double typeMultiplier;

  /// 与えたダメージ。
  final int damage;

  /// 技を受けた側の残りの HP。
  final int defenderRemainingHitPoints;

  /// 技の特殊効果の威力の倍率 (%) とログの説明文 (`calculateMoveSpecialEffect` の結果)。特殊効果の無い技とわるあがきは null。
  final ({int powerPercent, String description})? specialEffect;

  /// 技の効果でステータスの倍率が変わろうとした結果。変化の値が 0 の出力は入れない。効果の無い技とわるあがきは空。
  final List<StatModifierChange> statModifierChanges;

  /// 技の効果で技を使った側が回復した HP (最大 HP で丸めた後の値)。回復しない技は 0。
  final int recoveredHitPoints;

  /// 技を使った側の、回復の後 (自爆なら自爆の後) の残りの HP。
  final int attackerRemainingHitPoints;

  /// 混乱で選んだ技の代わりに [moveId] が出た時の、選んだ技の識別子。選んだ技がそのまま出た時は null。
  final String? replacedMoveId;

  /// 一撃必殺が当たり、威力に関係なく相手の HP を 0 にしたか。
  final bool isOneHitKnockout;

  /// 自爆で技を使った側の HP が 0 になったか。
  final bool selfDestructed;
}

/// 行動が失敗した理由。
enum ActionFailureReason {
  /// 技が外れた (命中率・眩暈)。
  missed,

  /// 麻痺で攻撃技が出せなかった。
  paralysis,

  /// 気絶で動けなかった。
  stun,

  /// 眠っていて動けなかった。
  sleep,

  /// 凍っていて動けなかった。
  frozen,
}

/// 選んだ行動が失敗した (外れた・状態で動けなかった)。外れた時は PP を使い、状態で動けなかった時は PP を使わない。
class ActionFailedEvent extends BattleEvent {
  /// 失敗のログを作る。
  const ActionFailedEvent({
    required super.turnNumber,
    required this.side,
    required this.monsterId,
    required this.moveId,
    required this.reason,
  });

  /// 失敗した陣営。
  final BattleSideId side;

  /// 失敗したモンスターの識別子。
  final String monsterId;

  /// 使おうとした技の識別子。わるあがきの時は null。
  final String? moveId;

  /// 失敗した理由。
  final ActionFailureReason reason;
}

/// 状態が付いた (重なった・置き換わった時を含む)。
class StatusConditionInflictedEvent extends BattleEvent {
  /// 状態が付いたログを作る。
  const StatusConditionInflictedEvent({
    required super.turnNumber,
    required this.side,
    required this.monsterId,
    required this.kind,
    required this.stackCount,
    required this.replacedKind,
    required this.cursedStatKind,
  });

  /// 状態が付いたモンスターの陣営。
  final BattleSideId side;

  /// 状態が付いたモンスターの識別子。
  final String monsterId;

  /// 付いた状態。
  final StatusConditionKind kind;

  /// 付いた後の重なりの数 (毒・やけど)。重なりを持たない状態は 1。
  final int stackCount;

  /// この状態に置き換わって消えた状態 (眠気が眠りになった時の眠気)。無ければ null。
  final StatusConditionKind? replacedKind;

  /// 呪いで半分になるステータス。呪い以外は null。
  final StatKind? cursedStatKind;
}

/// 状態が消えた理由。
enum StatusConditionCureCause {
  /// 技の効果で解除した。
  move,

  /// 残りのターンが 0 になった。
  expired,

  /// 技のダメージを受けて解けた (凍結)。
  damaged,
}

/// 状態が消えた。
class StatusConditionCuredEvent extends BattleEvent {
  /// 状態が消えたログを作る。
  const StatusConditionCuredEvent({
    required super.turnNumber,
    required this.side,
    required this.monsterId,
    required this.kinds,
    required this.cause,
  });

  /// 状態が消えたモンスターの陣営。
  final BattleSideId side;

  /// 状態が消えたモンスターの識別子。
  final String monsterId;

  /// 消えた状態 (1 つ以上)。
  final List<StatusConditionKind> kinds;

  /// 消えた理由。
  final StatusConditionCureCause cause;
}

/// 状態 (毒) でダメージを受けた。
class StatusConditionDamageEvent extends BattleEvent {
  /// 状態のダメージのログを作る。
  const StatusConditionDamageEvent({
    required super.turnNumber,
    required this.side,
    required this.monsterId,
    required this.kind,
    required this.damage,
    required this.remainingHitPoints,
  });

  /// ダメージを受けたモンスターの陣営。
  final BattleSideId side;

  /// ダメージを受けたモンスターの識別子。
  final String monsterId;

  /// ダメージの元の状態。
  final StatusConditionKind kind;

  /// 受けたダメージ。
  final int damage;

  /// 受けた後の残りの HP。
  final int remainingHitPoints;
}

/// フィールドの効果が始まった (続いている効果を同じ技で始め直した時を含む)。
class FieldEffectStartedEvent extends BattleEvent {
  /// フィールドの効果の開始のログを作る。
  const FieldEffectStartedEvent({
    required super.turnNumber,
    required this.side,
    required this.kind,
  });

  /// 技を使った陣営。
  final BattleSideId side;

  /// 始まった効果。
  final FieldEffectKind kind;
}

/// 入れ替えのフィールドで、ラウンドの始めにステータスが入れ替わった。
class FieldEffectShuffledEvent extends BattleEvent {
  /// 入れ替えのログを作る。
  const FieldEffectShuffledEvent({
    required super.turnNumber,
    required this.statKinds,
  });

  /// 入れ替わったステータスの組。
  final (StatKind, StatKind) statKinds;
}

/// フィールドの効果が終わった。
class FieldEffectEndedEvent extends BattleEvent {
  /// フィールドの効果の終了のログを作る。
  const FieldEffectEndedEvent({required super.turnNumber, required this.kind});

  /// 終わった効果。
  final FieldEffectKind kind;
}

/// モンスターが倒れた。
class MonsterFaintedEvent extends BattleEvent {
  /// 倒れたログを作る。
  const MonsterFaintedEvent({
    required super.turnNumber,
    required this.side,
    required this.monsterId,
  });

  /// 倒れたモンスターの陣営。
  final BattleSideId side;

  /// 倒れたモンスターの識別子。
  final String monsterId;
}

/// 倒れたモンスターの代わりに次のモンスターが場に出た。
class MonsterSwitchedInEvent extends BattleEvent {
  /// 交代のログを作る。
  const MonsterSwitchedInEvent({
    required super.turnNumber,
    required this.side,
    required this.monsterId,
  });

  /// 交代した陣営。
  final BattleSideId side;

  /// 場に出たモンスターの識別子。
  final String monsterId;
}

/// 決着後にモンスターのレベルが上がった。上限に達していて上がらなかった時も、経験の加算として出す。
class LevelUpEvent extends BattleEvent {
  /// レベルアップのログを作る。
  const LevelUpEvent({
    required super.turnNumber,
    required this.side,
    required this.monsterId,
    required this.newLevel,
  });

  /// レベルが上がった陣営。
  final BattleSideId side;

  /// レベルが上がったモンスターの識別子。
  final String monsterId;

  /// 上がった後のレベル。
  final int newLevel;
}

/// バトルの決着がついた。
class BattleFinishedEvent extends BattleEvent {
  /// 決着のログを作る。
  const BattleFinishedEvent({required super.turnNumber, required this.winner});

  /// 勝った陣営。
  final BattleSideId winner;
}

/// バトルの状態。`advanceRound` (battle_engine.dart) は状態を書き換えず、次の状態を返す。
class BattleState {
  /// バトルの状態を作る。
  const BattleState({
    required this.player,
    required this.opponent,
    required this.turnNumber,
    required this.randomState,
    required this.events,
    required this.winner,
    required this.battleDate,
    required this.field,
  });

  /// 利用者の陣営。
  final BattleParty player;

  /// 相手の陣営。
  final BattleParty opponent;

  /// 次に解決するラウンドの最初のターンの番号 (1 から。ラウンドごとに 2 進む)。
  final int turnNumber;

  /// 乱数 (行動順の同速判定・ダメージの乱数幅・命中・状態の付与と長さ・混乱・入れ替え) の内部状態。同じ状態と同じ行動からは同じ結果になる。
  final int randomState;

  /// ここまでのログ。
  final List<BattleEvent> events;

  /// 勝った陣営。決着前は null。
  final BattleSideId? winner;

  /// 対戦日 (バトルを始めた日時)。技の特殊効果の入力に渡す (外部要因の効果を足す時の枠)。
  final DateTime battleDate;

  /// 続いているフィールドの効果。無ければ null。
  final BattleField? field;

  /// 次に解決するラウンドの番号 (1 から)。
  int get roundNumber => (turnNumber + 1) ~/ 2;

  /// [side] の陣営を返す。
  BattleParty partyOf({required BattleSideId side}) => switch (side) {
    BattleSideId.player => player,
    BattleSideId.opponent => opponent,
  };
}
