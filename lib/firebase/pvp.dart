import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../domain/battle/battle_state.dart';
import '../domain/master/master_data.dart';
import '../features/opponent/pvp_battle.dart';
import '../features/opponent/pvp_client.dart';
import '../features/opponent/pvp_opponent.dart';
import '../features/opponent/report_reason.dart';
import '../master/master_repository.dart';
import 'session.dart';

// 他の利用者との対戦の Functions (functions/src/pvp.ts・pvp_battle.ts) の呼び出しと、人との対戦の状態・自分の戦績の読み込み。

/// ログインしていれば、その uid を返す。無ければ null
/// (Functions と Rules がログインの無い呼び出しを拒否するため。DEBUG ビルドでログインを飛ばした時に当たる)。
String? signedInUIDWithFirebase() => FirebaseAuth.instance.currentUser?.uid;

/// Functions の callable [name] を [data] で呼び、返った値を返す。
Future<Map<Object?, Object?>> _call({
  required String name,
  required Object? data,
}) async =>
    (await FirebaseFunctions.instanceFor(
          region: functionsRegion,
        ).httpsCallable(name).call<Object?>(data)).data!
        as Map<Object?, Object?>;

/// Functions の fetchOpponents を呼び、相手の候補を返す。ログインが無い時は呼ばずに null を返す。
Future<List<PvpOpponent>?> fetchPvpOpponentsWithFirebase() async {
  if (signedInUIDWithFirebase() == null) {
    return null;
  }
  final result = await _call(name: 'fetchOpponents', data: null);
  return [
    for (final opponentJson in result['opponents']! as List<Object?>)
      PvpOpponent.fromJson(
        json: _toJson(opponentJson)! as Map<String, dynamic>,
      ),
  ];
}

/// callable が返した値 (Map<Object?, Object?> の入れ子) を、`fromJson` が読む Map<String, dynamic> の入れ子にする。
Object? _toJson(Object? value) => switch (value) {
  Map() => {
    for (final entry in value.entries)
      entry.key! as String: _toJson(entry.value),
  },
  List() => [for (final item in value) _toJson(item)],
  _ => value,
};

/// [base] に、Firestore の `definitions/{definitionID}` ([definitionIDs]) を読んで足した定義を返す。
/// 無い定義があれば [StateError] を投げる (相手の属性・技を引けないまま戦わせないため)。
Future<MasterData> fetchDefinitionsWithFirebase({
  required MasterData base,
  required List<String> definitionIDs,
}) async {
  var definitions = base;
  for (final definitionID in definitionIDs.toSet()) {
    final definitionJson = (await fetchDefinition(
      firestore: FirebaseFirestore.instance,
      definitionID: definitionID,
    )).data();
    if (definitionJson == null) {
      throw StateError('定義 $definitionID が Firestore にありません');
    }
    definitions = mergeMasterData(
      base: definitions,
      additional: MasterData.fromJson(json: definitionJson),
    );
  }
  return definitions;
}

/// Functions の reportMonster を呼び、[monsterOwnerUid] のモンスター [monsterID] を [reason] で通報する。
Future<void> reportMonsterWithFirebase({
  required String monsterOwnerUid,
  required String monsterID,
  required ReportReason reason,
}) => _call(
  name: 'reportMonster',
  data: {
    'monsterOwnerUid': monsterOwnerUid,
    'monsterID': monsterID,
    'reason': reason.value,
  },
);

/// Functions の blockUser を呼び、[blockedUid] のユーザーをブロックする。[battleID] (ブロックの操作をした人との対戦の ID。
/// 対戦の外からは null) がその相手との進行中の対戦なら、Functions が勝敗を付けずに終える。
Future<void> blockUserWithFirebase({
  required String blockedUid,
  required String? battleID,
}) => _call(
  name: 'blockUser',
  data: {'blockedUid': blockedUid, 'battleID': battleID},
);

/// 自分の `users/{uid}/battles` のうち、勝った・負けた記録の数を数えて返す (集計を Firestore に持たないため、数えるクエリで読む。
/// .claude/rules/firestore.md)。ログインが無い時は null を返す。
Future<({int wins, int losses})?> fetchBattleRecordWithFirebase() async {
  final uid = signedInUIDWithFirebase();
  if (uid == null) {
    return null;
  }
  final battles = FirebaseFirestore.instance.collection('users/$uid/battles');
  Future<int> countWinner({required String winner}) async =>
      (await battles.where('winner', isEqualTo: winner).count().get()).count!;
  final (wins, losses) = await (
    countWinner(winner: 'player'),
    countWinner(winner: 'opponent'),
  ).wait;
  return (wins: wins, losses: losses);
}

