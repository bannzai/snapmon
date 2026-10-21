import '../monster/monster_definition.dart';
import '../monster/monster_state.dart';

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

  /// 変わる部分 (レベル・経験・HP・PP の残り)。
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

/// 1 ターンに陣営が選ぶ行動。
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

  /// 起きたターンの番号 (1 から)。
  final int turnNumber;
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

/// バトルの状態。`advanceTurn` (battle_engine.dart) は状態を書き換えず、次の状態を返す。
class BattleState {
  /// バトルの状態を作る。
  const BattleState({
    required this.player,
    required this.opponent,
    required this.turnNumber,
    required this.randomState,
    required this.events,
    required this.winner,
  });

  /// 利用者の陣営。
  final BattleParty player;

  /// 相手の陣営。
  final BattleParty opponent;

  /// 次に解決するターンの番号 (1 から)。
  final int turnNumber;

  /// 乱数 (行動順の同速判定・ダメージの乱数幅) の内部状態。同じ状態と同じ行動からは同じ結果になる。
  final int randomState;

  /// ここまでのログ。
  final List<BattleEvent> events;

  /// 勝った陣営。決着前は null。
  final BattleSideId? winner;

  /// [side] の陣営を返す。
  BattleParty partyOf({required BattleSideId side}) => switch (side) {
    BattleSideId.player => player,
    BattleSideId.opponent => opponent,
  };
}
