import 'dart:async';

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../domain/master/master_data.dart';
import '../../domain/master/move.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../monster_ui/move_card.dart';
import '../capture/monster_generator.dart';
import '../dex/dex_store.dart';
import 'action_card_client.dart';
import 'action_card_store.dart';

/// 購入の後に webhook の反映を待ってから「反映を待っています」の案内を出すまでの時間。
/// 生成チケットの購入画面 (lib/features/capture/ticket_purchase_sheet.dart) と同じ webhook のため、同じ長さにした。
const Duration _purchaseArrivalNoticeDelay = Duration(seconds: 20);

/// [master] の技を ID で引く表。技のランクの表と買い切った技は最新の版の master の技で、端末の master にまだ無い技は表に無い
/// (`refreshDefinitionsForActionCardMoves` が定義を読み直すまでの間。無い技は出さない)。
Map<String, Move> _movesByID({required MasterData master}) => {
  for (final move in master.moves) move.id: move,
};

/// [store] の売っている package のうち、ランク [rank] のもの。売っていなければ null。
Package? actionCardPackageOfRank({
  required ActionCardStore store,
  required int rank,
}) => store.packages
    .where((package) => actionCardRankOfPackage(package: package) == rank)
    .firstOrNull;

/// 技に結び付いていない購入 [purchase] で受け取れる技。今のランクが購入のランク以下で、まだ買い切っていない技 (ID の順)。
/// 判定は Functions の assignActionCardMove (functions/src/action_card_rules.ts の canAssignMoveToActionCard) と同じ。
List<Move> assignableMovesOfPurchase({
  required ActionCardPurchase purchase,
  required ActionCardStore store,
  required MasterData master,
}) {
  final movesByID = _movesByID(master: master);
  return [
    for (final MapEntry(key: moveID, value: moveRank)
        in (store.rankByMoveID ?? const <String, int>{}).entries)
      if (moveRank <= purchase.rank && !store.ownedMoveIDs.contains(moveID))
        ?movesByID[moveID],
  ]..sort((left, right) => left.id.compareTo(right.id));
}

/// Action Card の画面。技に結び付いていない購入 (あれば)、技を選んで買う一覧、買い切った技を出す。
/// 入口はプロフィールと図鑑の詳細 ([ActionCardStore.isScreenEntryVisible] の時だけ)。
class ActionCardScreen extends StatefulWidget {
  /// 画面を作る。
  const ActionCardScreen({super.key, required this.dexStore});

  /// 技の名前・属性を引く定義の持ち主。定義は読み直しで変わるため、開いた時の定義ではなくこの最新の値を使う。
  final DexStore dexStore;

  @override
  State<ActionCardScreen> createState() => _ActionCardScreenState();
}

/// [ActionCardScreen] の属性の絞り込みと、定義の読み直しの状態。
class _ActionCardScreenState extends State<ActionCardScreen> {
  /// 買う一覧を絞る属性。null はすべて。
  String? _elementTypeIDFilter;

  /// 定義の読み直しを頼んだ技 (`refreshDefinitionsForActionCardMoves`)。
  final Set<String> _requestedMoveIDs = {};

  /// 定義に無い技が届いたかを見ている [ActionCardStore]。
  ActionCardStore? _listenedActionCardStore;

