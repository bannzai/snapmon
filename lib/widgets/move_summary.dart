import 'package:flutter/material.dart';

import '../domain/battle/move_special_effect.dart';
import '../domain/master/master_data.dart';
import '../domain/master/move.dart';
import '../l10n/l10n.dart';
import '../theme/snapmon_colors.dart';
import '../theme/snapmon_radii.dart';
import '../theme/snapmon_text_styles.dart';
import 'monster_parts.dart';

/// 技の中身を 3 段で描く。1 段目は名前と、右に寄せた属性の札・今の相手への相性の札、2 段目は威力、3 段目は特殊効果の説明と右に寄せた PP。
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

  /// 今の相手の場のモンスターへの相性の倍率。属性の札の右に矢印と倍率の札で出す
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
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 名前は札に押されて切れないよう、札を除いた幅で折り返す (2 列の技のボタンの幅では長い名前が 1 行に収まらない)
          Expanded(
            child: Text(move.displayName, style: SnapmonTextStyles.moveName),
          ),
          const SizedBox(width: 8),
          ElementTypeTag(
            elementTypeId: move.elementTypeId,
            definitions: definitions,
          ),
          // 等倍は出さない (ログの「こうかは ばつぐんだ」「いまひとつ」と同じく、倍率が変わる時だけ知らせる。全部の技に出すと技の枠が埋まるため)
          if (typeMultiplier case final typeMultiplier?
              when typeMultiplier != 1) ...[
            const SizedBox(width: 4),
            _TypeEffectivenessTag(typeMultiplier: typeMultiplier),
          ],
        ],
      ),
      const SizedBox(height: 4),
      Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '${context.l10n.movePower} ',
              style: SnapmonTextStyles.small.copyWith(
                fontWeight: FontWeight.w400,
                color: SnapmonColors.textOnCardMuted,
              ),
            ),
            TextSpan(
              text: '${move.power}',
              style: SnapmonTextStyles.label.copyWith(
                color: SnapmonColors.textOnCard,
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 4),
      Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (move.specialEffect case final specialEffect?)
            Expanded(
              child: Text(
                specialEffect.summary,
                style: SnapmonTextStyles.small.copyWith(
                  fontWeight: FontWeight.w400,
                  color: SnapmonColors.textOnCardMuted,
                ),
              ),
            )
          else
            const Spacer(),
          const SizedBox(width: 8),
          // PP は技を選ぶ判断に効くことが少ないため、威力より小さく薄くして右下に置く
          Text(
            '${context.l10n.movePowerPoints} ${switch (remainingPowerPoints) {
              final remainingPowerPoints? => '$remainingPowerPoints/${move.powerPoints}',
              null => '${move.powerPoints}',
            }}',
            style: SnapmonTextStyles.small.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: SnapmonColors.textMuted,
            ),
          ),
        ],
      ),
    ],
  );
}

/// 今の相手への相性の札。上下の矢印と倍率で、効果が抜群 (1 より大きい) か今ひとつ (1 より小さい) かを言葉を読まずに伝える
/// (https://github.com/bannzai/snapmon/issues/259 )。
/// 抜群は強調色の地に濃い文字で技の中でいちばん目を引かせ、今ひとつは薄い地と薄い文字で控えめに描く。
/// 「効果は抜群」「効果はいまひとつ」の言葉は読み上げの名前にだけ持つ。画面に出すと 2 列の技のボタンの幅に収まらず、
/// 使った後のログが同じ言葉を出して矢印の意味を教えるため。
class _TypeEffectivenessTag extends StatelessWidget {
  const _TypeEffectivenessTag({required this.typeMultiplier});

  /// 相性の倍率 (等倍以外)。
  final double typeMultiplier;

  @override
  Widget build(BuildContext context) {
    final isSuperEffective = typeMultiplier > 1;
    // 相性の倍率は 0.5・2 の積 (0.25〜) のため、% の整数にしても桁は落ちない
    final multiplierText = formatPowerPercent(
      powerPercent: (typeMultiplier * 100).round(),
    );
    final foreground = isSuperEffective
        ? SnapmonColors.textOnCard
        : SnapmonColors.textOnCardMuted;
    return Semantics(
      label: isSuperEffective
          ? context.l10n.moveTypeSuperEffective(multiplierText)
          : context.l10n.moveTypeNotVeryEffective(multiplierText),
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: isSuperEffective
                ? SnapmonColors.accent
                : SnapmonColors.cardTrack,
            borderRadius: SnapmonRadii.tag,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isSuperEffective
                      ? Icons.keyboard_double_arrow_up
                      : Icons.keyboard_double_arrow_down,
                  // 文字 (11) と同じ高さに見える大きさ。文字より大きいと札だけ背が高くなり、属性の札と揃わない
                  size: 12,
                  color: foreground,
                ),
                Text(
                  context.l10n.moveTypeMultiplier(multiplierText),
                  key: const Key('move-type-multiplier'),
                  style: SnapmonTextStyles.small.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
