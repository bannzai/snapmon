import '../master/move.dart';
import '../monster/monster_stats.dart';
import 'battle_state.dart';

/// [move] の特殊効果を、技を使う時点の状況に当てはめた威力の倍率 (%) と、バトルのログに出す説明文を返す。
/// [move] が特殊効果を持たなければ null。条件を満たさない・割合が 0 の時は倍率 100 (効果なし) を返す。
///
/// [attacker]・[defender] は技を使う直前の状態 (HP・この技の PP は使う前の値)、[attackerStats]・[defenderStats] は
/// その時点のレベルで計算したステータス、[attackerMovesFirst] はそのターンに [attacker] が相手より先に行動したか。
/// [battleDate] は対戦日で、今の種類はどれも使わない (外部要因 (対戦日・天気) の種類を足す時の入力の枠)。
///
/// 端末 (iOS / Android / Web) で同じ結果になるよう、倍率は整数の掛け算と切り捨ての割り算だけで計算する。
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
  final maximumPowerPercent = specialEffect.maximumPowerPercent;

  /// [numerator] / [denominator] の割合に比例して、100% (1 倍。効果なし) から [maximumPowerPercent] まで上がる倍率。
  /// [denominator] が 0 以下 (最大 PP が 1 の技など、割合を決められない時) は効果なしの 100% にする。
  int percentByRatio({required int numerator, required int denominator}) =>
      denominator <= 0
      ? 100
      : 100 + (maximumPowerPercent - 100) * numerator ~/ denominator;

  /// [condition] を満たす時だけ [maximumPowerPercent] になる倍率。
  int percentByCondition({required bool condition}) =>
      condition ? maximumPowerPercent : 100;

  final sharesElementType = attacker.definition.elementTypeIds.any(
    defender.definition.elementTypeIds.contains,
  );
  final powerPercent = switch (specialEffect.kind) {
    MoveSpecialEffectKind.opponentHitPointsLow => percentByRatio(
      numerator: defenderStats.hitPoints - defender.state.currentHitPoints,
      denominator: defenderStats.hitPoints,
    ),
    MoveSpecialEffectKind.ownHitPointsLow => percentByRatio(
      numerator: attackerStats.hitPoints - attacker.state.currentHitPoints,
      denominator: attackerStats.hitPoints,
    ),
    MoveSpecialEffectKind.tougherOpponent => percentByCondition(
      condition: defenderStats.defense > attackerStats.attack,
    ),
    // 最初に使う時 (残りが最大) は 100%、最後の 1 回 (残り 1) で最大にする。
    // 使える技は残り PP が 1 以上ある技だけのため (battle_engine.dart の PP の消費と同じ前提)、残り PP は必ずある
    MoveSpecialEffectKind.powerPointsLow => percentByRatio(
      numerator:
          move.powerPoints - attacker.state.remainingPowerPoints[move.id]!,
      denominator: move.powerPoints - 1,
    ),
    MoveSpecialEffectKind.sameElementAsOpponent => percentByCondition(
      condition: sharesElementType,
    ),
    MoveSpecialEffectKind.differentElementFromOpponent => percentByCondition(
      condition: !sharesElementType,
    ),
    MoveSpecialEffectKind.movesFirst => percentByCondition(
      condition: attackerMovesFirst,
    ),
    MoveSpecialEffectKind.movesLast => percentByCondition(
      condition: !attackerMovesFirst,
    ),
  };
  return (
    powerPercent: powerPercent,
    description:
        '${_moveSpecialEffectRule(kind: specialEffect.kind)} (今回は ${formatPowerPercent(powerPercent: powerPercent)} 倍)',
  );
}

/// 技の枠に出す、[kind] の効果の短い説明。390pt 幅の画面で 2 列に並べた枠に 1 行で収まる長さにしている。
String moveSpecialEffectSummary({required MoveSpecialEffectKind kind}) =>
    switch (kind) {
      MoveSpecialEffectKind.opponentHitPointsLow => '相手が弱るほど強い',
      MoveSpecialEffectKind.ownHitPointsLow => '自分が弱るほど強い',
      MoveSpecialEffectKind.tougherOpponent => '硬い相手に強い',
      MoveSpecialEffectKind.powerPointsLow => 'PP が減るほど強い',
      MoveSpecialEffectKind.sameElementAsOpponent => '同じ属性の相手に強い',
      MoveSpecialEffectKind.differentElementFromOpponent => '違う属性の相手に強い',
      MoveSpecialEffectKind.movesFirst => '先に動くと強い',
      MoveSpecialEffectKind.movesLast => '後に動くと強い',
    };

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

/// バトルのログに出す、[kind] の効果の規則の説明。
String _moveSpecialEffectRule({required MoveSpecialEffectKind kind}) =>
    switch (kind) {
      MoveSpecialEffectKind.opponentHitPointsLow => '相手の HP が減っているほど威力が上がる',
      MoveSpecialEffectKind.ownHitPointsLow => '自分の HP が減っているほど威力が上がる',
      MoveSpecialEffectKind.tougherOpponent => '相手の防御が自分の攻撃より高いと威力が上がる',
      MoveSpecialEffectKind.powerPointsLow => 'この技の残り PP が少ないほど威力が上がる',
      MoveSpecialEffectKind.sameElementAsOpponent => '相手と同じ属性を持つと威力が上がる',
      MoveSpecialEffectKind.differentElementFromOpponent =>
        '相手と同じ属性を持たないと威力が上がる',
      MoveSpecialEffectKind.movesFirst => '先に行動すると威力が上がる',
      MoveSpecialEffectKind.movesLast => '後に行動すると威力が上がる',
    };
