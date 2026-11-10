import 'package:purchases_flutter/purchases_flutter.dart';

import '../capture/monster_generator.dart';

/// Action Card のランク (安い順)。Functions の functions/src/action_card_rules.ts の `MOVE_RANKS` と同じ値。
const List<int> actionCardRanks = [1, 2, 3];

/// RevenueCat の package の識別子 (offering の package の lookup_key) の接頭辞。後ろにランクの数字が付く
/// (revenuecat/config.json の `actioncard_rank1`〜`actioncard_rank3`)。生成チケットと同じ offering に入る。
const String actionCardPackageIdentifierPrefix = 'actioncard_rank';

/// [package] が Action Card の package ならそのランク、そうでなければ null。
int? actionCardRankOfPackage({required Package package}) =>
    package.identifier.startsWith(actionCardPackageIdentifierPrefix)
    ? int.tryParse(
        package.identifier.substring(actionCardPackageIdentifierPrefix.length),
      )
    : null;

/// Action Card の購入 1 件 (`users/{uid}/actionCardPurchases/{eventID}`。形は functions/src/generation_tickets.ts の
/// `ActionCardPurchaseDocument`)。買い切った技は `moveID` のある購入で、`moveID` の無い購入は技を選び直して受け取る。
class ActionCardPurchase {
  /// Firestore から読んだ購入を作る。
  const ActionCardPurchase({
    required this.actionCardPurchaseID,
    required this.rank,
    required this.moveID,
    required this.actionCardMoveReservationID,
    required this.createdAt,
    required this.moveAssignedAt,
  });

  /// 購入の ID (RevenueCat のイベントの ID。文書 ID)。
  final String actionCardPurchaseID;

  /// 購入した商品のランク。受け取れる技は、受け取る時のランクがこれ以下のもの。
  final int rank;

  /// 買い切った技の ID。技に結び付いていない購入は null (#290 より前のフィールドの無い購入も null)。
  final String? moveID;

  /// 購入に結び付けた控えの ID。購入画面はこの ID の購入が届くのを待つ。控えを使わなかった購入は null。
  final String? actionCardMoveReservationID;

  /// 購入を記録した時刻。
  final DateTime createdAt;

  /// 技を結び付けた時刻。技に結び付いていない間は null。
  final DateTime? moveAssignedAt;
}

/// 技を控える時に端末が出したランクと技の今のランクが違うため断られた (値段を出している間に技のランクが変わった)。
/// reserveActionCardMove が failed-precondition の `details` に今のランクを入れて断った時に投げる (functions/src/action_cards.ts)。
class ActionCardMoveRankChangedException implements Exception {
  /// 断られた時の技の今のランク [rank] を持つ。
  const ActionCardMoveRankChangedException({required this.rank});

  /// 技の今のランク。
  final int rank;

  @override
  String toString() => 'ActionCardMoveRankChangedException(rank: $rank)';
}

/// Action Card の表示の切り替え・商品・購入・技のランクの購読と、技の控え・購入・選び直し・覚えさせる・忘れさせるを呼ぶ関数の組。
/// 画面を Firebase・RevenueCat と切り離してテストするため、実体 (lib/firebase/action_cards.dart) は main.dart から渡す。
/// 購読は uid が変わるたびに空の値 (購入なし・隠す) から流し直す (前のアカウントの値を今のアカウントのものとして出さないため)。
class ActionCardClient {
  /// 関数の組を作る。
  const ActionCardClient({
    required this.isPurchaseSupported,
    required this.watchActionCardsVisible,
    required this.fetchActionCardPackages,
    required this.purchaseActionCardPackage,
    required this.watchActionCardPurchases,
    required this.watchMoveRanks,
    required this.reserveActionCardMove,
    required this.assignActionCardMove,
    required this.teachActionCardMove,
    required this.forgetActionCardMove,
  });

  /// 課金を使えるかを返す。Web と RevenueCat の鍵を渡していないビルドでは false で、購入の入口を出さない
  /// (課金はアプリだけ。documents/DIRECTION.md「必要な機能」)。関数にするのは、DEBUG ビルドでログインを飛ばした間だけ見本の購入に切り替えるため。
  final bool Function() isPurchaseSupported;

  /// `config/features.actionCardsVisible` を流す。無い時・読めない時は false。
  final Stream<bool> Function() watchActionCardsVisible;

  /// RevenueCat の current offering のうち Action Card の package ([actionCardRankOfPackage] が null でないもの) を返す。
  /// 課金が無効なビルド・ログインしていない時・売っていない時は空。
  final Future<List<Package>> Function() fetchActionCardPackages;

  /// [package] を購入する。技は、先に [reserveActionCardMove] で控えた技を webhook が購入に結び付け、[watchActionCardPurchases] に届く。
  final Future<TicketPurchaseResult> Function({required Package package})
  purchaseActionCardPackage;

  /// `users/{uid}/actionCardPurchases` を、記録した順で流す。
  final Stream<List<ActionCardPurchase>> Function() watchActionCardPurchases;

  /// `moveRanks/current.rankByMoveID` (技の ID ごとのランク) を流す。表がまだ無い時は null。
  final Stream<Map<String, int>?> Function() watchMoveRanks;

  /// reserveActionCardMove を呼んで、値段を出したランク [rank] の [moveID] を買う前に控え、控えの ID を返す。
  /// 技の今のランクが [rank] と違えば控えずに [ActionCardMoveRankChangedException] を投げる。
  final Future<String> Function({required String moveID, required int rank})
  reserveActionCardMove;

  /// assignActionCardMove を呼んで、技に結び付いていない購入 [actionCardPurchaseID] に [moveID] を結び付ける。
  final Future<void> Function({
    required String actionCardPurchaseID,
    required String moveID,
  })
  assignActionCardMove;

  /// teachActionCardMove を呼んで図鑑の [monsterID] に [moveID] を覚えさせ、覚えさせた後の一覧を返す。
  final Future<List<String>> Function({
    required String monsterID,
    required String moveID,
  })
  teachActionCardMove;

  /// forgetActionCardMove を呼んで図鑑の [monsterID] から [moveID] を忘れさせ、忘れさせた後の一覧を返す。
  final Future<List<String>> Function({
    required String monsterID,
    required String moveID,
  })
  forgetActionCardMove;
}
