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

/// テストが値を流し、呼び出しを確かめる Action Card の Firestore・Functions・RevenueCat の代わり。
class FakeActionCards {
  /// 課金を使えるビルドか。
  bool isPurchaseSupported = true;

  /// `config/features.actionCardsVisible`。
  final ValueNotifier<bool> isActionCardsVisible = ValueNotifier(true);

  /// 売っている package。
  List<Package> packages = [
    for (final rank in actionCardRanks) testActionCardPackage(rank: rank),
  ];

  /// ランクごとの残高。
  final ValueNotifier<Map<int, int>> creditsByRank = ValueNotifier(const {});

  /// 技のランクの表。
  final ValueNotifier<Map<String, int>?> rankByMoveId = ValueNotifier(null);

  /// 買い切った技。
  final ValueNotifier<List<String>> ownedMoveIds = ValueNotifier(const []);

  /// 購入の結果。null なら終わらない (購入の途中を確かめるため)。
  TicketPurchaseResult? purchaseResult = TicketPurchaseResult.purchased;

  /// 購入した package の ID (呼ばれた順)。
  final List<String> purchasedPackageIds = [];

  /// redeemActionCard に渡された技 (呼ばれた順)。
  final List<String> redeemedMoveIds = [];

  /// teachActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String monsterId, String moveId})> taughtMoves = [];

  /// forgetActionCardMove に渡された引数 (呼ばれた順)。
  final List<({String monsterId, String moveId})> forgottenMoves = [];

  /// teach・forget が返す一覧。
  List<String> monsterMoveIdsResult = const [];

  /// redeemActionCard の応答。null なら今の残高をすぐ返し、あればテストが完了させるまで待たせる (応答の途中を確かめるため)。
  Completer<Map<int, int>>? redeemCompleter;

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
    fetchActionCardPackages: () async => packages,
    purchaseActionCardPackage: ({required package}) {
      purchasedPackageIds.add(package.identifier);
      return switch (purchaseResult) {
        final result? => Future.value(result),
        null => Completer<TicketPurchaseResult>().future,
      };
    },
    watchActionCardCredits: () => _watch(notifier: creditsByRank),
    watchMoveRanks: () => _watch(notifier: rankByMoveId),
    watchOwnedActionCardMoveIds: () => _watch(notifier: ownedMoveIds),
    redeemActionCard: ({required moveId}) async {
      redeemedMoveIds.add(moveId);
      return redeemCompleter?.future ?? creditsByRank.value;
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
