import 'dart:async';

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../domain/master/master_data.dart';
import '../../domain/master/move.dart';
import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/move_summary.dart';
import '../capture/monster_generator.dart';
import '../dex/dex_store.dart';
import 'action_card_client.dart';
import 'action_card_store.dart';

/// 購入の後に webhook の反映を待ってから「反映を待っています」の案内を出すまでの時間。
/// 生成チケットの購入画面 (lib/features/capture/ticket_purchase_sheet.dart) と同じ webhook のため、同じ長さにした。
const Duration _creditArrivalNoticeDelay = Duration(seconds: 20);

/// [master] の技を ID で引く表。技のランクの表と買い切った技は最新の版の master の技で、端末の master にまだ無い技は表に無い
/// (`refreshDefinitionsForActionCardMoves` が定義を読み直すまでの間。無い技は出さない)。
Map<String, Move> _movesById({required MasterData master}) => {
  for (final move in master.moves) move.id: move,
};

/// [rank] の技のうち、購入画面にランクの例として出す技。威力が一番大きい技 (同じなら ID の順) で、無ければ null。
/// 威力で選ぶのは、高いランクほど強い技が並ぶことを 1 つの名前で伝えるため (documents/DIRECTION.md「決めたこと」の #273 の行)。
Move? featuredMoveOfRank({
  required int rank,
  required Map<String, int> rankByMoveId,
  required MasterData master,
}) {
  final movesById = _movesById(master: master);
  final moves =
      [
        for (final MapEntry(key: moveId, value: moveRank)
            in rankByMoveId.entries)
          if (moveRank == rank) ?movesById[moveId],
      ]..sort((left, right) {
        final powerOrder = right.power.compareTo(left.power);
        return powerOrder != 0 ? powerOrder : left.id.compareTo(right.id);
      });
  return moves.firstOrNull;
}

/// Action Card の画面。持っているカードの枚数、カードを買う入口、技を選んで買い切る一覧、買い切った技を出す。
/// 入口はプロフィールと図鑑の詳細 ([ActionCardStore.isScreenEntryVisible] の時だけ)。
class ActionCardScreen extends StatefulWidget {
  /// 画面を作る。
  const ActionCardScreen({super.key, required this.dexStore});

  /// 技の名前・属性を引く定義の持ち主。定義は読み直しで変わるため、開いた時の定義ではなくこの最新の値を使う。
  final DexStore dexStore;

  @override
  State<ActionCardScreen> createState() => _ActionCardScreenState();
}

/// [ActionCardScreen] の属性の絞り込みと買い切りの途中かどうか。
class _ActionCardScreenState extends State<ActionCardScreen> {
  /// 買い切る一覧を絞る属性。null はすべて。
  String? _elementTypeIdFilter;

  /// 買い切りの途中の技。途中は他の技を押せなくする (同じカードを 2 回使わせないため)。
  String? _redeemingMoveId;

  /// 定義の読み直しを頼んだ技 (`refreshDefinitionsForActionCardMoves`)。
  final Set<String> _requestedMoveIds = {};

  /// 定義に無い技が届いたかを見ている [ActionCardStore]。
  ActionCardStore? _listenedActionCardStore;

