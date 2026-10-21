import 'package:flutter/material.dart';

import '../../domain/battle/battle_state.dart';
import '../../sample/sample_data.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/monster_parts.dart';
import '../../widgets/square_icon_button.dart';
import '../home/home_shell.dart';
import '../result/result_screen.dart';
import 'dex_store.dart';
import 'owned_monster.dart';

/// 図鑑の画面 (モックの Dex.dc.html)。上に手持ち、下に図鑑のすべてのモンスターを 3 列で並べる。
class DexScreen extends StatelessWidget {
  /// 図鑑の画面を作る。
  const DexScreen({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.onSelectTab,
    required this.onOpenSettings,
  });

  /// 見本データ (属性・技の定義を引く)。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 下タブを切り替える。
  final void Function({required HomeTab tab}) onSelectTab;

  /// 設定画面を開く。
  final VoidCallback onOpenSettings;

  Future<void> _openMonster({
    required BuildContext context,
    required OwnedMonster monster,
  }) => Navigator.of(context).push(
    MaterialPageRoute<ResultScreenAction>(
      builder: (context) => ResultScreen(
        monster: monster,
        sampleData: sampleData,
        dexStore: dexStore,
        isNewlyBorn: false,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: dexStore,
    builder: (context, _) {
      final party = dexStore.party;
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('図鑑', style: SnapmonTextStyles.screenTitle),
                        const SizedBox(height: 2),
                        Text(
                          '${dexStore.monsters.length} 体 · 手持ち ${party.length} 体',
                          style: SnapmonTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      shape: const RoundedRectangleBorder(
                        borderRadius: SnapmonRadii.button,
                      ),
                      textStyle: SnapmonTextStyles.label,
                    ),
                    onPressed: () => onSelectTab(tab: HomeTab.capture),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('撮る'),
                  ),
                  const SizedBox(width: 8),
                  SquareIconButton(
                    icon: Icons.settings_outlined,
                    tooltip: '設定',
                    onPressed: onOpenSettings,
                    size: 44,
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '手持ち',
                    style: SnapmonTextStyles.caption.copyWith(
                      color: SnapmonColors.accent,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (var index = 0; index < maximumPartySize; index++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: index == 0 ? 0 : 5,
                              right: index == maximumPartySize - 1 ? 0 : 5,
                            ),
                            child: index < party.length
                                ? _MonsterTile(
                                    monster: party[index],
                                    isInParty: true,
                                    onTap: () => _openMonster(
                                      context: context,
                                      monster: party[index],
                                    ),
                                  )
                                : const _EmptyPartySlot(),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text('すべて', style: SnapmonTextStyles.caption),
            ),
          ),
          if (dexStore.monsters.isEmpty)
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 24, 20, 24),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'まだモンスターがいません\n撮る画面から身の回りの物を撮ってみよう',
                  textAlign: TextAlign.center,
                  style: SnapmonTextStyles.body,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverGrid.count(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.72,
                children: [
                  for (final monster in dexStore.monsters)
                    _MonsterTile(
                      monster: monster,
                      isInParty: false,
                      onTap: () =>
                          _openMonster(context: context, monster: monster),
                    ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

/// 図鑑の 1 体のカード。手持ちは生成りのカードに黄緑の縁、それ以外は地の色のカードで描く。
class _MonsterTile extends StatelessWidget {
  const _MonsterTile({
    required this.monster,
    required this.isInParty,
    required this.onTap,
  });

  final OwnedMonster monster;
  final bool isInParty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = isInParty
        ? SnapmonColors.textOnCard
        : SnapmonColors.textOnBackground;
    return Material(
      color: isInParty ? SnapmonColors.card : SnapmonColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: SnapmonRadii.card,
        side: isInParty
            ? const BorderSide(color: SnapmonColors.accent, width: 3)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: SnapmonRadii.card,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: PlaceholderMonsterArt(
                  definition: monster.definition,
                  backgroundColor: isInParty
                      ? SnapmonColors.cardSubtle
                      : SnapmonColors.artBackground,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                monster.definition.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SnapmonTextStyles.caption.copyWith(color: textColor),
              ),
              Text(
                'Lv. ${monster.level}',
                style: SnapmonTextStyles.small.copyWith(
                  color: isInParty
                      ? SnapmonColors.textOnCardMuted
                      : SnapmonColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 手持ちの空いた枠。
class _EmptyPartySlot extends StatelessWidget {
  const _EmptyPartySlot();

  @override
  Widget build(BuildContext context) => AspectRatio(
    aspectRatio: 0.72,
    child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: SnapmonRadii.card,
        border: Border.all(color: SnapmonColors.surface, width: 2),
      ),
      child: Center(child: Text('あき', style: SnapmonTextStyles.small)),
    ),
  );
}
