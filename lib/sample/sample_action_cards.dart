import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../domain/master/master_data.dart';
import '../features/action_card/action_card_client.dart';
import '../features/capture/monster_generator.dart';

/// DEBUG ビルドでログインを飛ばした時に、Action Card の Firestore・Functions・RevenueCat の代わりになる端末だけの見本。
/// Simulator には StoreKit の購入が無く、ログインを飛ばした端末は Functions を呼べないため、開発者メニューから
/// 表示の切り替え・残高・技のランクの表を作り、購入・買い切り・覚えさせる・忘れさせるの画面の流れを確かめる
/// (~/.claude/rules/debug-menu-first-for-hard-to-reach-states.md)。値はアプリを閉じると消える。
class SampleActionCards {
  /// 見本を作る。[actionCardMoveIdsOf] は図鑑の [monsterId] のモンスターが今覚えている Action Card の技を返す
  /// (覚えさせる・忘れさせるの結果を、Functions と同じく今の一覧から作るため)。
  SampleActionCards({required this.actionCardMoveIdsOf});

  /// 図鑑の [monsterId] のモンスターが今覚えている Action Card の技。
  final List<String> Function({required String monsterId}) actionCardMoveIdsOf;

  /// `config/features.actionCardsVisible` の代わり。
  final ValueNotifier<bool> isActionCardsVisible = ValueNotifier(false);

  /// `users/{uid}.actionCardCredits` の代わり。
  final ValueNotifier<Map<int, int>> creditsByRank = ValueNotifier(const {});

  /// `moveRanks/current.rankByMoveId` の代わり。
  final ValueNotifier<Map<String, int>?> rankByMoveId = ValueNotifier(null);

  /// `users/{uid}/actionCards` の代わり。
  final ValueNotifier<List<String>> ownedMoveIds = ValueNotifier(const []);

  /// [rank] の残高を 1 枚足す。
  void addCredit({required int rank}) => creditsByRank.value = {
    ...creditsByRank.value,
    rank: (creditsByRank.value[rank] ?? 0) + 1,
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

  /// [Package] の購入の代わり。webhook が届くまでの間を確かめられるよう、3 秒後に残高を 1 枚足す。
  Future<TicketPurchaseResult> _purchase({required Package package}) async {
    final rank = actionCardRankOfPackage(package: package)!;
    Timer(const Duration(seconds: 3), () => addCredit(rank: rank));
    return TicketPurchaseResult.purchased;
  }

  /// redeemActionCard の代わり。使うカードの決め方と、買い切り済み・カードが無い時・使うカードのランクが [creditRank] と違う時に
  /// 断るのは Functions と同じ。
  Future<Map<int, int>> _redeem({
    required String moveId,
    required int creditRank,
  }) async {
    if (ownedMoveIds.value.contains(moveId)) {
      throw StateError('$moveId は買い切り済みです');
    }
    final moveRank = rankByMoveId.value?[moveId];
    if (moveRank == null) {
      throw StateError('技のランクの表に $moveId がありません');
    }
    final redeemedCreditRank = creditRankToRedeem(
      moveRank: moveRank,
      creditsByRank: creditsByRank.value,
    );
    if (redeemedCreditRank == null) {
      throw StateError('ランク $moveRank 以上の Action Card がありません');
    }
    if (redeemedCreditRank != creditRank) {
      throw ActionCardCreditRankChangedException(
        creditRank: redeemedCreditRank,
        creditsByRank: creditsByRank.value,
      );
    }
    creditsByRank.value = {
      ...creditsByRank.value,
      redeemedCreditRank: creditsByRank.value[redeemedCreditRank]! - 1,
    };
    ownedMoveIds.value = [...ownedMoveIds.value, moveId];
    return creditsByRank.value;
  }

  /// teachActionCardMove の代わり。既に覚えていれば変えない (冪等)。
  Future<List<String>> _teach({
    required String monsterId,
    required String moveId,
  }) async {
    if (!ownedMoveIds.value.contains(moveId)) {
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
    watchActionCardCredits: () => _watch(notifier: creditsByRank),
    watchMoveRanks: () => _watch(notifier: rankByMoveId),
    watchOwnedActionCardMoveIds: () => _watch(notifier: ownedMoveIds),
    redeemActionCard: _redeem,
    teachActionCardMove: _teach,
    forgetActionCardMove: _forget,
  );
}