  /// [_listenedActionCardStore] の技のうち定義に無い技があれば、定義を読み直す。
  void _refreshMissingDefinitions() {
    if (_listenedActionCardStore case final actionCardStore?) {
      unawaited(
        refreshDefinitionsForActionCardMoves(
          actionCardStore: actionCardStore,
          dexStore: widget.dexStore,
          requestedMoveIds: _requestedMoveIds,
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

  /// [move] を買い切ってよいかを、使うカードのランク [creditRank] を出して確かめてから買い切る。
  Future<void> _redeem({
    required ActionCardStore store,
    required Move move,
    required int creditRank,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final isConfirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.actionCardRedeemConfirmTitle(move.displayName)),
        content: Text(l10n.actionCardRedeemConfirmBody(creditRank)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('action-card-redeem-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.actionCardRedeemConfirm),
          ),
        ],
      ),
    );
    if (isConfirmed != true || !mounted) {
      return;
    }
    setState(() => _redeemingMoveId = move.id);
    try {
      await store.redeem(moveId: move.id);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.actionCardRedeemed(move.displayName))),
      );
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _redeemingMoveId = null);
      }
    }
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
    final movesById = _movesById(master: widget.dexStore.definitions);
    final rankByMoveId = store.rankByMoveId;
    final highestCreditRank = actionCardRanks.lastWhere(
      (rank) => (store.creditsByRank[rank] ?? 0) > 0,
      orElse: () => 0,
    );
    final redeemableMoves = [
      if (rankByMoveId != null)
        for (final MapEntry(key: moveId, value: moveRank)
            in rankByMoveId.entries)
          if (moveRank <= highestCreditRank &&
              !store.ownedMoveIds.contains(moveId))
            ?movesById[moveId],
    ]..sort((left, right) => left.id.compareTo(right.id));
    // 選んだ属性の技を買い切り終えるとその属性のチップは消えるため、買い切れる技が無い属性はすべてとして扱う
    // (選んだ値は残し、チップの選択と一覧の絞り込みだけを戻す。一覧が空のまま、どのチップも選ばれていない状態にしないため)
    final activeElementTypeIdFilter =
        redeemableMoves.any(
          (move) => move.elementTypeId == _elementTypeIdFilter,
        )
        ? _elementTypeIdFilter
        : null;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.actionCardTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Text(l10n.actionCardCreditsHeading, style: SnapmonTextStyles.label),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final rank in actionCardRanks)
                Chip(
                  key: Key('action-card-credit-$rank'),
                  label: Text(
                    '${l10n.actionCardRank(rank)}  ${l10n.actionCardCreditCount(store.creditsByRank[rank] ?? 0)}',
                  ),
                ),
            ],
          ),
          if (store.isPurchaseEntryVisible) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const Key('action-card-buy'),
              onPressed: () => showActionCardPurchaseSheet(
                context: context,
                definitions: widget.dexStore.definitions,
              ),
              icon: const Icon(Icons.shopping_bag_outlined),
              label: Text(l10n.actionCardBuy),
            ),
          ],
          const SizedBox(height: 24),
          Text(l10n.actionCardRedeemHeading, style: SnapmonTextStyles.label),
          const SizedBox(height: 8),
          if (rankByMoveId == null)
            Text(l10n.actionCardRanksPreparing, style: SnapmonTextStyles.body)
          else if (highestCreditRank == 0)
            Text(l10n.actionCardRedeemNoCredits, style: SnapmonTextStyles.body)
          else ...[
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text(l10n.actionCardFilterAll),
                  selected: activeElementTypeIdFilter == null,
                  onSelected: (_) =>
                      setState(() => _elementTypeIdFilter = null),
                ),
                for (final elementType
                    in widget.dexStore.definitions.elementTypes)
                  if (redeemableMoves.any(
                    (move) => move.elementTypeId == elementType.id,
                  ))
                    ChoiceChip(
                      key: Key('action-card-filter-${elementType.id}'),
                      label: Text(elementType.displayName),
                      selected: activeElementTypeIdFilter == elementType.id,
                      onSelected: (_) =>
                          setState(() => _elementTypeIdFilter = elementType.id),
                    ),
              ],
            ),
            const SizedBox(height: 8),
            for (final move in redeemableMoves)
              if (activeElementTypeIdFilter == null ||
                  move.elementTypeId == activeElementTypeIdFilter)
                _ActionCardMoveTile(
                  key: Key('action-card-redeem-${move.id}'),
                  move: move,
                  rank: rankByMoveId[move.id]!,
                  definitions: widget.dexStore.definitions,
                  onTap: _redeemingMoveId != null
                      ? null
                      : switch (creditRankToRedeem(
                          moveRank: rankByMoveId[move.id]!,
                          creditsByRank: store.creditsByRank,
                        )) {
                          final creditRank? => () => _redeem(
                            store: store,
                            move: move,
                            creditRank: creditRank,
                          ),
                          null => null,
                        },
                ),
          ],
          const SizedBox(height: 24),
          Text(l10n.actionCardOwnedHeading, style: SnapmonTextStyles.label),
          const SizedBox(height: 8),
          if (store.ownedMoveIds.isEmpty)
            Text(l10n.actionCardOwnedEmpty, style: SnapmonTextStyles.body)
          else
            for (final moveId in store.ownedMoveIds)
              if (movesById[moveId] case final move?)
                _ActionCardMoveTile(
                  key: Key('action-card-owned-${move.id}'),
                  move: move,
                  rank: null,
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
    required this.rank,
    required this.definitions,
    required this.onTap,
  });

  /// 出す技。
  final Move move;

  /// 技の今のランク。買い切った技の一覧では出さないため null。
  final int? rank;

  /// 技の属性の名前を引く定義。
  final MasterData definitions;

  /// 押した時の処理。null の間は押せない。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: SnapmonColors.card,
    child: ListTile(
      onTap: onTap,
      title: MoveSummary(
        move: move,
        remainingPowerPoints: null,
        typeMultiplier: null,
        definitions: definitions,
      ),
      trailing: switch (rank) {
        final rank? => Text(
          context.l10n.actionCardRank(rank),
          style: SnapmonTextStyles.small.copyWith(
            color: SnapmonColors.textOnCardMuted,
          ),
        ),
        null => null,
      },
    ),
  );
}