  /// [_listenedActionCardStore] の技のうち定義に無い技があれば、定義を読み直す。
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
  }

  @override
  void dispose() {
    _listenedActionCardStore?.removeListener(_refreshMissingDefinitions);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // offering の切り替えはアプリの再リリース無しで行うため、開くたびに読み直す
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(ActionCardScope.maybeOf(context)?.refreshPackages());
      }
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.dexStore,
    builder: (context, _) => _buildScreen(context: context),
  );

  /// [build] の中身。定義が読み直されるたびに描き直す。
  Widget _buildScreen({required BuildContext context}) {
    final l10n = context.l10n;
    final store = ActionCardScope.maybeOf(context);
    if (store == null) {
      return const SizedBox.shrink();
    }
    final movesByID = _movesByID(master: widget.dexStore.definitions);
    final rankByMoveID = store.rankByMoveID;
    // 売っているランクの技だけを出す (offering に無いランクの技は値段を出せず買えないため)
    final purchasableMoves = [
      if (rankByMoveID != null && store.isPurchaseEntryVisible)
        for (final MapEntry(key: moveID, value: moveRank)
            in rankByMoveID.entries)
          if (!store.ownedMoveIDs.contains(moveID) &&
              actionCardPackageOfRank(store: store, rank: moveRank) != null)
            ?movesByID[moveID],
    ]..sort((left, right) => left.id.compareTo(right.id));
    // 選んだ属性の技を買い切り終えるとその属性のチップは消えるため、買える技が無い属性はすべてとして扱う
    // (一覧が空のまま、どのチップも選ばれていない状態にしないため)。選んだ値も次のフレームで解除する
    // (残すと、後で技のランクや売っているランクが変わってその属性の技がまた買えるようになった時に、触っていない絞り込みが戻るため)
    final activeElementTypeIDFilter =
        purchasableMoves.any(
          (move) => move.elementTypeID == _elementTypeIDFilter,
        )
        ? _elementTypeIDFilter
        : null;
    if (_elementTypeIDFilter != null && activeElementTypeIDFilter == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _elementTypeIDFilter = null);
        }
      });
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.actionCardTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // 技に結び付いていない購入は、選び直しが要る時だけ出す (通常の購入は技を選んでから買うため残らない。#290)
          if (store.unassignedPurchases.isNotEmpty) ...[
            Text(
              l10n.actionCardUnassignedHeading,
              style: SnapmonTextStyles.label,
            ),
            const SizedBox(height: 8),
            for (final purchase in store.unassignedPurchases)
              Card(
                key: Key(
                  'action-card-unassigned-${purchase.actionCardPurchaseID}',
                ),
                color: SnapmonColors.card,
                // テーマの文字色は暗い背景の上の色のため、明るいカードの上の色を指定する (指定しないと文字が背景に溶けて読めない)
                child: ListTile(
                  title: Text(
                    l10n.actionCardRank(purchase.rank),
                    style: SnapmonTextStyles.body.copyWith(
                      color: SnapmonColors.textOnCard,
                    ),
                  ),
                  trailing: TextButton(
                    key: Key(
                      'action-card-unassigned-choose-${purchase.actionCardPurchaseID}',
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: SnapmonColors.textOnCard,
                      // 押せない間 (技のランクの表が届く前) の既定はテーマの onSurface で、カードと同じ色になり読めないため
                      disabledForegroundColor: SnapmonColors.textOnCardMuted,
                    ),
                    onPressed: rankByMoveID == null
                        ? null
                        : () => showActionCardAssignSheet(
                            context: context,
                            purchase: purchase,
                            definitions: widget.dexStore.definitions,
                          ),
                    child: Text(l10n.actionCardUnassignedChooseMove),
                  ),
                ),
              ),
            const SizedBox(height: 24),
          ],
          Text(l10n.actionCardBuyHeading, style: SnapmonTextStyles.label),
          const SizedBox(height: 4),
          Text(l10n.actionCardBuyDescription, style: SnapmonTextStyles.small),
          const SizedBox(height: 8),
          if (!store.isPurchaseEntryVisible)
            Text(l10n.actionCardBuyUnavailable, style: SnapmonTextStyles.body)
          else if (rankByMoveID == null)
            Text(l10n.actionCardRanksPreparing, style: SnapmonTextStyles.body)
          else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text(l10n.actionCardFilterAll),
                  selected: activeElementTypeIDFilter == null,
                  onSelected: (_) =>
                      setState(() => _elementTypeIDFilter = null),
                ),
                for (final elementType
                    in widget.dexStore.definitions.elementTypes)
                  if (purchasableMoves.any(
                    (move) => move.elementTypeID == elementType.id,
                  ))
                    ChoiceChip(
                      key: Key('action-card-filter-${elementType.id}'),
                      label: Text(elementType.displayName),
                      selected: activeElementTypeIDFilter == elementType.id,
                      onSelected: (_) =>
                          setState(() => _elementTypeIDFilter = elementType.id),
                    ),
              ],
            ),
            const SizedBox(height: 8),
            for (final move in purchasableMoves)
              if (activeElementTypeIDFilter == null ||
                  move.elementTypeID == activeElementTypeIDFilter)
                _ActionCardMoveTile(
                  key: Key('action-card-buy-${move.id}'),
                  move: move,
                  trailingText:
                      '${l10n.actionCardRank(rankByMoveID[move.id]!)}\n${actionCardPackageOfRank(store: store, rank: rankByMoveID[move.id]!)!.storeProduct.priceString}',
                  definitions: widget.dexStore.definitions,
                  onTap: () => showActionCardMovePurchaseSheet(
                    context: context,
                    move: move,
                    definitions: widget.dexStore.definitions,
                  ),
                ),
          ],
          const SizedBox(height: 24),
          Text(l10n.actionCardOwnedHeading, style: SnapmonTextStyles.label),
          const SizedBox(height: 8),
          if (store.ownedMoveIDs.isEmpty)
            Text(l10n.actionCardOwnedEmpty, style: SnapmonTextStyles.body)
          else
            for (final moveID in store.ownedMoveIDs)
              if (movesByID[moveID] case final move?)
                _ActionCardMoveTile(
                  key: Key('action-card-owned-${move.id}'),
                  move: move,
                  trailingText: null,
                  definitions: widget.dexStore.definitions,
                  onTap: null,
                ),
        ],
      ),
    );
  }
}

