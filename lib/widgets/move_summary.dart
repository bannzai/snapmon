import 'package:flutter/material.dart';

import '../domain/battle/move_special_effect.dart';
import '../domain/master/master_data.dart';
import '../domain/master/move.dart';
import '../l10n/l10n.dart';
import '../theme/snapmon_colors.dart';
import '../theme/snapmon_radii.dart';
import '../theme/snapmon_text_styles.dart';
import 'monster_parts.dart';

/// 技の中身を「名前 / 属性の札・威力・PP / 特殊効果の説明」の 3 段に分けて描く。
/// 段ごとに書体と色を変え、何が名前で何が属性かを読み分けられるようにする (https://github.com/bannzai/snapmon/issues/123 )。
/// バトルの技のボタンと、モンスターのカードの覚えている技の行で使う。地はカードの生成りの白を前提にする。
class MoveSummary extends StatelessWidget {
  /// 技の 3 段の表示を作る。
  const MoveSummary({
    super.key,
    required this.move,
    required this.remainingPowerPoints,
    required this.typeMultiplier,
    required this.definitions,
  });

  /// 描く技。
  final Move move;

  /// 残りの PP。バトルの外 (カードの覚えている技) では null で、その時は最大の PP だけを出す。
  final int? remainingPowerPoints;

  /// 今の相手の場のモンスターへの相性の倍率。属性の札の横に「×2」のように出す
  /// (効果が抜群か今ひとつかを技を選ぶ前に分かるようにする。https://github.com/bannzai/snapmon/issues/241 )。
  /// バトルの外と相性が効かない技 (補助技・一撃必殺) は null で、出さない。
  final double? typeMultiplier;

  /// 技の属性の名前を引く定義。
  final MasterData definitions;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(move.displayName, style: SnapmonTextStyles.moveName),
      const SizedBox(height: 4),
      // 2 列の技のボタンの幅では札と 2 つの数値が 1 行に収まらないことがあるため、収まらない分は次の行に回す
      Wrap(
        spacing: 8,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 属性の札と相性の倍率は「炎 ×2」と 1 まとまりで読ませるため、Wrap の 1 つの子にして別の行に分けない
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElementTypeTag(
                elementTypeId: move.elementTypeId,
                definitions: definitions,
              ),
              // 等倍は出さない (ログの「こうかは ばつぐんだ」「いまひとつ」と同じく、倍率が変わる時だけ知らせる。全部の技に出すと技の枠が埋まるため)
              if (typeMultiplier case final typeMultiplier?
                  when typeMultiplier != 1) ...[
                const SizedBox(width: 4),
                _TypeMultiplierTag(typeMultiplier: typeMultiplier),
              ],
            ],
          ),
          _MoveStatValue(label: context.l10n.movePower, value: '${move.power}'),
          _MoveStatValue(
            label: context.l10n.movePowerPoints,
            value: switch (remainingPowerPoints) {
              final remainingPowerPoints? =>
                '$remainingPowerPoints/${move.powerPoints}',
              null => '${move.powerPoints}',
            },
          ),
          // 外れることがある技と先制の技だけに印を出す (ほとんどの技は命中 100・先制なしで、全部に出すと技の枠が埋まるため)
          if (move.accuracy < defaultMoveAccuracyPercent)
            Text(
              context.l10n.moveAccuracy(move.accuracy),
              style: SnapmonTextStyles.small.copyWith(
                fontWeight: FontWeight.w400,
                color: SnapmonColors.textOnCardMuted,
              ),
            ),
          if (move.priority > 0)
            Text(
              context.l10n.movePriority,
              style: SnapmonTextStyles.small.copyWith(
                fontWeight: FontWeight.w400,
                color: SnapmonColors.textOnCardMuted,
              ),
            ),
        ],
      ),
      if (move.specialEffect case final specialEffect?) ...[
        const SizedBox(height: 4),
        Text(
          specialEffect.summary,
          style: SnapmonTextStyles.small.copyWith(
            fontWeight: FontWeight.w400,
            color: SnapmonColors.textOnCardMuted,
          ),
        ),
      ],
    ],
  );
}

/// 相性の倍率の札。抜群 (1 より大きい) は暗い地に明るい色で目立たせ、今ひとつ (1 より小さい) は薄い地と薄い文字で控えめに描く。
class _TypeMultiplierTag extends StatelessWidget {
  const _TypeMultiplierTag({required this.typeMultiplier});

  /// 相性の倍率 (等倍以外)。
  final double typeMultiplier;

  @override
  Widget build(BuildContext context) {
    final isSuperEffective = typeMultiplier > 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isSuperEffective
            ? SnapmonColors.textOnCard
            : SnapmonColors.cardTrack,
        borderRadius: SnapmonRadii.tag,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          context.l10n.moveTypeMultiplier(
            // 相性の倍率は 0.5・2 の積 (0.25〜) のため、% の整数にしても桁は落ちない
            formatPowerPercent(powerPercent: (typeMultiplier * 100).round()),
          ),
          key: const Key('move-type-multiplier'),
          style: SnapmonTextStyles.small.copyWith(
            color: isSuperEffective
                ? SnapmonColors.accent
                : SnapmonColors.textOnCardMuted,
          ),
        ),
      ),
    );
  }
}

/// 技の数値 1 つ。小さく薄いラベルの後に太い数値を続ける。
class _MoveStatValue extends StatelessWidget {
  const _MoveStatValue({required this.label, required this.value});

  /// 数値の前に付けるラベル (威力・PP)。
  final String label;

  /// 数値の文字列。
  final String value;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$label ',
          style: SnapmonTextStyles.small.copyWith(
            fontWeight: FontWeight.w400,
            color: SnapmonColors.textOnCardMuted,
          ),
        ),
        TextSpan(
          text: value,
          style: SnapmonTextStyles.label.copyWith(
            color: SnapmonColors.textOnCard,
          ),
        ),
      ],
    ),
  );
}
