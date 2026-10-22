import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/master/master_data.dart';
import '../features/age_gate/age_verified_session_store.dart';
import '../features/dex/dex_store.dart';
import '../features/dex/owned_monster.dart';
import '../master/master_repository.dart';

// 図鑑 (users/{uid}/monsters) と手持ち (users/{uid}/party/current) を Firestore から読み続け、DexStore に反映する。
// 図鑑はクライアントから書けず (Functions が生成で書く)、手持ちだけを書く (.claude/rules/firestore.md)。

/// [sessionStore] のログインが続く間、その uid の図鑑に [dexStore] を繋ぐ。
/// ログインした時 (起動時に済んでいれば今) に繋ぎ、uid が変わった・ログインを終えた時は前の uid の購読をやめて
/// [dexStore] を空の端末の図鑑 (定義は [localDefinitions]) に戻す (開発者メニューの年齢の確認のやり直しで uid が変わるため)。
/// 同じ uid の間は繋ぎ直さない (同じ購読を二重に作らないため)。
void connectDexToFirestoreWhileSignedIn({
  required AgeVerifiedSessionStore sessionStore,
  required DexStore dexStore,
  required MasterData localDefinitions,
}) {
  String? connectedUid;
  Future<void> Function()? disconnect;
  void followSignedInUid() {
    final uid = sessionStore.uid;
    if (uid == connectedUid) {
      return;
    }
    final previousDisconnect = disconnect;
    disconnect = null;
    if (previousDisconnect != null) {
      unawaited(previousDisconnect());
      dexStore.disconnectServer(definitions: localDefinitions);
    }
    connectedUid = uid;
    if (uid != null) {
      disconnect = connectDexToFirestore(
        firestore: FirebaseFirestore.instance,
        uid: uid,
        dexStore: dexStore,
      );
    }
  }

  sessionStore.addListener(followSignedInUid);
  followSignedInUid();
}

/// [uid] の図鑑・手持ちを [firestore] から読み続けて [dexStore] に反映し、手持ちの変更を保存するようにする。
/// 返す関数は購読をやめる。
///
/// 図鑑のモンスターは、参照する定義 (最新の master と、まだ読んでいないその場で作った定義) を読んでから反映する
/// (属性・技を引けないモンスターを画面に出さないため)。読み込みの失敗は [DexStore.reportServerError] に残す。
Future<void> Function() connectDexToFirestore({
  required FirebaseFirestore firestore,
  required String uid,
  required DexStore dexStore,
}) {
  final userDocument = firestore.collection('users').doc(uid);
  final partyDocument = userDocument.collection('party').doc('current');
  var isConnected = true;
  Map<String, dynamic>? latestMasterJson;
  final definitionJsonsById = <String, Map<String, dynamic>>{};
  // 最後に届いた図鑑。定義を読めずに反映できなかった図鑑を、読み直しの時に反映し直すために持つ
  // (Firestore は図鑑が変わるまで同じスナップショットを送り直さないため)
  List<OwnedMonster>? latestMonsters;

  Future<MasterData> definitionsFor({
    required List<OwnedMonster> monsters,
  }) async {
    // ログインの後に新しい版の master が投入され、その版で生まれたモンスターが届いた時は読み直す
    // (古い版には無い属性・技を引けなくなるため)
    if (needsLatestMasterFetch(
      cachedMasterJson: latestMasterJson,
      monsters: monsters,
    )) {
      latestMasterJson = (await fetchLatestMaster(
        firestore: firestore,
      ))?.data();
    }
    for (final definitionId in {
      for (final monster in monsters) ...monster.definitionIds,
    }) {
      if (!definitionJsonsById.containsKey(definitionId)) {
        final definitionJson = (await fetchDefinition(
          firestore: firestore,
          definitionId: definitionId,
        )).data();
        if (definitionJson == null) {
          throw StateError('定義 $definitionId が Firestore にありません');
        }
        definitionJsonsById[definitionId] = definitionJson;
      }
    }
    return buildDexDefinitions(
      latestMasterJson: latestMasterJson,
      definitionJsons: definitionJsonsById.values.toList(),
    );
  }

  dexStore.connectServer(
    // updatedAt は Rules が request.time と一致することを求める (firebase/firestore.rules の party/current)
    savePartyMonsterIds: ({required monsterIds}) => partyDocument.set({
      'monsterIds': monsterIds,
      'updatedAt': FieldValue.serverTimestamp(),
    }),
    refreshDefinitions: () async {
      latestMasterJson = (await fetchLatestMaster(
        firestore: firestore,
      ))?.data();
      final monsters = latestMonsters;
      final definitions = await definitionsFor(monsters: monsters ?? const []);
      if (isConnected) {
        dexStore.applyServerSnapshot(
          monsters: monsters,
          partyMonsterIds: null,
          definitions: definitions,
        );
      }
    },
  );

  // asyncMap は前の反映が済むまで次のスナップショットを待たせるため、古い図鑑が新しい図鑑を上書きしない
  final monstersSubscription = userDocument
      .collection('monsters')
      .orderBy('createdAt')
      .snapshots()
      .asyncMap((snapshot) async {
        final monsters = [
          for (final document in snapshot.docs)
            OwnedMonster.fromJson(json: document.data()),
        ];
        latestMonsters = monsters;
        final definitions = await definitionsFor(monsters: monsters);
        // 定義を読んでいる間に購読をやめた (ログインを終えた) 時は、前の uid の図鑑を反映しない
        if (isConnected) {
          dexStore.applyServerSnapshot(
            monsters: monsters,
            partyMonsterIds: null,
            definitions: definitions,
          );
        }
      })
      .handleError((Object error) => dexStore.reportServerError(error: error))
      .listen(null);
  final partySubscription = partyDocument.snapshots().listen(
    (snapshot) => dexStore.applyServerSnapshot(
      monsters: null,
      partyMonsterIds: [
        for (final monsterId
            in snapshot.data()?['monsterIds'] as List<dynamic>? ?? [])
          monsterId as String,
      ],
      definitions: null,
    ),
    onError: (Object error) => dexStore.reportServerError(error: error),
  );
  return () async {
    isConnected = false;
    await monstersSubscription.cancel();
    await partySubscription.cancel();
  };
}
