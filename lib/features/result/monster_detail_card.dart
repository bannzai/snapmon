import 'package:flutter/material.dart';

import '../../domain/battle/battle_engine.dart';
import '../../domain/master/master_data.dart';
import '../../domain/master/move.dart';
import '../../domain/monster/monster_stats.dart';
import '../../domain/monster/stat_calculation.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../monster_ui/monster_parts.dart';
import '../../monster_ui/move_card.dart';
import '../dex/owned_monster.dart';
import '../reference/move_detail_screen.dart';

/// カードの絵の一辺。ステータスの 5 本の目盛り (ラベルの行と棒。各 29 ほど) を間隔 2 で隣に積んだ高さ (5 × 29 + 4 × 2) に揃え、
/// 絵とステータスを 1 段に収めて技を最初の画面に入れる (https://github.com/bannzai/snapmon/issues/216 )。
/// 命中を足した (#279) 時に、4 本の時の 128 から目盛り 1 本分を足した。
const double monsterDetailArtSize = 153;

/// モンスター 1 体のカード (名前・レベル・属性・絵・ステータス・図鑑の文章・覚えている技)。
/// 生まれた画面と、対戦相手の画面の相手のモンスターの詳細で使う。
/// 絵を左上に、ステータスを右に目盛りで並べ、技はバトルの技のボタンと同じ 2 列 × 2 行の枠に置く。
class MonsterDetailCard extends StatelessWidget {
  /// モンスターのカードを作る。
  const MonsterDetailCard({
    super.key,
    required this.monster,
    required this.definitions,
  });

  /// カードに出すモンスター。ステータスと覚えている技は [OwnedMonster.level] で決める。
  final OwnedMonster monster;

  /// 属性・技・ステータスの段階を引く定義。
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
    // バトルの技のボタンと同じ枠の数にし、技が無い枠は空の枠として描く
    final moveSlots = List<Move?>.generate(
      maximumEquippedMoveCount,
      (index) => null,
    );
    for (final (index, moveID) in equippedLearnsetEntries(
      learnset: definition.learnset,
      actionCardMoveIDs: monster.actionCardMoveIDs,
      level: monster.level,
    ).indexed) {
      moveSlots[index] = definitions.moveByID(moveID: moveID);
    }
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
                    for (final elementTypeID in definition.elementTypeIDs)
                      ElementTypeTag(
                        elementTypeID: elementTypeID,
                        definitions: definitions,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 元の写真は並べない。モンスターの絵は元の写真の crop の範囲か写真全体か OS で切り出した被写体で、
            // 並べると同じ絵が 2 枚になるため (DIRECTION.md 2026-10-31 の #120 の行)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(
                  dimension: monsterDetailArtSize,
                  child: ClipRRect(
                    borderRadius: SnapmonRadii.card,
                    child: MonsterArt(
                      monster: monster,
                      backgroundColor: SnapmonColors.cardSubtle,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 高さを絵に固定しない。端末の文字を大きくした時は目盛りが絵より高くなってよい
                // (固定すると RenderFlex がはみ出す)
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    // 標準の文字の大きさで 5 本の目盛りが絵の高さ (monsterDetailArtSize) に揃う間隔
                    spacing: 2,
                    children: [
                      for (final (label, statKind) in [
                        (context.l10n.statHitPoints, StatKind.hitPoints),
                        (context.l10n.statAttack, StatKind.attack),
                        (context.l10n.statDefense, StatKind.defense),
                        (context.l10n.statSpeed, StatKind.speed),
                        (context.l10n.statAccuracy, StatKind.accuracy),
                      ])
                        _StatGauge(
                          key: Key('stat-gauge-${statKind.name}'),
                          label: label,
                          value: stats.valueOf(statKind: statKind),
                          ratio: statStrengthRatio(
                            statKind: statKind,
                            baseStats: definition.baseStats,
                            individualValues: definition.individualValues,
                            master: definitions,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              definition.encyclopediaText,
              style: SnapmonTextStyles.body.copyWith(
                color: SnapmonColors.textOnCardBody,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.resultLearnedMoves,
              style: SnapmonTextStyles.caption.copyWith(
                color: SnapmonColors.textOnCardMuted,
              ),
            ),
            const SizedBox(height: 6),
            // バトルの技のボタンと同じ 2 列に並べ、同じ行の 2 つは高さを揃える。地はステータスの枠と同じ色にし、
            // 属性の札の色を読めるようにする。枠をタップすると技の詳細 ([openMoveDetail]) を開く
            for (var rowStart = 0; rowStart < moveSlots.length; rowStart += 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (column, move)
                          in moveSlots.skip(rowStart).take(2).indexed) ...[
                        if (column > 0) const SizedBox(width: 6),
                        Expanded(
                          child: _MoveSlot(
                            move: move,
                            definitions: definitions,
                            slotIndex: rowStart + column,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ステータス 1 つの目盛り。ラベルと実際の値の行の下に、取り得る最大に対する割合 ([statStrengthRatio]) の棒を描く。
class _StatGauge extends StatelessWidget {
  const _StatGauge({
    super.key,
    required this.label,
    required this.value,
    required this.ratio,
  });

  /// ステータスの名前。
  final String label;

  /// 今のレベルの実際の値。
  final int value;

  /// 棒の長さ (0 以上 1 以下)。
  final double ratio;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: SnapmonTextStyles.small.copyWith(
                color: SnapmonColors.textOnCardMuted,
              ),
            ),
          ),
          Text(
            '$value',
            style: SnapmonTextStyles.statValue.copyWith(fontSize: 14),
          ),
        ],
      ),
      const SizedBox(height: 3),
      ClipRRect(
        borderRadius: SnapmonRadii.tag,
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 6,
          color: SnapmonColors.accent,
          backgroundColor: SnapmonColors.cardTrack,
        ),
      ),
    ],
  );
}

/// 覚えている技の枠 1 つ。技が無い枠 ([move] が null) はバトルの技のボタンと同じく「—」の空の枠として描く。
class _MoveSlot extends StatelessWidget {
  const _MoveSlot({
    required this.move,
    required this.definitions,
    required this.slotIndex,
  });

  /// 描く技。無い枠は null。
  final Move? move;

  /// 技の属性の名前を引く定義。
  final MasterData definitions;

  /// 枠の位置 (0 始まり)。空の枠の key に使う。
  final int slotIndex;

  @override
  Widget build(BuildContext context) {
    final move = this.move;
    return Material(
      color: SnapmonColors.cardSubtle,
      borderRadius: SnapmonRadii.button,
      child: InkWell(
        key: Key(
          move == null ? 'move-chip-empty-$slotIndex' : 'move-chip-${move.id}',
        ),
        borderRadius: SnapmonRadii.button,
        onTap: move == null
            ? null
            : () => openMoveDetail(
                context: context,
                move: move,
                definitions: definitions,
              ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: move == null
              ? Center(
                  child: Text(
                    '—',
                    style: SnapmonTextStyles.caption.copyWith(
                      color: SnapmonColors.textOnCardMuted,
                    ),
                  ),
                )
              : Align(
                  alignment: Alignment.centerLeft,
                  child: MoveCard(
                    move: move,
                    remainingPowerPoints: null,
                    typeMultiplier: null,
                    definitions: definitions,
                  ),
                ),
        ),
      ),
    );
  }
}
