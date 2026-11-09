import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../domain/master/master_data.dart';
import '../features/action_card/action_card_client.dart';
import '../features/capture/monster_generator.dart';

/// DEBUG ビルドでログインを飛ばした時に、Action Card の Firestore・Functions・RevenueCat の代わりになる端末だけの見本。
/// Simulator には StoreKit の購入が無く、ログインを飛ばした端末は Functions を呼べないため、開発者メニューから
/// 表示の切り替え・技に結び付いていない購入・技のランクの表を作り、技を選んで買う・選び直す・覚えさせる・忘れさせるの画面の流れを確かめる
/// (~/.claude/rules/debug-menu-first-for-hard-to-reach-states.md)。値はアプリを閉じると消える。
class SampleActionCards {
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

  /// `moveRanks/current.rankByMoveId` の代わり。
  final ValueNotifier<Map<String, int>?> rankByMoveId = ValueNotifier(null);

  /// 次の購入が届く前に、控えた技を受け取れなくするか (開発者メニューが切り替える)。技を選んでから購入が届くまでの間に
  /// ランクが上がるか同じ技を別の端末で受け取り、技に結び付かない購入が残る流れ (選び直しの導線) を確かめるため。
  final ValueNotifier<bool> blocksReservedMoveBeforeArrival = ValueNotifier(
    false,
  );

  /// `users/{uid}.actionCardMoveReservation` の代わり。
  ({String actionCardMoveReservationID, String moveID, int rank})?
  _reservation;

  /// 見本の購入と控えの ID に付ける番号。
  int _sampleSequence = 0;

  /// [rank] の技に結び付いていない購入を 1 件足す (#290 より前の購入や、選び直しが要る購入の代わり)。
  void addUnassignedPurchase({required int rank}) => _addPurchase(
    rank: rank,
    moveID: null,
    actionCardMoveReservationID: null,
  );

  /// 購入を 1 件足す。
  void _addPurchase({
    required int rank,
    required String? moveID,
    required String? actionCardMoveReservationID,
  }) => purchases.value = [
    ...purchases.value,
    ActionCardPurchase(
      actionCardPurchaseID: 'sample-purchase-${++_sampleSequence}',
      rank: rank,
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

  /// [master] の買える技 (置き換えられた技を除く) に、威力でランクを付けた表を入れる。使用回数は見ない。
  /// 区切りの 110 と 70 は、Functions の予備のランク (functions/src/action_card_rules.ts の `fallbackMoveRank`) が使う
  /// `RANK_3_MINIMUM_POWER`・`RANK_2_MINIMUM_POWER` と同じ値にした (見本でも本番と同じランクの並びで画面を確かめるため)。
  /// Dart から TypeScript の定数を読めないため値を写しており、向こうを変えたらここも変える。DEBUG ビルドの見本だけが使い、
  /// 本番のランクは moveRanks/current が正。
  void loadSampleMoveRanks({required MasterData master}) {
    final replacedMoveIds = {
      for (final move in master.moves) ?move.replacesMoveId,
    };
    rankByMoveId.value = {
      for (final move in master.moves)
        if (!replacedMoveIds.contains(move.id))
          move.id: move.power >= 110
              ? 3
              : move.power >= 70
              ? 2
              : 1,
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

  /// ランクごとの見本の package。価格はストアから読まないため「見本の価格」と出す。
  List<Package> _samplePackages() => [
    for (final rank in actionCardRanks)
      Package(
        '$actionCardPackageIdentifierPrefix$rank',
        PackageType.custom,
        StoreProduct(
          'sample_actioncard_rank$rank',
          '',
          'Action Card ランク $rank (見本)',
          0,
          '見本の価格',
          '',
        ),
        const PresentedOfferingContext('sample', null, null),
      ),
  ];

  /// reserveActionCardMove の代わり。買い切り済み・ランクが [rank] と違う時に断るのは Functions と同じ。
  Future<String> _reserve({required String moveID, required int rank}) async {
    if (_ownedMoveIDs.contains(moveID)) {
      throw StateError('$moveID は買い切り済みです');
    }
    final moveRank = rankByMoveId.value?[moveID];
    if (moveRank == null) {
      throw StateError('技のランクの表に $moveID がありません');
    }
    if (moveRank != rank) {
      throw ActionCardMoveRankChangedException(rank: moveRank);
    }
    final actionCardMoveReservationID =
        'sample-reservation-${++_sampleSequence}';
    _reservation = (
      actionCardMoveReservationID: actionCardMoveReservationID,
      moveID: moveID,
      rank: rank,
    );
    return actionCardMoveReservationID;
  }

  /// [Package] の購入と webhook の代わり。webhook が届くまでの間を確かめられるよう、3 秒後に購入を足す。
  /// 控えた技を購入に結び付ける条件は Functions (functions/src/generation_tickets.ts) と同じ。
  /// [blocksReservedMoveBeforeArrival] がオンなら、購入を足す前に控えた技のランクを 1 つ上げる (ランク 3 の技は上げられないため、
  /// 代わりに同じ技を先に受け取ったことにする) ので、技に結び付かない購入が残る。
  Future<TicketPurchaseResult> _purchase({required Package package}) async {
    final rank = actionCardRankOfPackage(package: package)!;
    Timer(const Duration(seconds: 3), () {
      final reservation = _reservation?.rank == rank ? _reservation : null;
      if (reservation != null && blocksReservedMoveBeforeArrival.value) {
        if (reservation.rank < actionCardRanks.last) {
          rankByMoveId.value = {
            ...?rankByMoveId.value,
            reservation.moveID: reservation.rank + 1,
          };
        } else {
          _addPurchase(
            rank: reservation.rank,
            moveID: reservation.moveID,
            actionCardMoveReservationID: null,
          );
        }
      }
      final reservedMoveRank = reservation == null
          ? null
          : rankByMoveId.value?[reservation.moveID];
      final canReceive =
          reservation != null &&
          reservedMoveRank != null &&
          reservedMoveRank <= reservation.rank &&
          !_ownedMoveIDs.contains(reservation.moveID);
      _addPurchase(
        rank: rank,
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
    final moveRank = rankByMoveId.value?[moveID];
    if (moveRank == null || moveRank > purchase.rank) {
      throw StateError(
        'ランク ${purchase.rank} の Action Card では $moveID を受け取れません',
      );
    }
    purchases.value = [
      for (final candidate in purchases.value)
        candidate.actionCardPurchaseID == actionCardPurchaseID
            ? ActionCardPurchase(
                actionCardPurchaseID: candidate.actionCardPurchaseID,
                rank: candidate.rank,
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
    watchMoveRanks: () => _watch(notifier: rankByMoveId),
    reserveActionCardMove: _reserve,
    assignActionCardMove: _assign,
    teachActionCardMove: _teach,
    forgetActionCardMove: _forget,
  );
}
