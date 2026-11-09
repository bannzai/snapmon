import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../features/capture/monster_generator.dart';
import '../features/session/session_store.dart';

// 生成チケットの購入 (RevenueCat の SDK) と残高の購読。残高に足すのはサーバーの webhook (functions/src/generation_tickets.ts) で、
// webhook はイベントの `app_user_id` を uid として読むため、SDK のユーザー ID は常に Firebase の uid に揃える。

/// iOS の RevenueCat の public API key (公開値)。`--dart-define` で渡す。空のビルドでは課金を無効にする。
const String _revenueCatPublicApiKeyIos = String.fromEnvironment(
  'REVENUECAT_PUBLIC_API_KEY_IOS',
);

/// Android の RevenueCat の public API key (公開値)。`--dart-define` で渡す。空のビルドでは課金を無効にする。
const String _revenueCatPublicApiKeyAndroid = String.fromEnvironment(
  'REVENUECAT_PUBLIC_API_KEY_ANDROID',
);

/// この端末で使う public API key。Web と鍵を渡していないビルドでは空で、SDK を初期化しない。
String _revenueCatPublicApiKey() {
  if (kIsWeb) {
    return '';
  }
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => _revenueCatPublicApiKeyIos,
    TargetPlatform.android => _revenueCatPublicApiKeyAndroid,
    _ => '',
  };
}

/// 最後に始めた SDK のユーザーの切り替え。configure と logIn を重ねて呼ばないため、前の完了を待って順に行う。
Future<void> _latestPurchasesUserSync = Future<void>.value();

/// SDK のユーザーを [uid] に揃える (何度呼んでも同じ)。[uid] が null ならログアウトする。課金が無効なビルドでは何もしない。
Future<void> _syncPurchasesUser({required String? uid}) =>
    _latestPurchasesUserSync = _latestPurchasesUserSync
        .catchError((Object _) {})
        .then((_) => _applyPurchasesUser(uid: uid));

/// [_syncPurchasesUser] の本体。前の切り替えが終わってから呼ぶ。
Future<void> _applyPurchasesUser({required String? uid}) async {
  final publicApiKey = _revenueCatPublicApiKey();
  if (publicApiKey.isEmpty) {
    return;
  }
  if (!await Purchases.isConfigured) {
    if (uid != null) {
      await Purchases.configure(
        PurchasesConfiguration(publicApiKey)..appUserID = uid,
      );
    }
    return;
  }
  if (uid == null) {
    if (!await Purchases.isAnonymous) {
      await Purchases.logOut();
    }
    return;
  }
  if (await Purchases.appUserID != uid) {
    await Purchases.logIn(uid);
  }
}

/// ログインの状態 ([sessionStore]) に SDK のユーザーを追従させる。アプリの起動時に 1 回だけ呼ぶ。
/// 失敗しても購入の前 ([fetchTicketPackagesWithRevenueCat]・[purchaseTicketPackageWithRevenueCat]) にもう一度揃える。
void connectPurchasesWhileSignedIn({required SessionStore sessionStore}) {
  void followSignedInUid() => unawaited(
    _syncPurchasesUser(
      uid: sessionStore.uid,
    ).catchError((Object error) => debugPrint(error.toString())),
  );
  sessionStore.addListener(followSignedInUid);
  followSignedInUid();
}

/// 生成チケットの package の `lookup_key` の接頭辞 (`revenuecat/config.json` の `ticket10`・`ticket30`)。
/// 同じ offering に Action Card の package (`actioncard_rank*`) も入るため、生成チケットの購入画面に出す package をこれで選ぶ。
const String _generationTicketPackageIdentifierPrefix = 'ticket';

/// [packages] のうち生成チケットの package だけを、並びを保って返す。
List<Package> generationTicketPackages({required List<Package> packages}) =>
    packages
        .where(
          (package) => package.identifier.startsWith(
            _generationTicketPackageIdentifierPrefix,
          ),
        )
        .toList();

/// current offering の生成チケットの package を返す ([MonsterGenerator.fetchTicketPackages])。課金が無効なビルド・ログインしていない時は空。
/// 閉じている間は package の無い offering が current のため空になる (documents/DIRECTION.md「決めたこと」)。
Future<List<Package>> fetchTicketPackagesWithRevenueCat() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (_revenueCatPublicApiKey().isEmpty || uid == null) {
    return const [];
  }
  await _syncPurchasesUser(uid: uid);
  return generationTicketPackages(
    packages:
        (await Purchases.getOfferings()).current?.availablePackages ?? const [],
  );
}

/// [package] を購入する ([MonsterGenerator.purchaseTicketPackage])。ログインしていない時は webhook が残高を足す先が無いため [StateError] を投げる。
Future<TicketPurchaseResult> purchaseTicketPackageWithRevenueCat({
  required Package package,
}) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    throw StateError('ログインしていないため購入できません');
  }
  await _syncPurchasesUser(uid: uid);
  try {
    await Purchases.purchase(PurchaseParams.package(package));
    return TicketPurchaseResult.purchased;
  } on PlatformException catch (error) {
    return switch (PurchasesErrorHelper.getErrorCode(error)) {
      PurchasesErrorCode.purchaseCancelledError =>
        TicketPurchaseResult.cancelled,
      PurchasesErrorCode.paymentPendingError => TicketPurchaseResult.pending,
      _ => throw error,
    };
  }
}

/// ストアの購入の状態を RevenueCat と同期する ([MonsterGenerator.syncTicketPurchases])。
Future<void> syncTicketPurchasesWithRevenueCat() async {
  await _syncPurchasesUser(uid: FirebaseAuth.instance.currentUser?.uid);
  await Purchases.restorePurchases();
}

/// `users/{uid}.generationTickets` を流す ([MonsterGenerator.watchGenerationTickets])。uid が変わったら読み直す。
/// フィールドが無いユーザーとログインしていない時は 0 (functions/src/generation/pipeline.ts と同じく、買ったことが無ければ 0 枚)。
/// uid が変わった時と読めない時も 0 を流す (流す値は uid を持たず、前のアカウントの枚数を今のアカウントのものとして残さないため)。
/// 残高の表示は補助で、購入と生成の判定はサーバーが行うため、0 が一時的に流れても実害は無い。
Stream<int> watchGenerationTicketsWithFirebase() {
  StreamSubscription<User?>? userSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  documentSubscription;
  late final StreamController<int> controller;
  controller = StreamController<int>(
    onListen: () {
      userSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        unawaited(documentSubscription?.cancel());
        documentSubscription = null;
        controller.add(0);
        if (user == null) {
          return;
        }
        documentSubscription = FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .snapshots()
            .listen(
              (snapshot) => controller.add(
                snapshot.data()?['generationTickets'] as int? ?? 0,
              ),
              onError: (Object _) => controller.add(0),
            );
      });
    },
    onCancel: () async {
      await documentSubscription?.cancel();
      await userSubscription?.cancel();
    },
  );
  return controller.stream;
}
