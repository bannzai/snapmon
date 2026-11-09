import 'package:flutter/material.dart';

import '../../domain/battle/move_expression.dart';
import '../../domain/battle/move_special_effect.dart';
import '../../domain/master/master_data.dart';
import '../../domain/master/move.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../monster_ui/monster_parts.dart';

/// [move] の詳細の画面を開く。技の一覧・バトルの技のボタンの長押し・モンスターのカードの技の札から開く。
/// [definitions] は属性の名前と相性を引く定義で、開いた画面の定義 (バトルならそのバトルの定義) を渡す。
Future<void> openMoveDetail({
  required BuildContext context,
  required Move move,
  required MasterData definitions,
}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (context) =>
        MoveDetailScreen(move: move, definitions: definitions),
  ),
);

/// 技 1 つの詳細の画面。属性・威力・PP・覚えるレベル・特殊効果 (種類と威力の倍率の式)・技の属性の相性を出す。
/// 技の根拠 (`rationale`) は保守のための値でユーザーに見せない (documents/game-rules.md「技の根拠」) ため出さない。
class MoveDetailScreen extends StatelessWidget {
  /// [move] の詳細の画面を作る。
  const MoveDetailScreen({
    super.key,
    required this.move,
    required this.definitions,
  });

  /// 詳細を出す技。
  final Move move;

  /// 属性の名前と相性を引く定義。
  final MasterData definitions;

  @override
  Widget build(BuildContext context) {
    final specialEffect = move.specialEffect;
    final multipliersByDefenderElementTypeId = {
      for (final elementType in definitions.elementTypes)
        elementType.id: definitions.typeMultiplier(
          attackerElementTypeId: move.elementTypeId,
          defenderElementTypeId: elementType.id,
        ),
    };
    return Scaffold(
      appBar: AppBar(title: Text(move.displayName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Row(
            children: [
              ElementTypeTag(
                elementTypeId: move.elementTypeId,
                definitions: definitions,
              ),
            ],
          ),
          const SizedBox(height: 14),
          // 4 つの枠の高さを揃える (ラベルが長い言語で 1 つだけ折り返しても枠の下端が揃うように)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (label, value) in [
                  (context.l10n.moveDetailPower, '${move.power}'),
                  (context.l10n.moveDetailPowerPoints, '${move.powerPoints}'),
                  (context.l10n.moveDetailAccuracy, '${move.accuracy}'),
                  (
                    context.l10n.moveDetailUnlockLevel,
                    // 覚える技の一覧の開放レベルはレベル帯の下限 (functions/src/generation/monster_stats.ts の buildLearnset)。
                    // 上限は生成時に選べる帯の端で、そのレベルで忘れるわけではないため出さない
                    context.l10n.moveDetailUnlockLevelValue(
                      move.learnableLevelMinimum,
                    ),
                  ),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: SnapmonColors.card,
                          borderRadius: SnapmonRadii.button,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 10,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                label,
                                textAlign: TextAlign.center,
                                style: SnapmonTextStyles.small.copyWith(
                                  color: SnapmonColors.textOnCardMuted,
                                ),
                              ),
                              Text(
                                value,
                                textAlign: TextAlign.center,
                                style: SnapmonTextStyles.statValue,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (move.priority > 0) ...[
            const SizedBox(height: 10),
            Text(
              '${context.l10n.moveDetailPriority}: ${context.l10n.moveDetailPriorityValue}',
              style: SnapmonTextStyles.body,
            ),
          ],
          const SizedBox(height: 20),
          _SectionTitle(title: context.l10n.moveDetailSpecialEffect),
          if (specialEffect == null)
            Text(
              context.l10n.moveDetailNoSpecialEffect,
              style: SnapmonTextStyles.body,
            )
          else ...[
            Text(specialEffect.summary, style: SnapmonTextStyles.label),
            const SizedBox(height: 2),
            Text(specialEffect.rule, style: SnapmonTextStyles.body),
            const SizedBox(height: 10),
            // 式の無い効果 (状態・フィールド・自爆・一撃・必中だけの技) は規則の説明だけで足り、空の枠を出さない
            if (!specialEffect.hasNoExpressionEffect)
              DecoratedBox(
                decoration: const BoxDecoration(
                  color: SnapmonColors.surface,
                  borderRadius: SnapmonRadii.button,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      if (specialEffect.power case final power?)
                        _FormulaSection(
                          formulaKey: const Key('move-special-effect-formula'),
                          label: context.l10n.moveDetailFormula,
                          source: power,
                          note: context.l10n.moveDetailFormulaNote,
                        ),
                      for (final MapEntry(key: statKind, value: source)
                          in specialEffect.selfStatChanges.entries)
                        _FormulaSection(
                          formulaKey: Key(
                            'move-special-effect-self-${statKind.name}',
                          ),
                          label: context.l10n.moveDetailSelfStatFormula(
                            statLabel(l10n: context.l10n, statKind: statKind),
                          ),
                          source: source,
                          note: context.l10n.moveDetailStatFormulaNote,
                        ),
                      for (final MapEntry(key: statKind, value: source)
                          in specialEffect.opponentStatChanges.entries)
                        _FormulaSection(
                          formulaKey: Key(
                            'move-special-effect-opponent-${statKind.name}',
                          ),
                          label: context.l10n.moveDetailOpponentStatFormula(
                            statLabel(l10n: context.l10n, statKind: statKind),
                          ),
                          source: source,
                          note: context.l10n.moveDetailStatFormulaNote,
                        ),
                      if (specialEffect.selfHitPointsRecovery
                          case final recovery?)
                        _FormulaSection(
                          formulaKey: const Key('move-special-effect-recovery'),
                          label: context.l10n.moveDetailRecoveryFormula,
                          source: recovery,
                          note: context.l10n.moveDetailRecoveryFormulaNote,
                        ),
                    ],
                  ),
                ),
              ),
          ],
          const SizedBox(height: 20),
          _SectionTitle(title: context.l10n.moveDetailEffectiveness),
          if (multipliersByDefenderElementTypeId.values.every(
            (multiplier) => multiplier == 1,
          ))
            Text(
              context.l10n.moveDetailNeutralEverywhere,
              style: SnapmonTextStyles.body,
            )
          else
            for (final (label, isIncluded) in [
              (
                context.l10n.moveDetailSuperEffective,
                (double multiplier) => multiplier > 1,
              ),
              (
                context.l10n.moveDetailNotVeryEffective,
                (double multiplier) => multiplier < 1,
              ),
            ])
              if (multipliersByDefenderElementTypeId.values.any(isIncluded))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: SnapmonTextStyles.small),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final MapEntry(
                                key: elementTypeId,
                                value: multiplier,
                              )
                              in multipliersByDefenderElementTypeId.entries)
                            if (isIncluded(multiplier))
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ElementTypeTag(
                                    elementTypeId: elementTypeId,
                                    definitions: definitions,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '× ${formatTypeMultiplier(multiplier: multiplier)}',
                                    style: SnapmonTextStyles.small.copyWith(
                                      color: SnapmonColors.textOnBackground,
                                    ),
                                  ),
                                ],
                              ),
                        ],
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}

