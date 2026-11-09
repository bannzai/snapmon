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

/// `users/{uid}.actionCardCredits` の値 [stored] をランクごとの残高にする。無いランクは 0 枚 (買っていない。
/// Functions の functions/src/action_card_rules.ts の `actionCardCreditsOf` と同じ)。
Map<int, int> actionCardCreditsOf({required Object? stored}) => {
  for (final rank in actionCardRanks)
    rank: switch (stored is Map ? stored['rank$rank'] : null) {
      final int count => count,
      _ => 0,
    },
};

/// `users/{uid}.actionCardCredits` を流す ([ActionCardClient.watchActionCardCredits])。
Stream<Map<int, int>> watchActionCardCreditsWithFirebase() =>
    _watchWhileSignedIn(
      emptyValue: actionCardCreditsOf(stored: null),
      watchSignedIn: ({required uid}) => FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .map(
            (snapshot) => actionCardCreditsOf(
              stored: snapshot.data()?['actionCardCredits'],
            ),
          ),
    );

/// `moveRanks/current.rankByMoveId` を流す ([ActionCardClient.watchMoveRanks])。表が無い時は null。
Stream<Map<String, int>?> watchMoveRanksWithFirebase() => _watchWhileSignedIn(
  emptyValue: null,
  watchSignedIn: ({required uid}) => FirebaseFirestore.instance
      .doc('moveRanks/current')
      .snapshots()
      .map(
        (snapshot) => switch (snapshot.data()?['rankByMoveId']) {
          final Map<String, dynamic> rankByMoveId => {
            for (final MapEntry(key: moveId, value: rank)
                in rankByMoveId.entries)
              moveId: rank as int,
          },
          _ => null,
        },
      ),
);

/// `users/{uid}/actionCards` の技の ID を、買い切った順 (`redeemedAt`) で流す ([ActionCardClient.watchOwnedActionCardMoveIds])。
Stream<List<String>> watchOwnedActionCardMoveIdsWithFirebase() =>
    _watchWhileSignedIn(
      emptyValue: const [],
      watchSignedIn: ({required uid}) => FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('actionCards')
          .orderBy('redeemedAt')
          .snapshots()
          .map(
            (snapshot) => [
              for (final document in snapshot.docs)
                document.data()['moveId'] as String,
            ],
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

/// redeemActionCard を呼ぶ ([ActionCardClient.redeemActionCard])。返す値は使った後の残高。
Future<Map<int, int>> redeemActionCardWithFirebase({
  required String moveId,
}) async => actionCardCreditsOf(
  stored: {
    for (final MapEntry(key: rankKey, value: count)
        in ((await _call(
                  name: 'redeemActionCard',
                  data: {'moveId': moveId},
                ))['actionCardCredits']!
                as Map<Object?, Object?>)
            .entries)
      rankKey! as String: count,
  },
);

/// teachActionCardMove・forgetActionCardMove の [name] を呼び、返った一覧を返す。
Future<List<String>> _callMonsterMove({
  required String name,
  required String monsterId,
  required String moveId,
}) async => [
  for (final actionCardMoveId
      in (await _call(
            name: name,
            data: {'monsterId': monsterId, 'moveId': moveId},
          ))['actionCardMoveIds']!
          as List<Object?>)
    actionCardMoveId! as String,
];

/// teachActionCardMove を呼ぶ ([ActionCardClient.teachActionCardMove])。
Future<List<String>> teachActionCardMoveWithFirebase({
  required String monsterId,
  required String moveId,
}) => _callMonsterMove(
  name: 'teachActionCardMove',
  monsterId: monsterId,
  moveId: moveId,
);

/// forgetActionCardMove を呼ぶ ([ActionCardClient.forgetActionCardMove])。
Future<List<String>> forgetActionCardMoveWithFirebase({
  required String monsterId,
  required String moveId,
}) => _callMonsterMove(
  name: 'forgetActionCardMove',
  monsterId: monsterId,
  moveId: moveId,
);