/// Action Card の画面の技の 1 行。
class _ActionCardMoveTile extends StatelessWidget {
  const _ActionCardMoveTile({
    super.key,
    required this.move,
    required this.trailingText,
    required this.definitions,
    required this.onTap,
  });

  /// 出す技。
  final Move move;

  /// 右に出す文言 (買う一覧では技の今のランクと値段)。買い切った技の一覧では出さないため null。
  final String? trailingText;

  /// 技の属性の名前を引く定義。
  final MasterData definitions;

  /// 押した時の処理。null の間は押せない。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: SnapmonColors.card,
    child: ListTile(
      onTap: onTap,
      title: MoveCard(
        move: move,
        remainingPowerPoints: null,
        typeMultiplier: null,
        definitions: definitions,
      ),
      trailing: switch (trailingText) {
        final trailingText? => Text(
          trailingText,
          textAlign: TextAlign.end,
          style: SnapmonTextStyles.small.copyWith(
            color: SnapmonColors.textOnCardMuted,
          ),
        ),
        null => null,
      },
    ),
  );
}

/// 技 [move] を買う画面を出す。技の今のランクの商品の値段を出し、買うと技を控えてからストアで購入し、購入が届くまで待つ。
Future<void> showActionCardMovePurchaseSheet({
  required BuildContext context,
  required Move move,
  required MasterData definitions,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // ドラッグの閉じ方は PopScope で止まらず、購入の途中に閉じると結果を受ける画面が無くなるため切る
  enableDrag: false,
  builder: (context) =>
      _ActionCardMovePurchaseSheet(move: move, definitions: definitions),
);

/// 技を 1 つ買う画面。
class _ActionCardMovePurchaseSheet extends StatefulWidget {
  const _ActionCardMovePurchaseSheet({
    required this.move,
    required this.definitions,
  });

  /// 買う技。
  final Move move;

  /// 技の属性の名前を引く定義。
  final MasterData definitions;

  @override
  State<_ActionCardMovePurchaseSheet> createState() =>
      _ActionCardMovePurchaseSheetState();
}

/// [_ActionCardMovePurchaseSheet] の購入の進み具合。
class _ActionCardMovePurchaseSheetState
    extends State<_ActionCardMovePurchaseSheet> {
  /// 技の控えかストアの購入の途中か。
  bool _isPurchasing = false;

  /// 購入が済んだ (か支払いが保留になった) 時の控えの ID。この ID の購入が届くのを待つ (別の端末の購入と取り違えないため)。
  String? _actionCardMoveReservationID;

  /// 支払いが保留になったか。もう一度買わせないため、買うボタンを出さない。
  bool _isPaymentPending = false;

  /// 反映に時間がかかっている案内を出すか。
  bool _isPurchaseArrivalDelayed = false;

  /// 値段を出している間に技のランクが変わり、控えを断られたか。新しいランクの値段を出して買い直してもらう。
  bool _isRankChanged = false;

  /// 最後の購入の失敗。
  Object? _purchaseError;

  /// [_isPurchaseArrivalDelayed] にするタイマー。
  Timer? _purchaseArrivalNoticeTimer;

  @override
  void dispose() {
    _purchaseArrivalNoticeTimer?.cancel();
    super.dispose();
  }

  /// 値段を出したランク [rank] で技を控え、[package] を購入し、結果に応じて画面を進める。
  Future<void> _purchase({
    required ActionCardStore store,
    required Package package,
    required int rank,
  }) async {
    setState(() {
      _isPurchasing = true;
      _isRankChanged = false;
      _purchaseError = null;
    });
    try {
      final actionCardMoveReservationID = await store.reserveMove(
        moveID: widget.move.id,
        rank: rank,
      );
      final result = await store.purchase(package: package);
      if (!mounted) {
        return;
      }
      setState(() {
        _isPurchasing = false;
        switch (result) {
          case TicketPurchaseResult.purchased:
            _actionCardMoveReservationID = actionCardMoveReservationID;
            _purchaseArrivalNoticeTimer = Timer(
              _purchaseArrivalNoticeDelay,
              () => setState(() => _isPurchaseArrivalDelayed = true),
            );
          case TicketPurchaseResult.cancelled:
            break;
          case TicketPurchaseResult.pending:
            _actionCardMoveReservationID = actionCardMoveReservationID;
            _isPaymentPending = true;
        }
      });
    } on ActionCardMoveRankChangedException {
      // 新しいランクは技のランクの購読で届くため、届いた値で値段を出し直す
      if (mounted) {
        setState(() {
          _isPurchasing = false;
          _isRankChanged = true;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isPurchasing = false;
          _purchaseError = error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ActionCardScope.maybeOf(context);
    if (store == null) {
      return const SizedBox.shrink();
    }
    return PopScope(
      canPop: !_isPurchasing,
      child: SafeArea(
        // 横向きの小さい端末で文字を大きくすると画面に収まらないため、スクロールできるようにする
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: switch (_actionCardMoveReservationID) {
              final actionCardMoveReservationID? => _arrivalChildren(
                context: context,
                store: store,
                actionCardMoveReservationID: actionCardMoveReservationID,
              ),
              null => _offerChildren(context: context, store: store),
            },
          ),
        ),
      ),
    );
  }

  /// 買う前の中身。技、今のランクの値段、買うボタン。
  List<Widget> _offerChildren({
    required BuildContext context,
    required ActionCardStore store,
  }) {
    final l10n = context.l10n;
    final rank = store.rankByMoveID?[widget.move.id];
    final package = rank == null
        ? null
        : actionCardPackageOfRank(store: store, rank: rank);
    return [
      // MoveCard の文字色は明るいカードの上の色のため、一覧の行と同じカードに載せる (シートの暗い背景では技の名前が読めないため)
      _ActionCardMoveTile(
        move: widget.move,
        trailingText: null,
        definitions: widget.definitions,
        onTap: null,
      ),
      const SizedBox(height: 12),
      if (_isRankChanged) ...[
        Text(
          l10n.actionCardPurchaseRankChanged,
          key: const Key('action-card-purchase-rank-changed'),
          textAlign: TextAlign.center,
          style: SnapmonTextStyles.body,
        ),
        const SizedBox(height: 12),
      ],
      if (rank != null && package != null)
        FilledButton(
          key: const Key('action-card-purchase-buy'),
          onPressed: _isPurchasing
              ? null
              : () => _purchase(store: store, package: package, rank: rank),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              '${l10n.actionCardRank(rank)}  ${l10n.actionCardPurchaseBuy(package.storeProduct.priceString)}',
            ),
          ),
        )
      else
        Text(
          l10n.actionCardBuyUnavailable,
          textAlign: TextAlign.center,
          style: SnapmonTextStyles.body,
        ),
      if (_purchaseError case final purchaseError?)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            purchaseError.toString(),
            textAlign: TextAlign.center,
            style: SnapmonTextStyles.body.copyWith(
              color: SnapmonColors.hitPointsLoss,
            ),
          ),
        ),
      if (_isPurchasing)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Center(child: CircularProgressIndicator()),
        ),
    ];
  }

  /// 購入の後の中身。控え [actionCardMoveReservationID] の購入が届くまで待ち、届いたら技を受け取れたかを出す。
  List<Widget> _arrivalChildren({
    required BuildContext context,
    required ActionCardStore store,
    required String actionCardMoveReservationID,
  }) {
    final l10n = context.l10n;
    final arrivedPurchase = store.purchases
        .where(
          (purchase) =>
              purchase.actionCardMoveReservationID ==
              actionCardMoveReservationID,
        )
        .firstOrNull;
    if (arrivedPurchase == null) {
      return [
        const Center(child: CircularProgressIndicator()),
        const SizedBox(height: 16),
        Text(
          _isPaymentPending
              ? l10n.actionCardPurchasePending
              : _isPurchaseArrivalDelayed
              ? l10n.actionCardPurchaseArrivalDelayed
              : l10n.actionCardPurchaseWaiting,
          textAlign: TextAlign.center,
          style: SnapmonTextStyles.body,
        ),
      ];
    }
    final isMoveReceived = arrivedPurchase.moveID == widget.move.id;
    return [
      Text(
        isMoveReceived
            ? l10n.actionCardPurchaseArrivedTitle(widget.move.displayName)
            : l10n.actionCardPurchaseUnassignedTitle,
        key: Key(
          isMoveReceived
              ? 'action-card-purchase-arrived'
              : 'action-card-purchase-unassigned',
        ),
        textAlign: TextAlign.center,
        style: SnapmonTextStyles.hero,
      ),
      if (!isMoveReceived) ...[
        const SizedBox(height: 8),
        Text(
          l10n.actionCardPurchaseUnassignedBody,
          textAlign: TextAlign.center,
          style: SnapmonTextStyles.body,
        ),
      ],
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('action-card-purchase-close'),
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.commonClose),
      ),
    ];
  }
}