/// Action Card の購入画面を出す。売っている package (ランクの順) ごとに、ストアの価格・今そのランクにある技の数・例の技を出す。
/// 技のランクの表がまだ無い間は、買ったカードで技を選べないため買うボタンを押せなくする。
Future<void> showActionCardPurchaseSheet({
  required BuildContext context,
  required MasterData definitions,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  // ドラッグの閉じ方は PopScope で止まらず、購入の途中に閉じると結果を受ける画面が無くなるため切る
  enableDrag: false,
  builder: (context) => _ActionCardPurchaseSheet(definitions: definitions),
);

/// Action Card の購入画面。
class _ActionCardPurchaseSheet extends StatefulWidget {
  const _ActionCardPurchaseSheet({required this.definitions});

  /// 例の技の名前を引く定義。
  final MasterData definitions;

  @override
  State<_ActionCardPurchaseSheet> createState() =>
      _ActionCardPurchaseSheetState();
}

/// [_ActionCardPurchaseSheet] の購入の進み具合。
class _ActionCardPurchaseSheetState extends State<_ActionCardPurchaseSheet> {
  /// ストアの購入の途中か。
  bool _isPurchasing = false;

  /// 購入が済んだ (か支払いが保留になった) カードのランクと、購入を始めた時のそのランクの残高。
  /// 残高がこの値より増えたら届いたとする (残りのカードを持ったまま開けるため、0 より多いかでは決められない)。
  ({int rank, int creditsAtPurchase})? _purchasedCredit;

  /// 支払いが保留になったか。もう一度買わせないため、買うボタンを出さない。
  bool _isPaymentPending = false;

  /// 反映に時間がかかっている案内を出すか。
  bool _isCreditArrivalDelayed = false;

  /// 最後の購入の失敗。
  Object? _purchaseError;

  /// [_isCreditArrivalDelayed] にするタイマー。
  Timer? _creditArrivalNoticeTimer;

  @override
  void dispose() {
    _creditArrivalNoticeTimer?.cancel();
    super.dispose();
  }

  /// [package] (ランク [rank]) を購入し、結果に応じて画面を進める。
  Future<void> _purchase({
    required ActionCardStore store,
    required Package package,
    required int rank,
  }) async {
    final creditsAtPurchase = store.creditsByRank[rank] ?? 0;
    setState(() {
      _isPurchasing = true;
      _purchaseError = null;
    });
    try {
      final result = await store.purchase(package: package);
      if (!mounted) {
        return;
      }
      setState(() {
        _isPurchasing = false;
        switch (result) {
          case TicketPurchaseResult.purchased:
            _purchasedCredit = (
              rank: rank,
              creditsAtPurchase: creditsAtPurchase,
            );
            _creditArrivalNoticeTimer = Timer(_creditArrivalNoticeDelay, () {
              setState(() => _isCreditArrivalDelayed = true);
            });
          case TicketPurchaseResult.cancelled:
            break;
          case TicketPurchaseResult.pending:
            _purchasedCredit = (
              rank: rank,
              creditsAtPurchase: creditsAtPurchase,
            );
            _isPaymentPending = true;
        }
      });
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
    final l10n = context.l10n;
    final store = ActionCardScope.maybeOf(context);
    if (store == null) {
      return const SizedBox.shrink();
    }
    final rankByMoveId = store.rankByMoveId;
    final purchasedCredit = _purchasedCredit;
    return PopScope(
      canPop: !_isPurchasing,
      child: SafeArea(
        // 横向きの小さい端末で文字を大きくすると画面に収まらないため、スクロールできるようにする
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: purchasedCredit != null
                ? (store.creditsByRank[purchasedCredit.rank] ?? 0) >
                          purchasedCredit.creditsAtPurchase
                      ? [
                          Text(
                            l10n.actionCardPurchaseArrivedTitle,
                            textAlign: TextAlign.center,
                            style: SnapmonTextStyles.hero,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${l10n.actionCardRank(purchasedCredit.rank)}  ${l10n.actionCardCreditCount(store.creditsByRank[purchasedCredit.rank] ?? 0)}',
                            textAlign: TextAlign.center,
                            style: SnapmonTextStyles.body,
                          ),
                          const SizedBox(height: 16),
                          FilledButton(
                            key: const Key('action-card-choose-move'),
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(l10n.actionCardPurchaseChooseMove),
                          ),
                        ]
                      : [
                          const Center(child: CircularProgressIndicator()),
                          const SizedBox(height: 16),
                          Text(
                            _isPaymentPending
                                ? l10n.actionCardPurchasePending
                                : _isCreditArrivalDelayed
                                ? l10n.actionCardPurchaseArrivalDelayed
                                : l10n.actionCardPurchaseWaiting,
                            textAlign: TextAlign.center,
                            style: SnapmonTextStyles.body,
                          ),
                        ]
                : [
                    Text(
                      l10n.actionCardTitle,
                      textAlign: TextAlign.center,
                      style: SnapmonTextStyles.hero,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.actionCardPurchaseDescription,
                      textAlign: TextAlign.center,
                      style: SnapmonTextStyles.body,
                    ),
                    const SizedBox(height: 16),
                    if (rankByMoveId == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          l10n.actionCardRanksPreparing,
                          textAlign: TextAlign.center,
                          style: SnapmonTextStyles.body,
                        ),
                      ),
                    for (final package in store.packages)
                      if (actionCardRankOfPackage(package: package)
                          case final rank?)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: FilledButton(
                            key: Key('action-card-package-$rank'),
                            onPressed: _isPurchasing || rankByMoveId == null
                                ? null
                                : () => _purchase(
                                    store: store,
                                    package: package,
                                    rank: rank,
                                  ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  Text(
                                    '${l10n.actionCardRank(rank)}  ${package.storeProduct.priceString}',
                                  ),
                                  if (rankByMoveId != null) ...[
                                    Text(
                                      l10n.actionCardPackageMoves(
                                        rankByMoveId.values
                                            .where(
                                              (moveRank) => moveRank == rank,
                                            )
                                            .length,
                                      ),
                                      style: SnapmonTextStyles.small.copyWith(
                                        color: SnapmonColors.textOnCardMuted,
                                      ),
                                    ),
                                    if (featuredMoveOfRank(
                                          rank: rank,
                                          rankByMoveId: rankByMoveId,
                                          master: widget.definitions,
                                        )
                                        case final featuredMove?)
                                      Text(
                                        l10n.actionCardPackageFeatured(
                                          featuredMove.displayName,
                                        ),
                                        style: SnapmonTextStyles.small.copyWith(
                                          color: SnapmonColors.textOnCardMuted,
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                    if (_purchaseError case final purchaseError?)
                      Text(
                        purchaseError.toString(),
                        textAlign: TextAlign.center,
                        style: SnapmonTextStyles.body.copyWith(
                          color: SnapmonColors.hitPointsLoss,
                        ),
                      ),
                    if (_isPurchasing)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                  ],
          ),
        ),
      ),
    );
  }
}
