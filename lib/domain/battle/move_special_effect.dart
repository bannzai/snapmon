import 'dart:developer' as developer;

import '../master/move.dart';
import '../monster/monster_stats.dart';
import 'battle_state.dart';
import 'move_expression.dart';

/// [move] の特殊効果を、技を使う時点の状況に当てはめた威力の倍率 (%) と、バトルのログに出す説明文を返す。
/// [move] が特殊効果を持たなければ null。
///
/// [attacker]・[defender] は技を使う直前の状態 (HP・この技の PP は使う前の値)、[attackerStats]・[defenderStats] は
/// その時点のレベルで計算したステータス、[attackerMovesFirst] はそのターンに [attacker] が相手より先に行動したか、
/// [battleDate] は対戦日 (端末の時刻)。これらを式の変数 ([moveExpressionVariableNames]) に入れて評価する。
///
/// 式を評価できない時 (文法の誤り・未知の変数・0 での割り算・上限を超える値) と、値が負の時は、倍率 100 (効果なし) にしてログに残す。
/// 負を効果なしにするのは、負の威力がダメージを負にして相手の HP を回復させるため。
({int powerPercent, String description})? calculateMoveSpecialEffect({
  required Move move,
  required BattleMonster attacker,
  required BattleMonster defender,
  required MonsterStats attackerStats,
  required MonsterStats defenderStats,
  required bool attackerMovesFirst,
  required DateTime battleDate,
}) {
  final specialEffect = move.specialEffect;
  if (specialEffect == null) {
    return null;
  }
  final powerPercent = () {
    try {
      final value = evaluateMoveExpression(
        node: parseMoveExpression(source: specialEffect.power),
        variables: {
          'self.hitPoints': attacker.state.currentHitPoints,
          'self.maximumHitPoints': attackerStats.hitPoints,
          'self.attack': attackerStats.attack,
          'self.defense': attackerStats.defense,
          'self.speed': attackerStats.speed,
          'self.level': attacker.state.level,
          'opponent.hitPoints': defender.state.currentHitPoints,
          'opponent.maximumHitPoints': defenderStats.hitPoints,
          'opponent.attack': defenderStats.attack,
          'opponent.defense': defenderStats.defense,
          'opponent.speed': defenderStats.speed,
          'opponent.level': defender.state.level,
          'move.power': move.power,
          // 使える技は残り PP が 1 以上ある技だけのため (battle_engine.dart の PP の消費と同じ前提)、残り PP は必ずある
          'move.remainingPowerPoints':
              attacker.state.remainingPowerPoints[move.id]!,
          'move.maximumPowerPoints': move.powerPoints,
          'movesFirst': attackerMovesFirst ? 1 : 0,
          'sharesElementType':
              attacker.definition.elementTypeIds.any(
                defender.definition.elementTypeIds.contains,
              )
              ? 1
              : 0,
          'battleDate.year': battleDate.year,
          'battleDate.month': battleDate.month,
          'battleDate.day': battleDate.day,
        },
      );
      if (value >= 0) {
        return value;
      }
      developer.log('${move.id}: 式の値が負 ($value)', name: 'move_special_effect');
    } on MoveExpressionException catch (error) {
      developer.log('${move.id}: $error', name: 'move_special_effect');
    }
    return 100;
  }();
  return (
    powerPercent: powerPercent,
    description:
        '${specialEffect.rule} (今回は ${formatPowerPercent(powerPercent: powerPercent)} 倍)',
  );
}

/// 倍率 [powerPercent] (%) を「1.5」「2」「1.25」のような倍の数の文字列にする。double を通さず整数から組み立てる
/// (Web と端末で表示が食い違わないため)。
String formatPowerPercent({required int powerPercent}) {
  final fractionText = (powerPercent % 100)
      .toString()
      .padLeft(2, '0')
      .replaceFirst(RegExp(r'0$'), '');
  return fractionText.isEmpty || fractionText == '0'
      ? '${powerPercent ~/ 100}'
      : '${powerPercent ~/ 100}.$fractionText';
}