/// 技に結び付いていない購入 [purchase] で受け取る技を選ぶ画面を出す。
Future<void> showActionCardAssignSheet({
  required BuildContext context,
  required ActionCardPurchase purchase,
  required MasterData definitions,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // ドラッグの閉じ方は PopScope で止まらず、受け取りの途中に閉じると後の pop が背後の画面を閉じるため切る
  enableDrag: false,
  builder: (context) =>
      _ActionCardAssignSheet(purchase: purchase, definitions: definitions),
);

/// 技に結び付いていない購入で受け取る技を選ぶ画面。
class _ActionCardAssignSheet extends StatefulWidget {
  const _ActionCardAssignSheet({
    required this.purchase,
    required this.definitions,
  });

  /// 技に結び付いていない購入。
  final ActionCardPurchase purchase;

  /// 技の名前・属性を引く定義。
  final MasterData definitions;

  @override
  State<_ActionCardAssignSheet> createState() => _ActionCardAssignSheetState();
}

/// [_ActionCardAssignSheet] の受け取りの途中かどうか。
class _ActionCardAssignSheetState extends State<_ActionCardAssignSheet> {
  /// 受け取りの途中の技。途中は他の技を押せなくする (1 つの購入に 2 つの技を結び付けようとさせないため)。
  String? _assigningMoveID;

  /// [move] を購入に結び付け、結果を知らせて閉じる。断られた時は理由を出して画面に残る (選び直せるようにするため)。
  Future<void> _assign({
    required ActionCardStore store,
    required Move move,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    setState(() => _assigningMoveID = move.id);
    try {
      await store.assignMove(
        actionCardPurchaseID: widget.purchase.actionCardPurchaseID,
        moveID: move.id,
      );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.actionCardAssigned(move.displayName))),
      );
      // 受け取りの途中に (アカウントの切り替え等で) シートが閉じていたら、背後の画面を閉じないよう pop しない
      if (mounted) {
        navigator.pop();
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
      if (mounted) {
        setState(() => _assigningMoveID = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final store = ActionCardScope.maybeOf(context);
    if (store == null) {
      return const SizedBox.shrink();
    }
    final moves = assignableMovesOfPurchase(
      purchase: widget.purchase,
      store: store,
      master: widget.definitions,
    );
    return PopScope(
      canPop: _assigningMoveID == null,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                l10n.actionCardAssignTitle(widget.purchase.rank),
                textAlign: TextAlign.center,
                style: SnapmonTextStyles.label,
              ),
              const SizedBox(height: 12),
              if (moves.isEmpty)
                Text(
                  l10n.actionCardAssignNoMoves,
                  textAlign: TextAlign.center,
                  style: SnapmonTextStyles.body,
                ),
              for (final move in moves)
                _ActionCardMoveTile(
                  key: Key('action-card-assign-${move.id}'),
                  move: move,
                  trailingText: l10n.actionCardRank(
                    store.rankByMoveID![move.id]!,
                  ),
                  definitions: widget.definitions,
                  onTap: _assigningMoveID != null
                      ? null
                      : () => _assign(store: store, move: move),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
