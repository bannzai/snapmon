import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../sample/sample_action_cards.dart';
import '../capture/monster_generator.dart';
import 'action_card_client.dart';

/// Action Card の表示の切り替え・売っている package・残高・技のランク・買い切った技の、最後に読めた値。
/// 図鑑の詳細・プロフィール・Action Card の画面が同じ値を見るため、アプリに 1 つ置いて [ActionCardScope] で配る。
class ActionCardStore extends ChangeNotifier {
  /// [client] で購読を始める。[sessionChanges] が知らせるたびに (ログイン・始め直し・データの引き継ぎ) 空の値から購読し直す。
  /// [sampleActionCards] は DEBUG ビルドでログインを飛ばした時に [client] の代わりになる端末だけの見本で、開発者メニューが操作する
  /// (release ビルドでは null)。
  ActionCardStore({
    required this.client,
    required Listenable sessionChanges,
    required this.sampleActionCards,
  }) : _sessionChanges = sessionChanges {
    _sessionChanges.addListener(_resubscribe);
    _resubscribe();
  }

  /// 購読と呼び出しに使う関数の組。
  final ActionCardClient client;

  /// 開発者メニューが操作する端末だけの見本。release ビルドでは null。
  final SampleActionCards? sampleActionCards;

  /// 購読し直す合図。
  final Listenable _sessionChanges;

  /// 購読の一覧。購読し直す時にすべて止める。
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// `config/features.actionCardsVisible`。
  bool _isActionCardsVisible = false;

  /// 最後に読めた売っている Action Card の package (ランクの順)。
  List<Package> _packages = const [];

  /// ランクごとの残高。
  Map<int, int> _creditsByRank = const {};

  /// 技の ID ごとのランク。表がまだ無い時は null。
  Map<String, int>? _rankByMoveId;

  /// 買い切った技の ID (買い切った順)。
  List<String> _ownedMoveIds = const [];

  /// 売っている Action Card の package (ランクの順)。
  List<Package> get packages => _packages;

  /// ランクごとの残高 (無いランクは 0 枚)。
  Map<int, int> get creditsByRank => _creditsByRank;

  /// 技の ID ごとのランク。表がまだ無い時 (最初のデプロイの直後) は null で、買い切りと購入を受け付けない。
  Map<String, int>? get rankByMoveId => _rankByMoveId;

  /// 買い切った技の ID (買い切った順)。
  List<String> get ownedMoveIds => _ownedMoveIds;

  /// 購入の入口 (プロフィール・図鑑の詳細のボタンと購入の画面) を出すか。課金を使えるビルドで、`actionCardsVisible` が true で、
  /// 売っている package がある時だけ true (issue #273 の表示の条件)。
  bool get isPurchaseEntryVisible =>
      client.isPurchaseSupported() &&
      _isActionCardsVisible &&
      _packages.isNotEmpty;

  /// Action Card の画面の入口を出すか。購入の入口を出す時と、買い切った技を持っている時 (隠している間も、買ったものを使えなくしないため)。
  bool get isScreenEntryVisible =>
      isPurchaseEntryVisible || _ownedMoveIds.isNotEmpty;

  /// 空の値に戻してから、[client] の購読をすべて始め直す。
  void _resubscribe() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _isActionCardsVisible = false;
    _packages = const [];
    _creditsByRank = const {};
    _rankByMoveId = null;
    _ownedMoveIds = const [];
    notifyListeners();
    _subscriptions
      ..add(
        client.watchActionCardsVisible().listen((isActionCardsVisible) {
          _isActionCardsVisible = isActionCardsVisible;
          notifyListeners();
          if (isActionCardsVisible) {
            unawaited(refreshPackages());
          }
        }, onError: (Object _) {}),
      )
      ..add(
        client.watchActionCardCredits().listen((creditsByRank) {
          _creditsByRank = creditsByRank;
          notifyListeners();
        }, onError: (Object _) {}),
      )
      ..add(
        client.watchMoveRanks().listen((rankByMoveId) {
          _rankByMoveId = rankByMoveId;
          notifyListeners();
        }, onError: (Object _) {}),
      )
      ..add(
        client.watchOwnedActionCardMoveIds().listen((ownedMoveIds) {
          _ownedMoveIds = ownedMoveIds;
          notifyListeners();
        }, onError: (Object _) {}),
      );
  }

  /// 売っている package を読み直す。読めない時は売っていない時と同じく空にする (購入の入口を出さない)。
  /// offering の切り替えはアプリの再リリース無しで行うため、Action Card の画面を開くたびにも呼ぶ。
  Future<void> refreshPackages() async {
    final packages = await client.fetchActionCardPackages().catchError(
      (Object _) => const <Package>[],
    );
    _packages = [
      for (final rank in actionCardRanks)
        ...packages.where(
          (package) => actionCardRankOfPackage(package: package) == rank,
        ),
    ];
    notifyListeners();
  }

  /// [package] を購入する ([ActionCardClient.purchaseActionCardPackage])。
  Future<TicketPurchaseResult> purchase({required Package package}) =>
      client.purchaseActionCardPackage(package: package);

  /// [moveId] を買い切り、返った残高を購読の値が届く前に出す。
  Future<void> redeem({required String moveId}) async {
    _creditsByRank = await client.redeemActionCard(moveId: moveId);
    if (!_ownedMoveIds.contains(moveId)) {
      _ownedMoveIds = [..._ownedMoveIds, moveId];
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sessionChanges.removeListener(_resubscribe);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

/// [ActionCardStore] を配る範囲。アプリは Navigator の外に置き、push した画面からも引けるようにする。
class ActionCardScope extends InheritedNotifier<ActionCardStore> {
  /// [actionCardStore] を使う範囲を作る。
  const ActionCardScope({
    super.key,
    required ActionCardStore actionCardStore,
    required super.child,
  }) : super(notifier: actionCardStore);

  /// [context] から見える [ActionCardStore]。値の変化を build で追うため依存として登録する。
  /// 無い時 (Action Card を扱わない画面のテスト) は null で、呼び出し側は Action Card の表示を出さない。
  static ActionCardStore? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ActionCardScope>()?.notifier;
}
