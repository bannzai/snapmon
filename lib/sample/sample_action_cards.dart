import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../domain/master/master_data.dart';
import '../features/action_card/action_card_client.dart';
import '../features/capture/monster_generator.dart';

/// DEBUG ビルドでログインを飛ばした時に、Action Card の Firestore・Functions・RevenueCat の代わりになる端末だけの見本。
/// Simulator には StoreKit の購入が無く、ログインを飛ばした端末は Functions を呼べないため、開発者メニューから
/// 表示の切り替え・技に結び付いていない購入・技ごとの商品の表を作り、技を選んで買う・選び直す・覚えさせる・忘れさせるの画面の流れを確かめる
/// (~/.claude/rules/debug-menu-first-for-hard-to-reach-states.md)。値はアプリを閉じると消える。
class SampleActionCards {
  /// 見本の Action Card の商品の ID (安い順)。本番の商品の ID は Functions (functions/src/action_card_rules.ts) だけが持ち、
  /// アプリは技に割り振られた商品の ID をそのまま使うため、見本は本番と別の ID にする (本番の ID をアプリに写さないため)。
  static const List<String> sampleActionCardProductIDs = [
    'sample_actioncard_100yen',
    'sample_actioncard_300yen',
    'sample_actioncard_500yen',
  ];

  /// 見本を作る。[actionCardMoveIdsOf] は図鑑の [monsterId] のモンスターが今覚えている Action Card の技を返す
  /// (覚えさせる・忘れさせるの結果を、Functions と同じく今の一覧から作るため)。
  SampleActionCards({required this.actionCardMoveIdsOf});

  /// 図鑑の [monsterId] のモンスターが今覚えている Action Card の技。
  final List<String> Function({required String monsterId}) actionCardMoveIdsOf;

  /// `config/features.actionCardsVisible` の代わり。
  final ValueNotifier<bool> isActionCardsVisible = ValueNotifier(false);

  /// `users/{uid}/actionCardPurchases` の代わり (記録した順)。
  final ValueNotifier<List<ActionCardPurchase>> purchases = ValueNotifier(
    const [],
  );

  /// `actionCardProducts/current.productIDByMoveID` の代わり。
  final ValueNotifier<Map<String, String>?> productIDByMoveID = ValueNotifier(
    null,
  );

  /// 次の購入が届く前に、控えた技を受け取れなくするか (開発者メニューが切り替える)。技を選んでから購入が届くまでの間に
  /// 技の商品が変わり、技に結び付かない購入が残る流れ (選び直しの導線) を確かめるため。
  final ValueNotifier<bool> blocksReservedMoveBeforeArrival = ValueNotifier(
    false,
  );

  /// `users/{uid}.actionCardMoveReservation` の代わり。
  ({String actionCardMoveReservationID, String moveID, String productID})?
  _reservation;

  /// 見本の購入と控えの ID に付ける番号。
  int _sampleSequence = 0;

  /// 商品 [productID] の技に結び付いていない購入を 1 件足す (#290 より前の購入や、選び直しが要る購入の代わり)。
  void addUnassignedPurchase({required String productID}) => _addPurchase(
    productID: productID,
    moveID: null,
    actionCardMoveReservationID: null,
  );

  /// 購入を 1 件足す。
  void _addPurchase({
    required String productID,
    required String? moveID,
    required String? actionCardMoveReservationID,
  }) => purchases.value = [
    ...purchases.value,
    ActionCardPurchase(
      actionCardPurchaseID: 'sample-purchase-${++_sampleSequence}',
      productID: productID,
      moveID: moveID,
      actionCardMoveReservationID: actionCardMoveReservationID,
      createdAt: DateTime.now(),
      moveAssignedAt: moveID == null ? null : DateTime.now(),
    ),
  ];

  /// 買い切った技の ID。
  Set<String> get _ownedMoveIDs => {
    for (final purchase in purchases.value) ?purchase.moveID,
  };

  /// [master] の買える技 (置き換えられた技を除く) に、威力で見本の商品を割り振った表を入れる。使用回数は見ない。
  /// 区切りの 110 と 70 は、Functions の予備の商品 (functions/src/action_card_rules.ts の `fallbackActionCardProductID`) が使う
  /// `EXPENSIVE_PRODUCT_MINIMUM_POWER`・`MODERATE_PRODUCT_MINIMUM_POWER` と同じ値にした (見本でも本番と同じ値段の並びで画面を確かめるため)。
  /// Dart から TypeScript の定数を読めないため値を写しており、向こうを変えたらここも変える。DEBUG ビルドの見本だけが使い、
  /// 本番の技ごとの商品は actionCardProducts/current が正。
  void loadSampleActionCardProducts({required MasterData master}) {
    final replacedMoveIds = {
      for (final move in master.moves) ?move.replacesMoveId,
    };
    productIDByMoveID.value = {
      for (final move in master.moves)
        if (!replacedMoveIds.contains(move.id))
          move.id: sampleActionCardProductIDs[move.power >= 110
              ? 2
              : move.power >= 70
              ? 1
              : 0],
    };
  }

  /// [notifier] の今の値を流し、変わるたびに流す。
  Stream<T> _watch<T>({required ValueNotifier<T> notifier}) {
    late final StreamController<T> controller;
    void emit() => controller.add(notifier.value);
    controller = StreamController<T>(
      onListen: () {
        notifier.addListener(emit);
        emit();
      },
      onCancel: () => notifier.removeListener(emit),
    );
    return controller.stream;
  }

