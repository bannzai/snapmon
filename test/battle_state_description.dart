import 'package:snapmon/domain/battle/battle_state.dart';

/// [state] の中身 (両陣営の手持ち・ログ・乱数・勝者・フィールド) を、テストで比べられる行の一覧にする
/// ([BattleState] と中の型は `==` を持たないため)。2 つの状態が同じ行の一覧になるなら、画面に出る内容と次のラウンドの計算が同じになる。
List<String> describeBattleState({required BattleState state}) => [
  'turnNumber=${state.turnNumber} randomState=${state.randomState} winner=${state.winner?.name}',
  'battleDate=${state.battleDate.toIso8601String()} opponentDamagePercent=${state.opponentDamagePercent}',
  'field=${state.field?.kind.name} remainingRounds=${state.field?.remainingRounds} swapped=${state.field?.swappedStatKinds}',
  for (final side in BattleSideID.values) ...[
    '${side.name}: activeMemberIndex=${state.partyOf(side: side).activeMemberIndex}',
    for (final member in state.partyOf(side: side).members)
      '${side.name}: ${member.definition.id} maximumHitPointsPercent=${member.maximumHitPointsPercent} '
          'level=${member.state.level} experience=${member.state.experience} hitPoints=${member.state.currentHitPoints} '
          'powerPoints=${member.state.remainingPowerPoints} statModifiers=${member.state.statModifierPercents} '
          'statusConditions=${[for (final condition in member.state.statusConditions.values) '${condition.kind.name}/${condition.remainingTurns}/${condition.stackCount}/${condition.cursedStatKind?.name}']}',
  ],
  for (final event in state.events) _describeBattleEvent(event: event),
];

/// [event] の種類と中身を 1 行にする。
String _describeBattleEvent({required BattleEvent event}) => switch (event) {
  MoveUsedEvent() =>
    'turn ${event.turnNumber} MoveUsed ${event.attackerSide.name} ${event.attackerMonsterID} move=${event.moveID} '
        'replaced=${event.replacedMoveID} typeMultiplier=${event.typeMultiplier} damage=${event.damage} '
        'defenderHitPoints=${event.defenderRemainingHitPoints} specialEffect=${event.specialEffect} '
        'statModifierChanges=${[for (final change in event.statModifierChanges) '${change.side.name}/${change.statKind.name}/${change.previousPercent}/${change.newPercent}']} '
        'recovered=${event.recoveredHitPoints} attackerHitPoints=${event.attackerRemainingHitPoints} '
        'oneHitKnockout=${event.isOneHitKnockout} selfDestructed=${event.selfDestructed}',
  ActionFailedEvent() =>
    'turn ${event.turnNumber} ActionFailed ${event.side.name} ${event.monsterID} move=${event.moveID} reason=${event.reason.name}',
  StatusConditionInflictedEvent() =>
    'turn ${event.turnNumber} StatusConditionInflicted ${event.side.name} ${event.monsterID} ${event.kind.name} '
        'stackCount=${event.stackCount} replaced=${event.replacedKind?.name} cursed=${event.cursedStatKind?.name}',
  StatusConditionCuredEvent() =>
    'turn ${event.turnNumber} StatusConditionCured ${event.side.name} ${event.monsterID} '
        '${[for (final kind in event.kinds) kind.name]} cause=${event.cause.name}',
  StatusConditionDamageEvent() =>
    'turn ${event.turnNumber} StatusConditionDamage ${event.side.name} ${event.monsterID} ${event.kind.name} '
        'damage=${event.damage} hitPoints=${event.remainingHitPoints}',
  FieldEffectStartedEvent() =>
    'turn ${event.turnNumber} FieldEffectStarted ${event.side.name} ${event.kind.name}',
  FieldEffectShuffledEvent() =>
    'turn ${event.turnNumber} FieldEffectShuffled ${event.statKinds}',
  FieldEffectEndedEvent() =>
    'turn ${event.turnNumber} FieldEffectEnded ${event.kind.name}',
  MonsterFaintedEvent() =>
    'turn ${event.turnNumber} MonsterFainted ${event.side.name} ${event.monsterID}',
  MonsterSwitchedInEvent() =>
    'turn ${event.turnNumber} MonsterSwitchedIn ${event.side.name} ${event.monsterID} withdrawn=${event.withdrawnMonsterID}',
  LevelUpEvent() =>
    'turn ${event.turnNumber} LevelUp ${event.side.name} ${event.monsterID} newLevel=${event.newLevel}',
  BattleFinishedEvent() =>
    'turn ${event.turnNumber} BattleFinished winner=${event.winner.name}',
};
