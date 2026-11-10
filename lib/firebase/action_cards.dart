import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../features/action_card/action_card_client.dart';
import 'session.dart';

// Action Card の Firestore の購読と Functions (functions/src/action_cards.ts) の呼び出し。構造は .claude/rules/firestore.md。

/// ログインのたびに [watchSignedIn] の購読を始め直し、ログインが変わるたび (ログアウトを含む) に先に [emptyValue] を流す
/// (流す値は uid を持たず、前のアカウントの値を今のアカウントのものとして残さないため)。読めない時も [emptyValue] を流す。
Stream<T> _watchWhileSignedIn<T>({
  required T emptyValue,
  required Stream<T> Function({required String uid}) watchSignedIn,
}) {
  StreamSubscription<User?>? userSubscription;
  StreamSubscription<T>? valueSubscription;
  late final StreamController<T> controller;
  controller = StreamController<T>(
    onListen: () {
      userSubscription = FirebaseAuth.instance.authStateChanges().listen((
        user,
      ) {
        unawaited(valueSubscription?.cancel());
        valueSubscription = null;
        controller.add(emptyValue);
        if (user == null) {
          return;
        }
        valueSubscription = watchSignedIn(uid: user.uid).listen(
          controller.add,
          onError: (Object _) => controller.add(emptyValue),
        );
      });
    },
    onCancel: () async {
      await valueSubscription?.cancel();
      await userSubscription?.cancel();
    },
  );
  return controller.stream;
}

/// `config/features.actionCardsVisible` を流す ([ActionCardClient.watchActionCardsVisible])。
/// Rules はログインを求めるため、ログインしていない時は false (既定は出さない。documents/game-rules.md「Action Card」)。
Stream<bool> watchActionCardsVisibleWithFirebase() => _watchWhileSignedIn(
  emptyValue: false,
  watchSignedIn: ({required uid}) => FirebaseFirestore.instance
      .doc('config/features')
      .snapshots()
      .map(
        (snapshot) => snapshot.data()?['actionCardsVisible'] as bool? ?? false,
      ),
);

/// `users/{uid}/actionCardPurchases` を記録した順 (`createdAt`) で流す ([ActionCardClient.watchActionCardPurchases])。
/// `moveID` のフィールドが無い購入 (#290 より前) は技に結び付いていない購入として読む。
Stream<List<ActionCardPurchase>> watchActionCardPurchasesWithFirebase() =>
    _watchWhileSignedIn(
      emptyValue: const [],
      watchSignedIn: ({required uid}) => FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('actionCardPurchases')
          .orderBy('createdAt')
          .snapshots()
          .map(
            (snapshot) => [
              for (final document in snapshot.docs)
                ActionCardPurchase(
                  actionCardPurchaseID: document.id,
                  productID: document.data()['productID'] as String,
                  moveID: document.data()['moveID'] as String?,
                  actionCardMoveReservationID:
                      document.data()['actionCardMoveReservationID'] as String?,
                  createdAt: (document.data()['createdAt'] as Timestamp)
                      .toDate(),
                  moveAssignedAt:
                      (document.data()['moveAssignedAt'] as Timestamp?)
                          ?.toDate(),
                ),
            ],
          ),
    );

/// `actionCardProducts/current.productIDByMoveID` を流す ([ActionCardClient.watchActionCardProductIDByMoveID])。
/// 表が無い時は null。
Stream<Map<String, String>?> watchActionCardProductIDByMoveIDWithFirebase() =>
    _watchWhileSignedIn(
      emptyValue: null,
      watchSignedIn: ({required uid}) => FirebaseFirestore.instance
          .doc('actionCardProducts/current')
          .snapshots()
          .map(
            (snapshot) => switch (snapshot.data()?['productIDByMoveID']) {
              final Map<String, dynamic> productIDByMoveID => {
                for (final MapEntry(key: moveID, value: productID)
                    in productIDByMoveID.entries)
                  moveID: productID as String,
              },
              _ => null,
            },
          ),
    );

/// Functions の callable [name] を [data] で呼び、返った値を返す。
Future<Map<Object?, Object?>> _call({
  required String name,
  required Object? data,
}) async =>
    (await FirebaseFunctions.instanceFor(
          region: functionsRegion,
        ).httpsCallable(name).call<Object?>(data)).data!
        as Map<Object?, Object?>;

/// reserveActionCardMove を呼ぶ ([ActionCardClient.reserveActionCardMove])。返す値は控えの ID。
/// 技を今買える商品が [productID] と違うと断られた時 (failed-precondition の `details` に今の商品の ID がある) は
/// [ActionCardMoveProductChangedException] にして投げ、それ以外の失敗はそのまま投げる。
Future<String> reserveActionCardMoveWithFirebase({
  required String moveID,
  required String productID,
}) async {
  try {
    return (await _call(
          name: 'reserveActionCardMove',
          data: {'moveID': moveID, 'productID': productID},
        ))['actionCardMoveReservationID']!
        as String;
  } on FirebaseFunctionsException catch (error) {
    if (error.details case {
      'productID': final String changedProductID,
    } when error.code == 'failed-precondition') {
      throw ActionCardMoveProductChangedException(productID: changedProductID);
    }
    rethrow;
  }
}

/// assignActionCardMove を呼ぶ ([ActionCardClient.assignActionCardMove])。
Future<void> assignActionCardMoveWithFirebase({
  required String actionCardPurchaseID,
  required String moveID,
}) => _call(
  name: 'assignActionCardMove',
  data: {'actionCardPurchaseID': actionCardPurchaseID, 'moveID': moveID},
);

/// teachActionCardMove・forgetActionCardMove の [name] を呼び、返った一覧を返す。
Future<List<String>> _callMonsterMove({
  required String name,
  required String monsterID,
  required String moveID,
}) async => [
  for (final actionCardMoveID
      in (await _call(
            name: name,
            data: {'monsterID': monsterID, 'moveID': moveID},
          ))['actionCardMoveIDs']!
          as List<Object?>)
    actionCardMoveID! as String,
];

/// teachActionCardMove を呼ぶ ([ActionCardClient.teachActionCardMove])。
Future<List<String>> teachActionCardMoveWithFirebase({
  required String monsterID,
  required String moveID,
}) => _callMonsterMove(
  name: 'teachActionCardMove',
  monsterID: monsterID,
  moveID: moveID,
);

/// forgetActionCardMove を呼ぶ ([ActionCardClient.forgetActionCardMove])。
Future<List<String>> forgetActionCardMoveWithFirebase({
  required String monsterID,
  required String moveID,
}) => _callMonsterMove(
  name: 'forgetActionCardMove',
  monsterID: monsterID,
  moveID: moveID,
);