  /// 見本の商品ごとの package。価格はストアから読まないため「見本の価格」と出す。並べ替えに使う price は商品の順の値にする。
  List<Package> _samplePackages() => [
    for (final (index, productID) in sampleActionCardProductIDs.indexed)
      Package(
        '${actionCardPackageIdentifierPrefix}sample${index + 1}',
        PackageType.custom,
        StoreProduct(
          productID,
          '',
          'Action Card (見本 ${index + 1})',
          index.toDouble(),
          '見本の価格 ${index + 1}',
          '',
        ),
        const PresentedOfferingContext('sample', null, null),
      ),
  ];

  /// reserveActionCardMove の代わり。買い切り済み・技の商品が [productID] と違う時に断るのは Functions と同じ。
  Future<String> _reserve({
    required String moveID,
    required String productID,
  }) async {
    if (_ownedMoveIDs.contains(moveID)) {
      throw StateError('$moveID は買い切り済みです');
    }
    final moveProductID = productIDByMoveID.value?[moveID];
    if (moveProductID == null) {
      throw StateError('技ごとの商品の表に $moveID がありません');
    }
    if (moveProductID != productID) {
      throw ActionCardMoveProductChangedException(productID: moveProductID);
    }
    final actionCardMoveReservationID =
        'sample-reservation-${++_sampleSequence}';
    _reservation = (
      actionCardMoveReservationID: actionCardMoveReservationID,
      moveID: moveID,
      productID: productID,
    );
    return actionCardMoveReservationID;
  }

  /// [Package] の購入と webhook の代わり。webhook が届くまでの間を確かめられるよう、3 秒後に購入を足す。
  /// 控えた技を購入に結び付ける条件は Functions (functions/src/generation_tickets.ts) と同じ。
  /// [blocksReservedMoveBeforeArrival] がオンなら、購入を足す前に控えた技を別の見本の商品に変えるので、技に結び付かない購入が残る。
  Future<TicketPurchaseResult> _purchase({required Package package}) async {
    final productID = package.storeProduct.identifier;
    Timer(const Duration(seconds: 3), () {
      final reservation = _reservation?.productID == productID
          ? _reservation
          : null;
      if (reservation != null && blocksReservedMoveBeforeArrival.value) {
        productIDByMoveID.value = {
          ...?productIDByMoveID.value,
          reservation.moveID: sampleActionCardProductIDs.firstWhere(
            (candidate) => candidate != reservation.productID,
          ),
        };
      }
      final canReceive =
          reservation != null &&
          productIDByMoveID.value?[reservation.moveID] ==
              reservation.productID &&
          !_ownedMoveIDs.contains(reservation.moveID);
      _addPurchase(
        productID: productID,
        moveID: canReceive ? reservation.moveID : null,
        actionCardMoveReservationID: reservation?.actionCardMoveReservationID,
      );
      if (reservation != null) {
        _reservation = null;
      }
    });
    return TicketPurchaseResult.purchased;
  }

  /// assignActionCardMove の代わり。断る条件は Functions と同じ。
  Future<void> _assign({
    required String actionCardPurchaseID,
    required String moveID,
  }) async {
    final purchase = purchases.value.singleWhere(
      (purchase) => purchase.actionCardPurchaseID == actionCardPurchaseID,
    );
    if (purchase.moveID != null) {
      throw StateError('$actionCardPurchaseID は技を受け取り済みです');
    }
    if (_ownedMoveIDs.contains(moveID)) {
      throw StateError('$moveID は買い切り済みです');
    }
    if (productIDByMoveID.value?[moveID] != purchase.productID) {
      throw StateError(
        '${purchase.productID} の Action Card では $moveID を受け取れません',
      );
    }
    purchases.value = [
      for (final candidate in purchases.value)
        candidate.actionCardPurchaseID == actionCardPurchaseID
            ? ActionCardPurchase(
                actionCardPurchaseID: candidate.actionCardPurchaseID,
                productID: candidate.productID,
                moveID: moveID,
                actionCardMoveReservationID:
                    candidate.actionCardMoveReservationID,
                createdAt: candidate.createdAt,
                moveAssignedAt: DateTime.now(),
              )
            : candidate,
    ];
  }

  /// teachActionCardMove の代わり。既に覚えていれば変えない (冪等)。
  Future<List<String>> _teach({
    required String monsterId,
    required String moveId,
  }) async {
    if (!_ownedMoveIDs.contains(moveId)) {
      throw StateError('$moveId を買い切っていません');
    }
    final actionCardMoveIds = actionCardMoveIdsOf(monsterId: monsterId);
    return actionCardMoveIds.contains(moveId)
        ? actionCardMoveIds
        : [...actionCardMoveIds, moveId];
  }

  /// forgetActionCardMove の代わり。覚えていなければ変えない (冪等)。
  Future<List<String>> _forget({
    required String monsterId,
    required String moveId,
  }) async => [
    for (final actionCardMoveId in actionCardMoveIdsOf(monsterId: monsterId))
      if (actionCardMoveId != moveId) actionCardMoveId,
  ];

  /// この見本を呼ぶ関数の組。課金の可否はビルドに関係なく使えるとする (Simulator で購入の画面を確かめるため)。
  ActionCardClient client() => ActionCardClient(
    isPurchaseSupported: () => true,
    watchActionCardsVisible: () => _watch(notifier: isActionCardsVisible),
    fetchActionCardPackages: () async => _samplePackages(),
    purchaseActionCardPackage: _purchase,
    watchActionCardPurchases: () => _watch(notifier: purchases),
    watchActionCardProductIDByMoveID: () =>
        _watch(notifier: productIDByMoveID),
    reserveActionCardMove: _reserve,
    assignActionCardMove: _assign,
    teachActionCardMove: _teach,
    forgetActionCardMove: _forget,
  );
}
