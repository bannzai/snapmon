import 'package:flutter/material.dart';

import '../../common_ui/scene_route.dart';
import '../../domain/battle/battle_state.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../monster_ui/monster_parts.dart';
import '../../common_ui/square_icon_button.dart';
import '../home/home_shell.dart';
import '../reference/reference_screen.dart';
import '../result/result_screen.dart';
import '../share/card_sharer.dart';
import 'dex_store.dart';
import 'owned_monster.dart';

/// 図鑑の画面 (モックの Dex.dc.html)。上に手持ち、下に図鑑のすべてのモンスターを 3 列で並べる。
/// 見出しと手持ちの間に、属性の相性表と技の一覧の画面 ([ReferenceScreen]) を開く入口を置く (モックに無い入口で、置き場所は agent が決めた)。
/// 撮る画面を開くボタンは見出しの右ではなく、画面の下に横長の「追加する」として置く (#246)。
class DexScreen extends StatelessWidget {
  /// 図鑑の画面を作る。
  const DexScreen({
    super.key,
    required this.dexStore,
    required this.onSelectScene,
    required this.onOpenSettings,
    required this.cardSharer,
  });

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// ホームの画面のシーンを切り替える (「追加する」で撮るを開く)。
  final void Function({required HomeScene scene}) onSelectScene;

  /// 設定画面を開く。
  final VoidCallback onOpenSettings;

  /// 図鑑のカードの共有に使う関数の組。
  final CardSharer cardSharer;

  Future<void> _openMonster({
    required BuildContext context,
    required OwnedMonster monster,
  }) => Navigator.of(context).push(
    sceneRoute<ResultScreenAction>(
      builder: (context) => ResultScreen(
        monster: monster,
        dexStore: dexStore,
        origin: ResultScreenOrigin.dex,
        cardSharer: cardSharer,
      ),
    ),
  );

  /// 手持ちに入っていない図鑑のモンスターから 1 体を選んでもらい、手持ちに入れる。保存に失敗したらエラーをそのまま出す。
  Future<void> _addToParty({required BuildContext context}) async {
    final candidates = [
      for (final monster in dexStore.monsters)
        if (!dexStore.isInParty(monsterID: monster.definition.id)) monster,
    ];
    final incomingMonster = await showDialog<OwnedMonster>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.dexAddToPartyTitle),
        children: [
          if (candidates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                context.l10n.dexNoPartyCandidates,
                style: SnapmonTextStyles.body,
              ),
            ),
          for (final candidate in candidates)
            SimpleDialogOption(
              key: Key('dex-add-to-party-${candidate.definition.id}'),
              onPressed: () => Navigator.of(context).pop(candidate),
              child: Text(
                '${candidate.definition.name}  ${context.l10n.commonLevel(candidate.level)}',
              ),
            ),
        ],
      ),
    );
    if (incomingMonster == null || !context.mounted) {
      return;
    }
    // 保存を待つ間に図鑑の画面が閉じても失敗を出せるよう、await の前に ScaffoldMessenger を取っておく
    final messenger = ScaffoldMessenger.of(context);
    try {
      await dexStore.addToParty(monsterID: incomingMonster.definition.id);
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListenableBuilder(
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
                          Text(
                            context.l10n.tabDex,
                            style: SnapmonTextStyles.screenTitle,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.l10n.dexSummary(
                              dexStore.monsters.length,
                              party.length,
                            ),
                            style: SnapmonTextStyles.caption,
                          ),
                          if (dexStore.serverError != null) ...[
                            Text(
                              dexStore.serverError.toString(),
                              style: SnapmonTextStyles.small.copyWith(
                                color: SnapmonColors.hitPointsLoss,
                              ),
                            ),
                            TextButton(
                              onPressed: () =>
                                  dexStore.refreshDefinitions().catchError(
                                    (Object error) => dexStore
                                        .reportServerError(error: error),
                                  ),
                              child: Text(context.l10n.dexReload),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SquareIconButton(
                      icon: Icons.settings_outlined,
                      tooltip: context.l10n.settingsTitle,
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
                child: Material(
                  color: SnapmonColors.surface,
                  borderRadius: SnapmonRadii.button,
                  child: InkWell(
                    key: const Key('dex-open-reference'),
                    borderRadius: SnapmonRadii.button,
                    onTap: () => Navigator.of(context).push(
                      sceneRoute<void>(
                        builder: (context) =>
                            ReferenceScreen(dexStore: dexStore),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.menu_book_outlined,
                            size: 18,
                            color: SnapmonColors.accent,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              context.l10n.referenceOpen,
                              style: SnapmonTextStyles.label,
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: SnapmonColors.textMuted,
                          ),
                        ],
                      ),
                    ),
                  ),
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
                      context.l10n.dexParty,
                      style: SnapmonTextStyles.caption.copyWith(
                        color: SnapmonColors.accent,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // 枠の幅を揃えるため、間隔は枠の外に置く (下の「すべて」の 3 列と同じ幅になる)
                        for (
                          var index = 0;
                          index < maximumPartySize;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: 10),
                          Expanded(
                            child: AspectRatio(
                              aspectRatio: _monsterTileAspectRatio,
                              child: index < party.length
                                  ? _MonsterTile(
                                      monster: party[index],
                                      isInParty: true,
                                      onTap: () => _openMonster(
                                        context: context,
                                        monster: party[index],
                                      ),
                                    )
                                  : _EmptyPartySlot(
                                      // 手持ちの ID が図鑑より先に届いた間は、枠が空いて見えても手持ちに空きが無い
                                      onTap:
                                          dexStore.isSavingParty ||
                                              !dexStore.hasPartyVacancy
                                          ? null
                                          : () => _addToParty(context: context),
                                    ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  context.l10n.dexAll,
                  style: SnapmonTextStyles.caption,
                ),
              ),
            ),
            if (dexStore.monsters.isEmpty)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    context.l10n.dexEmpty,
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
                  childAspectRatio: _monsterTileAspectRatio,
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
            // 最後の行が下の「追加する」ボタンに隠れないよう、ボタンの高さと centerFloat がボタンの下に空ける余白の分だけ下に余白を足す
            const SliverPadding(
              padding: EdgeInsets.only(
                bottom: _addMonsterButtonHeight + kFloatingActionButtonMargin,
              ),
            ),
          ],
        );
      },
    ),
    floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    floatingActionButton: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SizedBox(
        width: double.infinity,
        height: _addMonsterButtonHeight,
        child: FloatingActionButton.extended(
          key: const Key('dex-add-monster'),
          backgroundColor: SnapmonColors.accent,
          foregroundColor: SnapmonColors.textOnCard,
          shape: const RoundedRectangleBorder(
            borderRadius: SnapmonRadii.button,
          ),
          onPressed: () => onSelectScene(scene: HomeScene.capture),
          icon: const Icon(Icons.photo_camera_outlined),
          label: Text(
            context.l10n.dexAddMonster,
            // label の文字色 (地の色の上の白) がボタンの foregroundColor を上書きするため、黄緑の上の濃い色を明示する
            style: SnapmonTextStyles.label.copyWith(
              color: SnapmonColors.textOnCard,
            ),
          ),
        ),
      ),
    ),
  );
}

