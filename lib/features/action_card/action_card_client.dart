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

/// [moveRank] の技を買い切る時に使うカードのランク。技のランク以上で残高のあるうち一番安いランクで、無ければ null。
/// Functions の redeemActionCard が使うカードの決め方 (functions/src/action_card_rules.ts の `creditRankToRedeem`) と同じで、
/// 買い切る前にどのカードを使うかを出すために使う。
int? creditRankToRedeem({
  required int moveRank,
  required Map<int, int> creditsByRank,
}) {
  for (final creditRank in actionCardRanks) {
    if (creditRank >= moveRank && (creditsByRank[creditRank] ?? 0) >= 1) {
      return creditRank;
    }
  }
  return null;
}

/// 買い切りを、確かめる画面で出したカードのランクと使うカードのランクが違うため断られた (確かめている間に技のランクか残高が変わった)。
/// redeemActionCard が failed-precondition の `details` に今使うランクを入れて断った時に投げる (functions/src/action_cards.ts。#277)。
class ActionCardCreditRankChangedException implements Exception {
  /// 断られた時の今使うランク [creditRank] と残高 [creditsByRank] を持つ。
  const ActionCardCreditRankChangedException({
    required this.creditRank,
    required this.creditsByRank,
  });

  /// 今の残高と技のランクで使うカードのランク。確かめ直す画面に出す。
  final int creditRank;

  /// 断られた時の残高 (キーはランク)。
  final Map<int, int> creditsByRank;

  @override
  String toString() =>
      'ActionCardCreditRankChangedException(creditRank: $creditRank)';
}

/// Action Card の表示の切り替え・商品・残高・技のランク・買い切った技の購読と、購入・買い切り・覚えさせる・忘れさせるを呼ぶ関数の組。
/// 画面を Firebase・RevenueCat と切り離してテストするため、実体 (lib/firebase/action_cards.dart) は main.dart から渡す。
/// 購読は uid が変わるたびに空の値 (残高 0・技なし・隠す) から流し直す (前のアカウントの値を今のアカウントのものとして出さないため)。
class ActionCardClient {
  /// 関数の組を作る。
  const ActionCardClient({
    required this.isPurchaseSupported,
    required this.watchActionCardsVisible,
    required this.fetchActionCardPackages,
    required this.purchaseActionCardPackage,
    required this.watchActionCardCredits,
    required this.watchMoveRanks,
    required this.watchOwnedActionCardMoveIds,
    required this.redeemActionCard,
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

  /// [package] を購入する。残高はストアの購入の後に webhook が足し、[watchActionCardCredits] に届く。
  final Future<TicketPurchaseResult> Function({required Package package})
  purchaseActionCardPackage;

  /// `users/{uid}.actionCardCredits` をランクごとの残高 (キーはランク。無いランクは 0 枚) で流す。
  final Stream<Map<int, int>> Function() watchActionCardCredits;

  /// `moveRanks/current.rankByMoveId` (技の ID ごとのランク) を流す。表がまだ無い時は null。
  final Stream<Map<String, int>?> Function() watchMoveRanks;

  /// `users/{uid}/actionCards` の技の ID を、買い切った順で流す。
  final Stream<List<String>> Function() watchOwnedActionCardMoveIds;

  /// redeemActionCard を呼んで [moveId] を、確かめる画面で出したランク [creditRank] のカードで買い切り、使った後の残高を返す。
  /// 使うカードのランクが [creditRank] と違えば買い切らずに [ActionCardCreditRankChangedException] を投げる。
  final Future<Map<int, int>> Function({
    required String moveId,
    required int creditRank,
  })
  redeemActionCard;

  /// teachActionCardMove を呼んで図鑑の [monsterId] に [moveId] を覚えさせ、覚えさせた後の一覧を返す。
  final Future<List<String>> Function({
    required String monsterId,
    required String moveId,
  })
  teachActionCardMove;

  /// forgetActionCardMove を呼んで図鑑の [monsterId] から [moveId] を忘れさせ、忘れさせた後の一覧を返す。
  final Future<List<String>> Function({
    required String monsterId,
    required String moveId,
  })
  forgetActionCardMove;
}
