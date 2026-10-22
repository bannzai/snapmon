import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/master/master_data.dart';
import '../features/age_gate/age_verified_session_store.dart';
import '../features/dex/dex_store.dart';
import '../features/dex/owned_monster.dart';
import '../master/master_repository.dart';

// 図鑑 (users/{uid}/monsters) と手持ち (users/{uid}/party/current) を Firestore から読み続け、DexStore に反映する。
// 図鑑はクライアントから書けず (Functions が生成で書く)、手持ちだけを書く (.claude/rules/firestore.md)。

/// [sessionStore] のログインが済んだら (済んでいれば今)、その uid の図鑑に [dexStore] を繋ぐ。
/// 繋ぐのは 1 回だけで、後から何度ログインの状態が変わっても繋ぎ直さない (同じ購読を二重に作らないため)。
void connectDexToFirestoreAfterSignIn({
  required AgeVerifiedSessionStore sessionStore,
  required DexStore dexStore,
}) {
  var isConnected = false;
  void connectIfSignedIn() {
    final uid = sessionStore.uid;
    if (isConnected || uid == null) {
      return;
    }
    isConnected = true;
    connectDexToFirestore(
      firestore: FirebaseFirestore.instance,
      uid: uid,
      dexStore: dexStore,
    );
  }

  sessionStore.addListener(connectIfSignedIn);
  connectIfSignedIn();
}

/// [uid] の図鑑・手持ちを [firestore] から読み続けて [dexStore] に反映し、手持ちの変更を保存するようにする。
///
/// 図鑑のモンスターは、参照する定義 (最新の master と、まだ読んでいないその場で作った定義) を読んでから反映する
/// (属性・技を引けないモンスターを画面に出さないため)。読み込みの失敗は [DexStore.reportServerError] に残す。
void connectDexToFirestore({
  required FirebaseFirestore firestore,
  required String uid,
  required DexStore dexStore,
}) {
  final userDocument = firestore.collection('users').doc(uid);
  final partyDocument = userDocument.collection('party').doc('current');
  dexStore.connectServer(
    // updatedAt は Rules が request.time と一致することを求める (firebase/firestore.rules の party/current)
    savePartyMonsterIds: ({required monsterIds}) => partyDocument.set({
      'monsterIds': monsterIds,
      'updatedAt': FieldValue.serverTimestamp(),
    }),
  );

  Map<String, dynamic>? latestMasterJson;
  final definitionJsonsById = <String, Map<String, dynamic>>{};
  Future<MasterData> definitionsFor({
    required List<OwnedMonster> monsters,
  }) async {
    latestMasterJson ??= (await fetchLatestMaster(firestore: firestore))?.data();
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

  // asyncMap は前の反映が済むまで次のスナップショットを待たせるため、古い図鑑が新しい図鑑を上書きしない
  userDocument
      .collection('monsters')
      .orderBy('createdAt')
      .snapshots()
      .asyncMap((snapshot) async {
        final monsters = [
          for (final document in snapshot.docs)
            OwnedMonster.fromJson(json: document.data()),
        ];
        dexStore.applyServerSnapshot(
          monsters: monsters,
          partyMonsterIds: null,
          definitions: await definitionsFor(monsters: monsters),
        );
      })
      .handleError((Object error) => dexStore.reportServerError(error: error))
      .listen(null);
  partyDocument.snapshots().listen(
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
}