/// Functions の getDisplayName を呼び、自分の表示名とアイコンを返す。ログインが無い時は呼ばずに null を返す。
/// iconPath を返さない古い Functions (アイコンを足す前の版) の応答は、アイコンの無いプロフィールとして読む。
Future<PlayerProfile?> fetchProfileWithFirebase() async {
  if (signedInUIDWithFirebase() == null) {
    return null;
  }
  final result = await _call(name: 'getDisplayName', data: null);
  return (
    displayName: result['displayName']! as String,
    iconPath: result['iconPath'] as String?,
  );
}

/// [photo] (JPEG) を Storage の `users/{uid}/iconUploads/{uploadID}` に置いてから Functions の setProfileIcon を呼び、
/// 保存したアイコンのパスを返す。uploadID は呼ぶたびに作る (同じ写真を選び直しても、別のアイコンとして検査し直すため)。
Future<String> updateProfileIconWithFirebase({required Uint8List photo}) async {
  final uid = signedInUIDWithFirebase();
  if (uid == null) {
    throw StateError('ログインしていないためアイコンを変えられません');
  }
  final uploadID = const Uuid().v4();
  await FirebaseStorage.instance
      .ref('users/$uid/iconUploads/$uploadID')
      .putData(photo, SettableMetadata(contentType: 'image/jpeg'));
  return (await _call(
        name: 'setProfileIcon',
        data: {'uploadID': uploadID},
      ))['iconPath']!
      as String;
}

/// Functions の setDisplayName を呼び、保存した表示名を返す。
Future<String> updateDisplayNameWithFirebase({
  required String displayName,
}) async =>
    (await _call(
          name: 'setDisplayName',
          data: {'displayName': displayName},
        ))['displayName']!
        as String;

/// 人との対戦の相手を探す 1 回の操作の ID (UUID) を作る。
String createPvpSearchID() => const Uuid().v4();

/// Functions の joinPvpMatch を呼び、組み合わされた対戦の ID を返す。まだ組み合わされていなければ null。
Future<String?> joinPvpMatchWithFirebase({
  required String rulesVersion,
  required String searchID,
}) async =>
    (await _call(
          name: 'joinPvpMatch',
          data: {'rulesVersion': rulesVersion, 'searchID': searchID},
        ))['battleID']
        as String?;

/// Functions の leavePvpMatch を呼び、やめる前に組み合わされていた対戦の ID を返す。組み合わされていなければ null。
Future<String?> leavePvpMatchWithFirebase({required String searchID}) async =>
    (await _call(
          name: 'leavePvpMatch',
          data: {'searchID': searchID},
        ))['battleID']
        as String?;

/// Firestore の `pvpBattles/{battleID}` の今の状態と、その後の変化を流す。ドキュメントが無い時は null を流す。
Stream<PvpBattle?> watchPvpBattleWithFirebase({required String battleID}) =>
    FirebaseFirestore.instance
        .doc('pvpBattles/$battleID')
        .snapshots()
        .map(
          (snapshot) => switch (snapshot.data()) {
            null => null,
            final battleJson => PvpBattle.fromJson(
              battleID: battleID,
              json: _toJson(battleJson)! as Map<String, dynamic>,
            ),
          },
        );

/// Functions の submitPvpAction を呼び、対戦 [battleID] の [round] 番目のターンに自分の行動 [action] を出す。
Future<void> submitPvpActionWithFirebase({
  required String battleID,
  required int round,
  required BattleAction action,
}) => _call(
  name: 'submitPvpAction',
  data: {
    'battleID': battleID,
    'round': round,
    'action': battleActionToJson(action: action),
  },
);

/// Functions の claimPvpTimeout を呼び、対戦 [battleID] の今のターンを時間切れとして終えるよう頼む。
Future<void> claimPvpTimeoutWithFirebase({required String battleID}) =>
    _call(name: 'claimPvpTimeout', data: {'battleID': battleID});

/// Functions の reportPvpResult を呼び、対戦 [battleID] の自分の計算の勝者 [winnerUID] (決着していなければ null) を報告する。
Future<void> reportPvpResultWithFirebase({
  required String battleID,
  required String? winnerUID,
}) => _call(
  name: 'reportPvpResult',
  data: {'battleID': battleID, 'winnerUID': winnerUID},
);
