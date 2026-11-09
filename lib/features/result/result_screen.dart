import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../common_ui/square_icon_button.dart';
import '../action_card/action_card_moves_section.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../settings/settings_screen.dart';
import '../share/card_sharer.dart';
import '../share/share_card_button.dart';
import '../share/share_cards.dart';
import 'monster_detail_card.dart';

/// 生まれた画面 (モックの Result.dc.html) を閉じた後に、呼び出し元にしてほしいこと。
enum ResultScreenAction {
  /// 図鑑のシーンを開く。
  openDex,
}

/// 生まれた画面をどこから開いたか。
enum ResultScreenOrigin {
  /// 撮った写真から新しく生まれた。
  newlyBorn,

  /// 撮った写真の被写体が、もう図鑑にいた (同じ被写体・同じ写真の撮り直し)。
  alreadyInDex,

  /// 図鑑から開いた。
  dex,
}

/// 生まれた画面。生まれたばかりのモンスターと、図鑑から開いたモンスターのカードを出す。
class ResultScreen extends StatelessWidget {
  /// モンスターのカードの画面を作る。
  const ResultScreen({
    super.key,
    required this.monster,
    required this.dexStore,
    required this.origin,
    required this.cardSharer,
  });

  /// カードに出すモンスター。
  final OwnedMonster monster;

  /// 図鑑と手持ち (属性・技の定義も引く)。
  final DexStore dexStore;

  /// どこから開いたか。撮る画面から開いた時は「もう 1 体撮る」を出し、図鑑から開いた時は出さない。
  final ResultScreenOrigin origin;

  /// 図鑑のカードの共有に使う関数の組。
  final CardSharer cardSharer;

  /// 手持ちの変更 [change] を待ち、保存に失敗したらエラーをそのまま出す。成功したら true を返す。
  static Future<bool> _changeParty({
    required BuildContext context,
    required Future<void> Function() change,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await change();
      return true;
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
      return false;
    }
  }

  /// 手持ちが満員の時に [monster] と入れ替える手持ちを選んでもらい、入れ替えたら図鑑を開くよう閉じる。
  Future<void> _replacePartyMember({required BuildContext context}) async {
    final outgoingMonster = await showDialog<OwnedMonster>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.resultReplaceTitle(monster.definition.name)),
        children: [
          for (final partyMonster in dexStore.party)
            SimpleDialogOption(
              key: Key('replace-${partyMonster.definition.id}'),
              onPressed: () => Navigator.of(context).pop(partyMonster),
              child: Text(
                '${partyMonster.definition.name}  ${context.l10n.commonLevel(partyMonster.level)}',
              ),
            ),
        ],
      ),
    );
    if (outgoingMonster == null || !context.mounted) {
      return;
    }
    if (await _changeParty(
          context: context,
          change: () => dexStore.replacePartyMember(
            outgoingMonsterId: outgoingMonster.definition.id,
            incomingMonsterId: monster.definition.id,
          ),
        ) &&
        context.mounted) {
      Navigator.of(context).pop(ResultScreenAction.openDex);
    }
  }

  /// [monster] を手持ちに入れ、入れたら図鑑を開くよう閉じる。
  Future<void> _addToParty({required BuildContext context}) async {
    if (await _changeParty(
          context: context,
          change: () => dexStore.addToParty(monsterId: monster.definition.id),
        ) &&
        context.mounted) {
      Navigator.of(context).pop(ResultScreenAction.openDex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final definition = monster.definition;
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
                    // AppBar の戻るボタンと同じ文言 (Material の各言語の訳) にする
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).backButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    size: 44,
                  ),
                  Expanded(
                    child: Text(
                      switch (origin) {
                        ResultScreenOrigin.newlyBorn =>
                          context.l10n.resultNewlyBorn,
                        ResultScreenOrigin.alreadyInDex =>
                          context.l10n.generationAlreadyInDexTitle,
                        ResultScreenOrigin.dex => context.l10n.tabDex,
                      },
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
              // Action Card の技を覚えさせる・忘れさせると図鑑の値が変わるため、図鑑の最新の値で描く (図鑑にいなければ開いた時の値)
              child: ListenableBuilder(
                listenable: dexStore,
                builder: (context, _) {
                  final latestMonster =
                      dexStore.monsters
                          .where(
                            (dexMonster) =>
                                dexMonster.definition.id == definition.id,
                          )
                          .firstOrNull ??
                      monster;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    children: [
                      MonsterDetailCard(
                        monster: latestMonster,
                        definitions: dexStore.definitions,
                      ),
                      if (origin == ResultScreenOrigin.dex)
                        ActionCardMovesSection(
                          monster: latestMonster,
                          dexStore: dexStore,
                        ),
                    ],
                  );
                },
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
                      // 手持ちにいるモンスターはここから外せるようにし、満員の時は手持ちの 1 体と入れ替える。
                      // 保存の途中は押せなくする (DexStore は保存の途中の次の変更を受け付けないため)
                      return FilledButton(
                        onPressed: dexStore.isSavingParty
                            ? null
                            : isInParty
                            ? () => _changeParty(
                                context: context,
                                change: () => dexStore.removeFromParty(
                                  monsterId: definition.id,
                                ),
                              )
                            : dexStore.hasPartyVacancy
                            ? () => _addToParty(context: context)
                            : () => _replacePartyMember(context: context),
                        child: Text(
                          isInParty
                              ? context.l10n.resultRemoveFromParty
                              : dexStore.hasPartyVacancy
                              ? context.l10n.resultAddToParty
                              : context.l10n.resultReplaceInParty,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (origin != ResultScreenOrigin.dex) ...[
                        Expanded(
                          child: _SecondaryButton(
                            label: context.l10n.resultCaptureAnother,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: ShareCardButton(
                          cardSharer: cardSharer,
                          screen: switch (origin) {
                            ResultScreenOrigin.newlyBorn =>
                              ShareScreen.resultNewlyBorn,
                            ResultScreenOrigin.alreadyInDex =>
                              ShareScreen.resultAlreadyInDex,
                            ResultScreenOrigin.dex => ShareScreen.dexDetail,
                          },
                          artPaths: [?monster.artPath],
                          buildCard:
                              ({required format, required artImagesByPath}) =>
                                  MonsterShareCard(
                                    monster: monster,
                                    artImagesByPath: artImagesByPath,
                                    definitions: dexStore.definitions,
                                    format: format,
                                  ),
                          shareText: context.l10n.resultShareText(
                            definition.name,
                            landingPageUri.toString(),
                          ),
                          fileNamePrefix: 'snapmon-${definition.id}',
                          buttonBuilder: ({required onPressed}) =>
                              _SecondaryButton(
                                label: context.l10n.resultShareCard,
                                onPressed: onPressed,
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

/// 地の色の副ボタン。
class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, required this.onPressed});

  final String label;

  /// 押した時の処理。null の間は押せない。
  final VoidCallback? onPressed;

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
