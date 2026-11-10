import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:snapmon/features/action_card/action_card_client.dart';
import 'package:snapmon/features/capture/monster_generator.dart';

/// テストの 100 円の Action Card の商品の ID。本番の商品の ID は Functions だけが持つため、テストは別の ID を使う。
const String testCheapActionCardProductID = 'test_actioncard_100yen';

/// テストの 200 円の Action Card の商品の ID。
const String testModerateActionCardProductID = 'test_actioncard_200yen';

/// テストの 300 円の Action Card の商品の ID。
const String testExpensiveActionCardProductID = 'test_actioncard_300yen';

/// テストの商品の ID ごとのストアの価格 (円)。画面がストアの価格をそのまま出すかを確かめる見本の値。
const Map<String, int> _testActionCardPriceOfProductID = {
  testCheapActionCardProductID: 100,
  testModerateActionCardProductID: 200,
  testExpensiveActionCardProductID: 300,
};

/// テストの商品 [productID] の Action Card の package。
Package testActionCardPackage({required String productID}) => Package(
  '${actionCardPackageIdentifierPrefix}test${_testActionCardPriceOfProductID[productID]!}',
  PackageType.custom,
  StoreProduct(
    productID,
    '',
    'Action Card ${_testActionCardPriceOfProductID[productID]!} 円',
    _testActionCardPriceOfProductID[productID]!.toDouble(),
    '¥${_testActionCardPriceOfProductID[productID]!}',
    'JPY',
  ),
  const PresentedOfferingContext('generation_tickets', null, null),
);

/// テストの Action Card の購入。[moveID] が null なら技に結び付いていない購入。
ActionCardPurchase testActionCardPurchase({
  required String actionCardPurchaseID,
  required String productID,
  required String? moveID,
  String? actionCardMoveReservationID,
}) => ActionCardPurchase(
  actionCardPurchaseID: actionCardPurchaseID,
  productID: productID,
  moveID: moveID,
  actionCardMoveReservationID: actionCardMoveReservationID,
  createdAt: DateTime(2026, 11, 10),
  moveAssignedAt: moveID == null ? null : DateTime(2026, 11, 10),
);

/// テストが値を流し、呼び出しを確かめる Action Card の Firestore・Functions・RevenueCat の代わり。
class FakeActionCards {
  /// 課金を使えるビルドか。
  bool isPurchaseSupported = true;

  /// `config/features.actionCardsVisible`。
  final ValueNotifier<bool> isActionCardsVisible = ValueNotifier(true);

  /// fetchActionCardPackages の応答。null なら [packages] をすぐ返し、あればテストが完了させるまで待たせる
  /// (読み込みが並んで走る順番を確かめるため)。呼ばれるたびに先頭から 1 つずつ使う。
  final List<Completer<List<Package>>> packagesCompleters = [];

  /// 売っている package。
  List<Package> packages = [
    for (final productID in _testActionCardPriceOfProductID.keys)
      testActionCardPackage(productID: productID),
  ];

  /// `users/{uid}/actionCardPurchases` (記録した順)。
  final ValueNotifier<List<ActionCardPurchase>> purchases = ValueNotifier(
    const [],
  );

  /// 技ごとの商品の ID の表。
  final ValueNotifier<Map<String, String>?> productIDByMoveID = ValueNotifier(
    null,
  );

  /// 購入の結果。null なら終わらない (購入の途中を確かめるため)。
  TicketPurchaseResult? purchaseResult = TicketPurchaseResult.purchased;

  /// 購入した package の ID (呼ばれた順)。
  final List<String> purchasedPackageIds = [];

  /// reserveActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String moveID, String productID})> reservedMoves = [];

  /// reserveActionCardMove が投げる失敗。呼ばれるたびに先頭から 1 つずつ投げ、空なら成功する (値段が変わった後の買い直しを確かめるため)。
  final List<Object> reserveErrors = [];

  /// assignActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String actionCardPurchaseID, String moveID})> assignedMoves = [];

  /// assignActionCardMove が投げる失敗。空なら成功する。
  final List<Object> assignErrors = [];

  /// teachActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String monsterId, String moveId})> taughtMoves = [];

  /// forgetActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String monsterId, String moveId})> forgottenMoves = [];

  /// teach・forget が返す一覧。
  List<String> monsterMoveIdsResult = const [];

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

  /// この代わりを呼ぶ関数の組。
  ActionCardClient client() => ActionCardClient(
    isPurchaseSupported: () => isPurchaseSupported,
    watchActionCardsVisible: () => _watch(notifier: isActionCardsVisible),
    fetchActionCardPackages: () async => packagesCompleters.isEmpty
        ? packages
        : packagesCompleters.removeAt(0).future,
    purchaseActionCardPackage: ({required package}) {
      purchasedPackageIds.add(package.identifier);
      return switch (purchaseResult) {
        final result? => Future.value(result),
        null => Completer<TicketPurchaseResult>().future,
      };
    },
    watchActionCardPurchases: () => _watch(notifier: purchases),
    watchActionCardProductIDByMoveID: () =>
        _watch(notifier: productIDByMoveID),
    reserveActionCardMove: ({required moveID, required productID}) async {
      reservedMoves.add((moveID: moveID, productID: productID));
      if (reserveErrors.isNotEmpty) {
        throw reserveErrors.removeAt(0);
      }
      return 'reservation-${reservedMoves.length}';
    },
    assignActionCardMove:
        ({required actionCardPurchaseID, required moveID}) async {
          assignedMoves.add((
            actionCardPurchaseID: actionCardPurchaseID,
            moveID: moveID,
          ));
          if (assignErrors.isNotEmpty) {
            throw assignErrors.removeAt(0);
          }
        },
    teachActionCardMove: ({required monsterId, required moveId}) async {
      taughtMoves.add((monsterId: monsterId, moveId: moveId));
      return monsterMoveIdsResult;
    },
    forgetActionCardMove: ({required monsterId, required moveId}) async {
      forgottenMoves.add((monsterId: monsterId, moveId: moveId));
      return monsterMoveIdsResult;
    },
  );
}
