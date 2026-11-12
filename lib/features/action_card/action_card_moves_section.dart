import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/battle/battle_engine.dart';
import '../../domain/master/move.dart';
import '../../common_ui/scene_route.dart';
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

  /// 定義の読み直しを頼んだ技 (`refreshDefinitionsForActionCardMoves`)。
  final Set<String> _requestedMoveIDs = {};

  /// 定義に無い技が届いたかを見ている [ActionCardStore]。
  ActionCardStore? _listenedActionCardStore;

  /// [_listenedActionCardStore] の買い切った技のうち定義に無い技があれば、定義を読み直す (覚えさせる候補に出すため)。
  void _refreshMissingDefinitions() {
    if (_listenedActionCardStore case final actionCardStore?) {
      unawaited(
        refreshDefinitionsForActionCardMoves(
          actionCardStore: actionCardStore,
          dexStore: widget.dexStore,
          requestedMoveIDs: _requestedMoveIDs,
        ),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final actionCardStore = ActionCardScope.maybeOf(context);
    if (!identical(actionCardStore, _listenedActionCardStore)) {
      _listenedActionCardStore?.removeListener(_refreshMissingDefinitions);
      _listenedActionCardStore = actionCardStore
        ?..addListener(_refreshMissingDefinitions);
      _refreshMissingDefinitions();
    }
    // package をまだ読めていないと Action Card の入口が出ないため、開いた時とストアの値が変わるたびに足りなければ読み込む
    // (読めた後と読み込みの途中は何もしないため、何度呼んでも読み込みは重ならない)
    actionCardStore?.refreshPackagesIfMissing();
  }

  @override
  void dispose() {
    _listenedActionCardStore?.removeListener(_refreshMissingDefinitions);
    super.dispose();
  }

  /// 図鑑の [monsterID] のモンスター (図鑑にいなければ null)。
  OwnedMonster? _dexMonster({required String monsterID}) => widget
      .dexStore
      .monsters
      .where((monster) => monster.definition.id == monsterID)
      .firstOrNull;

  /// [update] (teach か forget) を呼び、返った一覧を Firestore から届く前に図鑑へ出す。失敗したらエラーをそのまま出す。
  /// 待っている間に図鑑のそのモンスターが変わった (Firestore の新しい値が届いた) 時は、届いた値の方が新しいため上書きしない。
  /// 図鑑は値が変わるたびに新しい [OwnedMonster] を置くため、呼び出しの前と同じオブジェクトかで見分ける。
  Future<void> _updateActionCardMoveIDs({
    required Future<List<String>> Function() update,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final monsterID = widget.monster.definition.id;
    final monsterAtStart = _dexMonster(monsterID: monsterID);
    setState(() => _isUpdating = true);
    try {
      final actionCardMoveIDs = await update();
      if (identical(_dexMonster(monsterID: monsterID), monsterAtStart)) {
        widget.dexStore.updateActionCardMoveIDs(
          monsterID: monsterID,
          actionCardMoveIDs: actionCardMoveIDs,
        );
      }
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
                  _teachSubtitle(
                    context: context,
                    monster: monster,
                    move: move,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(move),
              ),
          ],
        ),
      ),
    );
  }

  /// [monster] に [move] を覚えさせる前に、技を選ぶ一覧の各技の下に出す説明を返す。覚えさせると技の枠から外れる技、
  /// 覚えさせた技が枠に入らない時 (技を選んである。#309) は「技を選ぶ」で枠に入れられること、どちらでもなければ入れ替わらないこと。
  String _teachSubtitle({
    required BuildContext context,
    required OwnedMonster monster,
    required Move move,
  }) {
    final newEquippedMoveIDs = equippedLearnsetEntries(
      learnset: monster.definition.learnset,
      actionCardMoveIDs: [...monster.actionCardMoveIDs, move.id],
      selectedMoveIDs: monster.selectedMoveIDs,
      level: monster.level,
    );
    return switch (equippedMoveChanges(
      previousMoveIDs: equippedLearnsetEntries(
        learnset: monster.definition.learnset,
        actionCardMoveIDs: monster.actionCardMoveIDs,
        selectedMoveIDs: monster.selectedMoveIDs,
        level: monster.level,
      ),
      newMoveIDs: newEquippedMoveIDs,
    ).forgottenMoveIDs) {
      [] when !newEquippedMoveIDs.contains(move.id) =>
        context.l10n.actionCardTeachNotEquipped,
      [] => context.l10n.actionCardTeachNoForgotten,
      final forgottenMoveIDs => [
        for (final moveID in forgottenMoveIDs)
          context.l10n.battleForgotMove(
            widget.dexStore.definitions.moveByID(moveID: moveID).displayName,
          ),
      ].join('\n'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = ActionCardScope.maybeOf(context);
    final monster = widget.monster;
    final definitions = widget.dexStore.definitions;
    final movesByID = {for (final move in definitions.moves) move.id: move};
    final isEntryVisible = store?.isScreenEntryVisible ?? false;
    if (!isEntryVisible && monster.actionCardMoveIDs.isEmpty) {
      return const SizedBox.shrink();
    }
    final candidateMoves = [
      for (final moveID in store?.ownedMoveIDs ?? const <String>[])
        if (!monster.actionCardMoveIDs.contains(moveID)) ?movesByID[moveID],
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
              if (monster.actionCardMoveIDs.isEmpty)
                Text(
                  l10n.actionCardTaughtNone,
                  style: SnapmonTextStyles.body.copyWith(
                    color: SnapmonColors.textOnCardBody,
                  ),
                ),
              for (final moveID in monster.actionCardMoveIDs)
                Row(
                  key: Key('action-card-taught-$moveID'),
                  children: [
                    Expanded(
                      child: Text(
                        movesByID[moveID]?.displayName ?? moveID,
                        style: SnapmonTextStyles.body.copyWith(
                          color: SnapmonColors.textOnCard,
                        ),
                      ),
                    ),
                    TextButton(
                      key: Key('action-card-forget-$moveID'),
                      onPressed: _isUpdating || store == null
                          ? null
                          : () => _updateActionCardMoveIDs(
                              update: () => store.client.forgetActionCardMove(
                                monsterID: monster.definition.id,
                                moveID: moveID,
                              ),
                            ),
                      // テーマの文字色 (accent) は明るいカードの上で読めないため、カードの上の文字色にする
                      style: TextButton.styleFrom(
                        foregroundColor: SnapmonColors.textOnCard,
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
                          await _updateActionCardMoveIDs(
                            update: () => store.client.teachActionCardMove(
                              monsterID: monster.definition.id,
                              moveID: move.id,
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
                    sceneRoute<void>(
                      builder: (context) =>
                          ActionCardScreen(dexStore: widget.dexStore),
                    ),
                  ),
                  // テーマの文字色 (accent) は明るいカードの上で読めないため、カードの上の文字色と枠にする
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SnapmonColors.textOnCard,
                    side: const BorderSide(
                      color: SnapmonColors.textOnCardMuted,
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
