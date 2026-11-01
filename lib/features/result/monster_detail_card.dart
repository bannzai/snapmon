import 'package:flutter/material.dart';

import '../../domain/battle/battle_engine.dart';
import '../../domain/master/master_data.dart';
import '../../domain/monster/stat_calculation.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/monster_parts.dart';
import '../../widgets/move_summary.dart';
import '../dex/owned_monster.dart';

/// モンスター 1 体のカード (名前・レベル・属性・絵・図鑑の文章・ステータス・覚えている技)。
/// 生まれた画面と、対戦相手の画面の相手のモンスターの詳細で使う。
class MonsterDetailCard extends StatelessWidget {
  /// モンスターのカードを作る。
  const MonsterDetailCard({
    super.key,
    required this.monster,
    required this.definitions,
  });

  /// カードに出すモンスター。ステータスと覚えている技は [OwnedMonster.level] で決める。
  final OwnedMonster monster;

  /// 属性・技を引く定義。
  final MasterData definitions;

  @override
  Widget build(BuildContext context) {
    final definition = monster.definition;
    final stats = calculateStats(
      baseStats: definition.baseStats,
      individualValues: definition.individualValues,
      level: monster.level,
      statCalculationVersion: definition.statCalculationVersion,
    );
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: SnapmonColors.card,
        borderRadius: SnapmonRadii.panel,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(definition.name, style: SnapmonTextStyles.cardTitle),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.commonLevel(monster.level),
                        style: SnapmonTextStyles.caption.copyWith(
                          color: SnapmonColors.textOnCardMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final elementTypeId in definition.elementTypeIds)
                      ElementTypeTag(
                        elementTypeId: elementTypeId,
                        definitions: definitions,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            // 元の写真は並べない。モンスターの絵は元の写真の crop の範囲か写真全体か OS で切り出した被写体で、
            // 並べると同じ絵が 2 枚になるため (DIRECTION.md 2026-10-31 の #120 の行)
            // 横長の画面 (Web のデスクトップ) で絵が画面の高さを超えて名前と能力値が見えなくならないよう、
            // 一辺を画面の高さの半分までにする
            Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).height / 2,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: SnapmonRadii.card,
                    child: MonsterArt(
                      monster: monster,
                      backgroundColor: SnapmonColors.cardSubtle,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              definition.encyclopediaText,
              style: SnapmonTextStyles.body.copyWith(
                color: SnapmonColors.textOnCardBody,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final (label, value) in [
                  (context.l10n.statHitPoints, stats.hitPoints),
                  (context.l10n.statAttack, stats.attack),
                  (context.l10n.statDefense, stats.defense),
                  (context.l10n.statSpeed, stats.speed),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          color: SnapmonColors.cardSubtle,
                          borderRadius: SnapmonRadii.button,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              Text(
                                label,
                                style: SnapmonTextStyles.small.copyWith(
                                  color: SnapmonColors.textOnCardMuted,
                                ),
                              ),
                              Text(
                                '$value',
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
            const SizedBox(height: 14),
            Text(
              context.l10n.resultLearnedMoves,
              style: SnapmonTextStyles.caption.copyWith(
                color: SnapmonColors.textOnCardMuted,
              ),
            ),
            const SizedBox(height: 6),
            // バトルの技のボタンと同じ 3 段の構成で 1 技 1 行に並べる。地はステータスの枠と同じ色にし、属性の札の色を読めるようにする
            for (final learnsetEntry in equippedLearnsetEntries(
              learnset: definition.learnset,
              level: monster.level,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: SnapmonColors.cardSubtle,
                    borderRadius: SnapmonRadii.button,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: MoveSummary(
                        move: definitions.moveById(
                          moveId: learnsetEntry.moveId,
                        ),
                        remainingPowerPoints: null,
                        definitions: definitions,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
