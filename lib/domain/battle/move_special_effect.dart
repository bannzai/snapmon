import 'dart:developer' as developer;

import '../master/move.dart';
import '../monster/monster_stats.dart';
import 'battle_state.dart';
import 'move_expression.dart';

/// 技を使う時点の状況を、式の変数 ([moveExpressionVariableNames]) の名前と値にして返す。
///
/// [attacker]・[defender] は技を使う直前の状態 (HP・この技の PP は使う前の値)、[attackerStats]・[defenderStats] は
/// その時点のレベルで計算し、補助技で変わった倍率を掛けたステータス (lib/domain/battle/battle_engine.dart の `effectiveStats`)、
/// [attackerMovesFirst] はそのターンに [attacker] が相手より先に行動したか、[battleDate] は対戦日 (端末の時刻)。
Map<String, int> moveExpressionVariables({
  required Move move,
  required BattleMonster attacker,
  required BattleMonster defender,
  required MonsterStats attackerStats,
  required MonsterStats defenderStats,
  required bool attackerMovesFirst,
  required DateTime battleDate,
}) => {
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
  'move.remainingPowerPoints': attacker.state.remainingPowerPoints[move.id]!,
  'move.maximumPowerPoints': move.powerPoints,
  'movesFirst': attackerMovesFirst ? 1 : 0,
  'sharesElementType':
      attacker.definition.elementTypeIDs.any(
        defender.definition.elementTypeIDs.contains,
      )
      ? 1
      : 0,
  'battleDate.year': battleDate.year,
  'battleDate.month': battleDate.month,
  'battleDate.day': battleDate.day,
};

/// [source] の式を [variables] で評価した値を返す。評価できない時 (文法の誤り・未知の変数・0 での割り算・上限を超える値) は
/// null を返し、[moveID] と理由を端末のログに残す。
int? _evaluateOrLog({
  required String moveID,
  required String source,
  required Map<String, int> variables,
}) {
  try {
    return evaluateMoveExpression(
      node: parseMoveExpression(source: source),
      variables: variables,
    );
  } on MoveExpressionException catch (error) {
    developer.log('$moveID: $error', name: 'move_special_effect');
    return null;
  }
}

/// [move] の特殊効果の威力の倍率の式 (`power`) を、技を使う時点の状況 ([variables]。[moveExpressionVariables] の結果) に当てはめた
/// 倍率 (%) と、バトルのログに出す説明文を返す。[move] が威力の倍率の式を持たなければ null。
///
/// 式を評価できない時と、値が負の時は、倍率 100 (効果なし) にしてログに残す。
/// 負を効果なしにするのは、負の威力がダメージを負にして相手の HP を回復させるため。
({int powerPercent, String description})? calculateMoveSpecialEffect({
  required Move move,
  required Map<String, int> variables,
}) {
  final specialEffect = move.specialEffect;
  final powerSource = specialEffect?.power;
  if (specialEffect == null || powerSource == null) {
    return null;
  }
  final value = _evaluateOrLog(
    moveID: move.id,
    source: powerSource,
    variables: variables,
  );
  if (value != null && value < 0) {
    developer.log('${move.id}: 式の値が負 ($value)', name: 'move_special_effect');
  }
  final powerPercent = value == null || value < 0 ? 100 : value;
  return (
    powerPercent: powerPercent,
    description:
        '${specialEffect.rule} (今回は ${formatPowerPercent(powerPercent: powerPercent)} 倍)',
  );
}

/// [move] の特殊効果のステータスの変化と回復の式を、技を使う時点の状況 ([variables]) に当てはめた値を返す。
/// ステータスの変化は倍率 (%) に足す値 (重ねがけの上限で丸める前)、回復は HP を回復する量 (最大 HP で丸める前)。
/// 評価できない式は、その出力だけを効果なし (変化 0・回復 0) にしてログに残す。回復の値が負の時も 0 にする
/// (負の回復は HP を減らし、補助技が自分を攻撃することになるため)。
({
  Map<StatKind, int> selfStatChanges,
  Map<StatKind, int> opponentStatChanges,
  int hitPointsRecovery,
})
calculateMoveStatusEffect({
  required Move move,
  required Map<String, int> variables,
}) {
  final specialEffect = move.specialEffect;
  Map<StatKind, int> evaluateStatChanges({
    required Map<StatKind, String> statChanges,
  }) => {
    for (final MapEntry(key: statKind, value: source) in statChanges.entries)
      statKind:
          _evaluateOrLog(
            moveID: move.id,
            source: source,
            variables: variables,
          ) ??
          0,
  };
  final recoverySource = specialEffect?.selfHitPointsRecovery;
  final recovery = recoverySource == null
      ? 0
      : _evaluateOrLog(
              moveID: move.id,
              source: recoverySource,
              variables: variables,
            ) ??
            0;
  return (
    selfStatChanges: evaluateStatChanges(
      statChanges: specialEffect?.selfStatChanges ?? const {},
    ),
    opponentStatChanges: evaluateStatChanges(
      statChanges: specialEffect?.opponentStatChanges ?? const {},
    ),
    hitPointsRecovery: recovery < 0 ? 0 : recovery,
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
