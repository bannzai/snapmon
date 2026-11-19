import 'battle_engine.dart';
import 'battle_state.dart';

/// [state] の 2 つの陣営を入れ替えた状態を返す (利用者の陣営と相手の陣営・ログの陣営・勝った陣営)。
/// 人との対戦では、2 人の端末が同じ向き (先に待っていた側を利用者の陣営とする向き) で [advanceRound] を計算し
/// (同じ素早さの時の乱数と相打ちの扱いが陣営で違うため)、後から来た側の端末は結果をこの関数で自分の向きに直して画面に出す。
/// 2 回入れ替えると元の状態に戻る。[BattleState.opponentDamagePercent] は陣営に付く値だが、人との対戦はどちらの陣営も
/// 補正なし (100) のため動かさない。
BattleState mirrorBattleState({required BattleState state}) => BattleState(
  player: state.opponent,
  opponent: state.player,
  turnNumber: state.turnNumber,
  randomState: state.randomState,
  events: [for (final event in state.events) _mirrorBattleEvent(event: event)],
  winner: switch (state.winner) {
    null => null,
    final winner => winner,
  },
  battleDate: state.battleDate,
  field: state.field,
  opponentDamagePercent: state.opponentDamagePercent,
);

/// [event] の陣営を入れ替えたログを返す。陣営を持たないログはそのまま返す。
BattleEvent _mirrorBattleEvent({required BattleEvent event}) => switch (event) {
  MoveUsedEvent() => MoveUsedEvent(
    turnNumber: event.turnNumber,
    attackerSide: otherSide(side: event.attackerSide),
    attackerMonsterID: event.attackerMonsterID,
    moveID: event.moveID,
    typeMultiplier: event.typeMultiplier,
    damage: event.damage,
    defenderRemainingHitPoints: event.defenderRemainingHitPoints,
    specialEffect: event.specialEffect,
    statModifierChanges: [
      for (final change in event.statModifierChanges)
        StatModifierChange(
          side: otherSide(side: change.side),
          statKind: change.statKind,
          previousPercent: change.previousPercent,
          newPercent: change.newPercent,
        ),
    ],
    recoveredHitPoints: event.recoveredHitPoints,
    attackerRemainingHitPoints: event.attackerRemainingHitPoints,
    replacedMoveID: event.replacedMoveID,
    isOneHitKnockout: event.isOneHitKnockout,
    selfDestructed: event.selfDestructed,
  ),
  ActionFailedEvent() => ActionFailedEvent(
    turnNumber: event.turnNumber,
    side: otherSide(side: event.side),
    monsterID: event.monsterID,
    moveID: event.moveID,
    reason: event.reason,
  ),
  StatusConditionInflictedEvent() => StatusConditionInflictedEvent(
    turnNumber: event.turnNumber,
    side: otherSide(side: event.side),
    monsterID: event.monsterID,
    kind: event.kind,
    stackCount: event.stackCount,
    replacedKind: event.replacedKind,
    cursedStatKind: event.cursedStatKind,
  ),
  StatusConditionCuredEvent() => StatusConditionCuredEvent(
    turnNumber: event.turnNumber,
    side: otherSide(side: event.side),
    monsterID: event.monsterID,
    kinds: event.kinds,
    cause: event.cause,
  ),
  StatusConditionDamageEvent() => StatusConditionDamageEvent(
    turnNumber: event.turnNumber,
    side: otherSide(side: event.side),
    monsterID: event.monsterID,
    kind: event.kind,
    damage: event.damage,
    remainingHitPoints: event.remainingHitPoints,
  ),
  FieldEffectStartedEvent() => FieldEffectStartedEvent(
    turnNumber: event.turnNumber,
    side: otherSide(side: event.side),
    kind: event.kind,
  ),
  FieldEffectShuffledEvent() || FieldEffectEndedEvent() => event,
  MonsterFaintedEvent() => MonsterFaintedEvent(
    turnNumber: event.turnNumber,
    side: otherSide(side: event.side),
    monsterID: event.monsterID,
  ),
  MonsterSwitchedInEvent() => MonsterSwitchedInEvent(
    turnNumber: event.turnNumber,
    side: otherSide(side: event.side),
    monsterID: event.monsterID,
    withdrawnMonsterID: event.withdrawnMonsterID,
  ),
  LevelUpEvent() => LevelUpEvent(
    turnNumber: event.turnNumber,
    side: otherSide(side: event.side),
    monsterID: event.monsterID,
    newLevel: event.newLevel,
  ),
  BattleFinishedEvent() => BattleFinishedEvent(
    turnNumber: event.turnNumber,
    winner: otherSide(side: event.winner),
  ),
};
