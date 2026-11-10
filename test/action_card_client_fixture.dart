import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:snapmon/features/action_card/action_card_client.dart';
import 'package:snapmon/features/capture/monster_generator.dart';

/// テストの Action Card の package。価格はストアから来る値の見本で、画面がこの値をそのまま出すかを確かめる。
Package testActionCardPackage({required int rank}) => Package(
  '$actionCardPackageIdentifierPrefix$rank',
  PackageType.custom,
  StoreProduct(
    'snapmon_actioncard_rank$rank',
    '',
    'Action Card ランク $rank',
    rank * 100,
    '¥${rank * 100}',
    'JPY',
  ),
  const PresentedOfferingContext('generation_tickets', null, null),
);

/// テストの Action Card の購入。[moveID] が null なら技に結び付いていない購入。
ActionCardPurchase testActionCardPurchase({
  required String actionCardPurchaseID,
  required int rank,
  required String? moveID,
  String? actionCardMoveReservationID,
}) => ActionCardPurchase(
  actionCardPurchaseID: actionCardPurchaseID,
  rank: rank,
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
    for (final rank in actionCardRanks) testActionCardPackage(rank: rank),
  ];

  /// `users/{uid}/actionCardPurchases` (記録した順)。
  final ValueNotifier<List<ActionCardPurchase>> purchases = ValueNotifier(
    const [],
  );

  /// 技のランクの表。
  final ValueNotifier<Map<String, int>?> rankByMoveID = ValueNotifier(null);

  /// 購入の結果。null なら終わらない (購入の途中を確かめるため)。
  TicketPurchaseResult? purchaseResult = TicketPurchaseResult.purchased;

  /// 購入した package の ID (呼ばれた順)。
  final List<String> purchasedPackageIDs = [];

  /// reserveActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String moveID, int rank})> reservedMoves = [];

  /// reserveActionCardMove が投げる失敗。呼ばれるたびに先頭から 1 つずつ投げ、空なら成功する (値段が変わった後の買い直しを確かめるため)。
  final List<Object> reserveErrors = [];

  /// assignActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String actionCardPurchaseID, String moveID})> assignedMoves = [];

  /// assignActionCardMove が投げる失敗。空なら成功する。
  final List<Object> assignErrors = [];

  /// teachActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String monsterID, String moveID})> taughtMoves = [];

  /// forgetActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String monsterID, String moveID})> forgottenMoves = [];

  /// teach・forget が返す一覧。
  List<String> monsterMoveIDsResult = const [];

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
      purchasedPackageIDs.add(package.identifier);
      return switch (purchaseResult) {
        final result? => Future.value(result),
        null => Completer<TicketPurchaseResult>().future,
      };
    },
    watchActionCardPurchases: () => _watch(notifier: purchases),
    watchMoveRanks: () => _watch(notifier: rankByMoveID),
    reserveActionCardMove: ({required moveID, required rank}) async {
      reservedMoves.add((moveID: moveID, rank: rank));
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
    teachActionCardMove: ({required monsterID, required moveID}) async {
      taughtMoves.add((monsterID: monsterID, moveID: moveID));
      return monsterMoveIDsResult;
    },
    forgetActionCardMove: ({required monsterID, required moveID}) async {
      forgottenMoves.add((monsterID: monsterID, moveID: moveID));
      return monsterMoveIDsResult;
    },
  );
}
