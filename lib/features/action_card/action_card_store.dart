import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../sample/sample_action_cards.dart';
import '../capture/monster_generator.dart';
import '../dex/dex_store.dart';
import 'action_card_client.dart';

/// package の読み込みが失敗した後に読み直すまでの時間。通信の一時的な失敗 (電波の切り替わり・RevenueCat の一時的な失敗) が
/// 戻るのを待ちつつ、入口が出ないまま利用者が待たされすぎない長さにした。読めるまで繰り返す。
const Duration _packagesRetryDelay = Duration(seconds: 30);

/// Action Card の表示の切り替え・売っている package・購入・技のランクの、最後に読めた値。
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

  /// 購読し直した回数。呼び出しの途中で購読し直した (アカウントが変わった) 時に、前のアカウントの結果を反映しないために比べる。
  int _sessionGeneration = 0;

  /// `config/features.actionCardsVisible`。
  bool _isActionCardsVisible = false;

  /// 最後に読めた売っている Action Card の package (ランクの順)。
  List<Package> _packages = const [];

  /// [refreshPackages] を始めた回数。読み込みごとの番号にする。
  int _packagesRequestNumber = 0;

  /// 一覧に反映した読み込みの番号。読み込みが並んで走った時に、これより後に始めた読み込みの成功だけを反映する
  /// (先に始めた読み込みの成功が後から返って新しい一覧を古い一覧で上書きしないため。失敗はどの読み込みの結果も捨てない)。
  int _appliedPackagesRequestNumber = 0;

  /// 途中の読み込みの数。0 の時だけ [refreshPackagesIfMissing] が読み込みを始める (同じ読み込みを重ねないため)。
  int _loadingPackagesCount = 0;

  /// 今のアカウントで package を一度でも読めたか (売っていない空の結果を含む)。読めた後は [refreshPackagesIfMissing] が読み直さない。
  bool _hasLoadedPackages = false;

  /// 読み込みの失敗の後の読み直しのタイマー。読めるまで [_packagesRetryDelay] ごとに読み直す。
  Timer? _packagesRetryTimer;

  /// Action Card の購入 (記録した順)。
  List<ActionCardPurchase> _purchases = const [];

  /// 技の ID ごとのランク。表がまだ無い時は null。
  Map<String, int>? _rankByMoveId;

  /// 売っている Action Card の package (ランクの順)。
  List<Package> get packages => _packages;

  /// Action Card の購入 (記録した順)。購入画面が、控えた技の購入が届いたかを見る。
  List<ActionCardPurchase> get purchases => _purchases;

  /// 技の ID ごとのランク。表がまだ無い時 (最初のデプロイの直後) は null で、購入と選び直しを受け付けない。
  Map<String, int>? get rankByMoveId => _rankByMoveId;

  /// 買い切った技の ID (技を結び付けた順)。購入の `moveID` から出し、別に持たない (#290)。
  List<String> get ownedMoveIds => [
    for (final purchase
        in [
          for (final purchase in _purchases)
            if (purchase.moveID != null) purchase,
        ]..sort(
          (left, right) => (left.moveAssignedAt ?? left.createdAt).compareTo(
            right.moveAssignedAt ?? right.createdAt,
          ),
        ))
      purchase.moveID!,
  ];

  /// 技に結び付いていない購入 (記録した順)。技を選んでから購入が届くまでの間にランクが上がった時などに残り、利用者が技を選び直す。
  List<ActionCardPurchase> get unassignedPurchases => [
    for (final purchase in _purchases)
      if (purchase.moveID == null) purchase,
  ];

  /// 購入の入口 (プロフィール・図鑑の詳細のボタンと購入の画面) を出すか。課金を使えるビルドで、`actionCardsVisible` が true で、
  /// 売っている package がある時だけ true (issue #273 の表示の条件)。
  bool get isPurchaseEntryVisible =>
      client.isPurchaseSupported() &&
      _isActionCardsVisible &&
      _packages.isNotEmpty;

  /// Action Card の画面の入口を出すか。購入の入口を出す時と、購入が 1 件でもある時 (買い切った技と技に結び付いていない購入。
  /// 隠している間や商品を読めない間も、払ったものを使えなくしないため)。
  bool get isScreenEntryVisible =>
      isPurchaseEntryVisible || _purchases.isNotEmpty;

  /// 空の値に戻してから、[client] の購読をすべて始め直す。
  void _resubscribe() {
    _sessionGeneration += 1;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _packagesRetryTimer?.cancel();
    _packagesRetryTimer = null;
    _isActionCardsVisible = false;
    _packages = const [];
    _hasLoadedPackages = false;
    // 前のアカウントの途中の読み込みは、返ってもアカウントが違うため件数を減らさない。数え直しをここで 0 から始める
    _loadingPackagesCount = 0;
    _purchases = const [];
    _rankByMoveId = null;
    notifyListeners();
    _subscriptions
      ..add(
        client.watchActionCardsVisible().listen((isActionCardsVisible) {
          _isActionCardsVisible = isActionCardsVisible;
          notifyListeners();
          refreshPackagesIfMissing();
        }, onError: (Object _) {}),
      )
      ..add(
        client.watchActionCardPurchases().listen((purchases) {
          _purchases = purchases;
          notifyListeners();
        }, onError: (Object _) {}),
      )
      ..add(
        client.watchMoveRanks().listen((rankByMoveId) {
          _rankByMoveId = rankByMoveId;
          notifyListeners();
        }, onError: (Object _) {}),
      );
  }

  /// 売っている package を読み直す。売っていない (空が返った) 時は空にして購入の入口を出さない。
  /// 読めなかった (例外) 時は前に読めた一覧を残し、まだ一度も読めていなければ [_packagesRetryDelay] の後に読み直す
  /// (通信の一時的な失敗で入口が消え、入口の画面を開き直すまで戻らなくなるため。残すのは前に取得した実際の値で、
  /// 取得できなかった値を作って出すことにはならない)。
  /// offering の切り替えはアプリの再リリース無しで行うため、Action Card の画面を開くたびにも呼ぶ。
  Future<void> refreshPackages() async {
    final sessionGeneration = _sessionGeneration;
    final packagesRequestNumber = ++_packagesRequestNumber;
    _loadingPackagesCount += 1;
    final List<Package> packages;
    try {
      packages = await client.fetchActionCardPackages();
    } catch (_) {
      if (sessionGeneration == _sessionGeneration) {
        _loadingPackagesCount -= 1;
        _schedulePackagesRetry();
      }
      return;
    }
    if (sessionGeneration != _sessionGeneration) {
      return;
    }
    _loadingPackagesCount -= 1;
    if (packagesRequestNumber <= _appliedPackagesRequestNumber) {
      return;
    }
    _appliedPackagesRequestNumber = packagesRequestNumber;
    _hasLoadedPackages = true;
    _packagesRetryTimer?.cancel();
    _packagesRetryTimer = null;
    _packages = [
      for (final rank in actionCardRanks)
        ...packages.where(
          (package) => actionCardRankOfPackage(package: package) == rank,
        ),
    ];
    notifyListeners();
  }

  /// 表示の切り替えが true で課金を使えるのに、今のアカウントでまだ package を読めておらず、読み込みの途中でもない時だけ読み込む。
  /// 表示の切り替えが届いた時と、入口を出す画面 (プロフィール・図鑑の詳細) がストアの値の変化を受けるたびに呼ぶ
  /// (読めた後と途中は何もしないため、何度呼んでも読み込みは重ならない)。
  void refreshPackagesIfMissing() {
    if (_isActionCardsVisible &&
        client.isPurchaseSupported() &&
        !_hasLoadedPackages &&
        _loadingPackagesCount == 0) {
      unawaited(refreshPackages());
    }
  }

  /// まだ一度も package を読めていない時に、[_packagesRetryDelay] の後に [refreshPackagesIfMissing] を呼ぶタイマーを置く。
  void _schedulePackagesRetry() {
    if (_hasLoadedPackages || _packagesRetryTimer != null) {
      return;
    }
    _packagesRetryTimer = Timer(_packagesRetryDelay, () {
      _packagesRetryTimer = null;
      refreshPackagesIfMissing();
    });
  }

  /// 値段を出したランク [rank] の [moveID] を買う前に控え、控えの ID を返す ([ActionCardClient.reserveActionCardMove])。
  Future<String> reserveMove({required String moveID, required int rank}) =>
      client.reserveActionCardMove(moveID: moveID, rank: rank);

  /// [package] を購入する ([ActionCardClient.purchaseActionCardPackage])。先に [reserveMove] で控えた技が、届いた購入に結び付く。
  Future<TicketPurchaseResult> purchase({required Package package}) =>
      client.purchaseActionCardPackage(package: package);

  /// 技に結び付いていない購入 [actionCardPurchaseID] に [moveID] を結び付ける ([ActionCardClient.assignActionCardMove])。
  /// 結果は購入の購読で届く。
  Future<void> assignMove({
    required String actionCardPurchaseID,
    required String moveID,
  }) => client.assignActionCardMove(
    actionCardPurchaseID: actionCardPurchaseID,
    moveID: moveID,
  );

  @override
  void dispose() {
    _packagesRetryTimer?.cancel();
    _sessionChanges.removeListener(_resubscribe);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}

