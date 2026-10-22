import 'package:flutter/material.dart';

import '../../domain/master/move.dart';
import '../../domain/monster/stat_calculation.dart';
import '../../sample/sample_data.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/monster_parts.dart';
import '../../widgets/square_icon_button.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';

/// 生まれた画面 (モックの Result.dc.html) を閉じた後に、呼び出し元にしてほしいこと。
enum ResultScreenAction {
  /// 図鑑のタブを開く。
  openDex,
}

/// 生まれた画面。生まれたばかりのモンスターと、図鑑から開いたモンスターのカードを出す。
class ResultScreen extends StatelessWidget {
  /// モンスターのカードの画面を作る。
  const ResultScreen({
    super.key,
    required this.monster,
    required this.sampleData,
    required this.dexStore,
    required this.isNewlyBorn,
  });

  /// カードに出すモンスター。
  final OwnedMonster monster;

  /// 見本データ (属性・技の定義を引く)。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 生まれたばかりか。true なら「もう 1 体撮る」を出し、false (図鑑から開いた) なら出さない。
  final bool isNewlyBorn;

  @override
  Widget build(BuildContext context) {
    final definition = monster.definition;
    final stats = calculateStats(
      baseStats: definition.baseStats,
      individualValues: definition.individualValues,
      level: monster.level,
      statCalculationVersion: definition.statCalculationVersion,
    );
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  SquareIconButton(
                    icon: Icons.chevron_left,
                    tooltip: '戻る',
                    onPressed: () => Navigator.of(context).pop(),
                    size: 44,
                  ),
                  Expanded(
                    child: Text(
                      isNewlyBorn ? 'あたらしい なかま' : '図鑑',
                      textAlign: TextAlign.center,
                      style: SnapmonTextStyles.label.copyWith(
                        color: SnapmonColors.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                children: [
                  DecoratedBox(
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
                                    Text(
                                      definition.name,
                                      style: SnapmonTextStyles.cardTitle,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Lv. ${monster.level}',
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
                                  for (final elementTypeId
                                      in definition.elementTypeIds)
                                    ElementTypeTag(
                                      elementTypeId: elementTypeId,
                                      definitions: sampleData.definitions,
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: _LabeledPanel(
                                    label: '写真',
                                    child: const ColoredBox(
                                      color: SnapmonColors.surfaceRaised,
                                      child: Center(
                                        child: Icon(
                                          Icons.image_outlined,
                                          color: SnapmonColors.textMuted,
                                          size: 40,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: _LabeledPanel(
                                    label: 'モンスター',
                                    child: PlaceholderMonsterArt(
                                      definition: definition,
                                      backgroundColor: SnapmonColors.cardSubtle,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            definition.encyclopediaText,
                            style: SnapmonTextStyles.body.copyWith(
                              color: SnapmonColors.textOnCardBody,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // 名前と図鑑の文章が AI の生成であることの表示 (DIRECTION.md「必要な機能」の未成年向けの安全策)
                          Text(
                            '名前と図鑑の文章は AI が作りました',
                            style: SnapmonTextStyles.small.copyWith(
                              color: SnapmonColors.textOnCardMuted,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              for (final (label, value) in [
                                ('HP', stats.hitPoints),
                                ('攻撃', stats.attack),
                                ('防御', stats.defense),
                                ('素早さ', stats.speed),
                              ])
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    child: DecoratedBox(
                                      decoration: const BoxDecoration(
                                        color: SnapmonColors.cardSubtle,
                                        borderRadius: SnapmonRadii.button,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 8,
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              label,
                                              style: SnapmonTextStyles.small
                                                  .copyWith(
                                                    color: SnapmonColors
                                                        .textOnCardMuted,
                                                  ),
                                            ),
                                            Text(
                                              '$value',
                                              style:
                                                  SnapmonTextStyles.statValue,
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
                            'おぼえている技',
                            style: SnapmonTextStyles.caption.copyWith(
                              color: SnapmonColors.textOnCardMuted,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final learnsetEntry in definition.learnset)
                                if (learnsetEntry.unlockLevel <= monster.level)
                                  _MoveChip(
                                    move: sampleData.definitions.moveById(
                                      moveId: learnsetEntry.moveId,
                                    ),
                                  ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                children: [
                  ListenableBuilder(
                    listenable: dexStore,
                    builder: (context, _) {
                      final isInParty = dexStore.isInParty(
                        monsterId: definition.id,
                      );
                      // 手持ちにいるモンスターはここから外せるようにし、満員でも入れ替えられるようにする
                      return FilledButton(
                        onPressed: isInParty
                            ? () => dexStore.removeFromParty(
                                monsterId: definition.id,
                              )
                            : !dexStore.hasPartyVacancy
                            ? null
                            : () {
                                dexStore.addToParty(monsterId: definition.id);
                                Navigator.of(
                                  context,
                                ).pop(ResultScreenAction.openDex);
                              },
                        child: Text(
                          isInParty
                              ? '手持ちから外す'
                              : dexStore.hasPartyVacancy
                              ? '手持ちに入れる'
                              : '手持ちがいっぱいです 外してから入れる',
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (isNewlyBorn) ...[
                        Expanded(
                          child: _SecondaryButton(
                            label: 'もう 1 体撮る',
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: _SecondaryButton(
                          label: 'カードを共有',
                          // 共有は #18 で実装する
                          onPressed: () =>
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('共有は準備中です')),
                              ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 左下にラベルを重ねた、角丸の絵の枠。
class _LabeledPanel extends StatelessWidget {
  const _LabeledPanel({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: SnapmonRadii.card,
    child: Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          left: 8,
          bottom: 8,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: SnapmonColors.scrim,
              borderRadius: SnapmonRadii.tag,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                label,
                style: SnapmonTextStyles.small.copyWith(
                  color: SnapmonColors.textOnBackground,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 覚えている技の札。
class _MoveChip extends StatelessWidget {
  const _MoveChip({required this.move});

  final Move move;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: SnapmonColors.textOnCard,
      borderRadius: SnapmonRadii.tag,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(
        '${move.displayName} PP ${move.powerPoints}',
        style: SnapmonTextStyles.caption.copyWith(
          color: SnapmonColors.textOnBackground,
        ),
      ),
    ),
  );
}

/// 地の色の副ボタン。
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: SnapmonColors.surface,
    borderRadius: SnapmonRadii.card,
    child: InkWell(
      borderRadius: SnapmonRadii.card,
      onTap: onPressed,
      child: SizedBox(
        height: 48,
        child: Center(child: Text(label, style: SnapmonTextStyles.label)),
      ),
    ),
  );
}