/// 相性の倍率 [multiplier] (相性表の 0.5 / 1 / 2 のような値) を「0.5」「2」のような文字列にする。
/// 技の特殊効果の倍率と同じく整数の % から組み立てる ([formatPowerPercent]。端末で表示を食い違わせないため)。
String formatTypeMultiplier({required double multiplier}) =>
    formatPowerPercent(powerPercent: (multiplier * 100).round());

/// 特殊効果の出力 1 つ分の、見出し・式 (日本語にしたもの)・注記。
class _FormulaSection extends StatelessWidget {
  const _FormulaSection({
    required this.formulaKey,
    required this.label,
    required this.source,
    required this.note,
  });

  /// 式の文字列の Key (テストが出力ごとの式を見分けるため)。
  final Key formulaKey;

  /// 出力の見出し (例: 威力の倍率 (%))。
  final String label;

  /// master の式。
  final String source;

  /// 式の値の読み方の注記。
  final String note;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 4,
    children: [
      Text(
        label,
        style: SnapmonTextStyles.caption.copyWith(color: SnapmonColors.accent),
      ),
      Text(
        formatMoveExpression(source: source),
        key: formulaKey,
        style: SnapmonTextStyles.body,
      ),
      Text(note, style: SnapmonTextStyles.small),
    ],
  );
}

/// 詳細の画面の節の見出し。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  /// 見出しの文言。
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      title,
      style: SnapmonTextStyles.caption.copyWith(color: SnapmonColors.accent),
    ),
  );
}