/// [actionCardStore] の技のランクの表と買い切った技のうち、[dexStore] の定義に無い技があれば、定義を最新の master から読み直す。
/// 技のランクの表と買い切った技は最新の版の master の技で、ログインの後に新しい版が投入されると端末の定義に無い技が届くため
/// (図鑑の読み直しは図鑑のモンスターの技しか見ない。lib/master/master_repository.dart の `needsLatestMasterFetch`)。
/// [requestedMoveIds] は読み直しを頼んだ技で、master に無い技のために何度も読み直さないよう、呼び出し側が画面ごとに持つ。
/// 読み直しの失敗は無視する (無い技は一覧に出さないままにする)。
Future<void> refreshDefinitionsForActionCardMoves({
  required ActionCardStore actionCardStore,
  required DexStore dexStore,
  required Set<String> requestedMoveIds,
}) async {
  final missingMoveIds =
      {
        ...?actionCardStore.rankByMoveId?.keys,
        ...actionCardStore.ownedMoveIds,
      }.difference({
        for (final move in dexStore.definitions.moves) move.id,
        ...requestedMoveIds,
      });
  if (missingMoveIds.isEmpty) {
    return;
  }
  requestedMoveIds.addAll(missingMoveIds);
  await dexStore.refreshDefinitions().catchError((Object _) {});
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
