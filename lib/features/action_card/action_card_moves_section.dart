import 'package:flutter/material.dart';

import '../../domain/battle/battle_engine.dart';
import '../../domain/master/move.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import 'action_card_screen.dart';
import 'action_card_store.dart';

/// 図鑑の詳細の「Action Card の技」の節。[monster] に覚えさせた技と「忘れさせる」、買い切った技から選んで覚えさせる操作、
/// Action Card の画面の入口を出す。Action Card の画面の入口を出さない時 (隠している間で買い切った技も無い) と、
/// [ActionCardScope] が無い時は、覚えさせた技がある時だけ節を出す (覚えさせた技を忘れさせられなくしないため)。
class ActionCardMovesSection extends StatefulWidget {
  /// 節を作る。
  const ActionCardMovesSection({
    super.key,
    required this.monster,
    required this.dexStore,
  });

  /// 覚えさせる・忘れさせる対象のモンスター (図鑑の最新の値)。
  final OwnedMonster monster;

  /// 結果を図鑑に反映する先 (技の定義も引く)。
  final DexStore dexStore;

  @override
  State<ActionCardMovesSection> createState() => _ActionCardMovesSectionState();
}

/// [ActionCardMovesSection] の覚えさせる・忘れさせるの途中かどうか。
class _ActionCardMovesSectionState extends State<ActionCardMovesSection> {
  /// 覚えさせる・忘れさせるの途中か。途中は他の操作を押せなくする。
  bool _isUpdating = false;

  /// [update] (teach か forget) を呼び、返った一覧を Firestore から届く前に図鑑へ出す。失敗したらエラーをそのまま出す。
  Future<void> _updateActionCardMoveIds({
    required Future<List<String>> Function() update,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isUpdating = true);
    try {
      widget.dexStore.updateActionCardMoveIds(
        monsterId: widget.monster.definition.id,
        actionCardMoveIds: await update(),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  /// 覚えさせる技を [candidateMoves] から選んでもらう。各技に、覚えさせると技の枠から外れる技を出す
  /// (枠は自動で入れ替わり、選ぶ画面が無いため。#247 の勝敗の画面と同じ文言)。選ばなければ null。
  Future<Move?> _chooseMoveToTeach({required List<Move> candidateMoves}) {
    final monster = widget.monster;
    final definitions = widget.dexStore.definitions;
    final currentMoveIds = equippedMoveIds(
      learnset: monster.definition.learnset,
      actionCardMoveIds: monster.actionCardMoveIds,
      level: monster.level,
    );
    return showModalBottomSheet<Move>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              context.l10n.actionCardTeachTitle(monster.definition.name),
              textAlign: TextAlign.center,
              style: SnapmonTextStyles.screenTitle,
            ),
            const SizedBox(height: 12),
            for (final move in candidateMoves)
              ListTile(
                key: Key('action-card-teach-${move.id}'),
                title: Text(move.displayName),
                subtitle: Text(
                  switch (equippedMoveChanges(
                    previousMoveIds: currentMoveIds,
                    newMoveIds: equippedMoveIds(
                      learnset: monster.definition.learnset,
                      actionCardMoveIds: [
                        ...monster.actionCardMoveIds,
                        move.id,
                      ],
                      level: monster.level,
                    ),
                  ).forgottenMoveIds) {
                    [] => context.l10n.actionCardTeachNoForgotten,
                    final forgottenMoveIds => [
                      for (final moveId in forgottenMoveIds)
                        context.l10n.battleForgotMove(
                          definitions.moveById(moveId: moveId).displayName,
                        ),
                    ].join('\n'),
                  },
                ),
                onTap: () => Navigator.of(context).pop(move),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ActionCardScope.maybeOf(context);
    final monster = widget.monster;
    final definitions = widget.dexStore.definitions;
    final movesById = {for (final move in definitions.moves) move.id: move};
    final isEntryVisible = store?.isScreenEntryVisible ?? false;
    if (!isEntryVisible && monster.actionCardMoveIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final candidateMoves = [
      for (final moveId in store?.ownedMoveIds ?? const <String>[])
        if (!monster.actionCardMoveIds.contains(moveId)) ?movesById[moveId],
    ];
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: SnapmonColors.card,
          borderRadius: SnapmonRadii.panel,
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.actionCardMovesHeading,
                style: SnapmonTextStyles.caption.copyWith(
                  color: SnapmonColors.textOnCardMuted,
                ),
              ),
              const SizedBox(height: 6),
              if (monster.actionCardMoveIds.isEmpty)
                Text(
                  l10n.actionCardTaughtNone,
                  style: SnapmonTextStyles.body.copyWith(
                    color: SnapmonColors.textOnCardBody,
                  ),
                ),
              for (final moveId in monster.actionCardMoveIds)
                Row(
                  key: Key('action-card-taught-$moveId'),
                  children: [
                    Expanded(
                      child: Text(
                        movesById[moveId]?.displayName ?? moveId,
                        style: SnapmonTextStyles.body.copyWith(
                          color: SnapmonColors.textOnCard,
                        ),
                      ),
                    ),
                    TextButton(
                      key: Key('action-card-forget-$moveId'),
                      onPressed: _isUpdating || store == null
                          ? null
                          : () => _updateActionCardMoveIds(
                              update: () => store.client.forgetActionCardMove(
                                monsterId: monster.definition.id,
                                moveId: moveId,
                              ),
                            ),
                      child: Text(l10n.actionCardForget),
                    ),
                  ],
                ),
              if (store != null && candidateMoves.isNotEmpty) ...[
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('action-card-teach'),
                  onPressed: _isUpdating
                      ? null
                      : () async {
                          final move = await _chooseMoveToTeach(
                            candidateMoves: candidateMoves,
                          );
                          if (move == null || !mounted) {
                            return;
                          }
                          await _updateActionCardMoveIds(
                            update: () => store.client.teachActionCardMove(
                              monsterId: monster.definition.id,
                              moveId: move.id,
                            ),
                          );
                        },
                  child: Text(l10n.actionCardTeach),
                ),
              ],
              if (isEntryVisible) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('action-card-entry-dex'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (context) =>
                          ActionCardScreen(definitions: definitions),
                    ),
                  ),
                  icon: const Icon(Icons.style_outlined),
                  label: Text(l10n.actionCardTitle),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