/// 図鑑の画面の下の「追加する」ボタンの高さ。モックのボタンの文字 14px と上下の余白を、指で押しやすい 44 以上に広げた値。
const double _addMonsterButtonHeight = 52;

/// 図鑑のカードと手持ちの枠の幅 / 高さ。モック (Dex.dc.html) の 3 列のカードの比率から取った。
const double _monsterTileAspectRatio = 0.72;

/// 図鑑の 1 体のカード。手持ちと「すべて」は同じ地の色のカードで描き、手持ちにだけ黄緑の縁を付ける (#246)。
/// 高さは呼び出し元の比率で決まり、絵は文字の残りの高さに収める (端末の文字を大きくしてもはみ出さないため)。
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
  Widget build(BuildContext context) => Material(
    color: SnapmonColors.surface,
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
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: MonsterArt(
                    monster: monster,
                    backgroundColor: SnapmonColors.artBackground,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              monster.definition.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SnapmonTextStyles.caption.copyWith(
                color: SnapmonColors.textOnBackground,
              ),
            ),
            Text(
              context.l10n.commonLevel(monster.level),
              style: SnapmonTextStyles.small.copyWith(
                color: SnapmonColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 手持ちの空いた枠。+ を出し、タップで手持ちに入れるモンスターを選ぶ。[onTap] が null の間 (手持ちの保存中・手持ちに空きが無い間) はタップを受け付けない。
class _EmptyPartySlot extends StatelessWidget {
  const _EmptyPartySlot({required this.onTap});

  /// 枠をタップした時の処理。null の間はタップを受け付けない。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    shape: const RoundedRectangleBorder(
      borderRadius: SnapmonRadii.card,
      side: BorderSide(color: SnapmonColors.surface, width: 2),
    ),
    child: InkWell(
      key: const Key('dex-empty-party-slot'),
      borderRadius: SnapmonRadii.card,
      onTap: onTap,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add, color: SnapmonColors.accent, size: 28),
            const SizedBox(height: 4),
            Text(context.l10n.dexEmptySlot, style: SnapmonTextStyles.small),
          ],
        ),
      ),
    ),
  );
}
