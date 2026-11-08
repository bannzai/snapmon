import 'package:flutter/material.dart';

import '../domain/master/master_data.dart';
import '../domain/master/move.dart';
import '../l10n/l10n.dart';
import '../theme/snapmon_colors.dart';
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
    required this.definitions,
  });

  /// 描く技。
  final Move move;

  /// 残りの PP。バトルの外 (カードの覚えている技) では null で、その時は最大の PP だけを出す。
  final int? remainingPowerPoints;

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
          ElementTypeTag(
            elementTypeId: move.elementTypeId,
            definitions: definitions,
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
