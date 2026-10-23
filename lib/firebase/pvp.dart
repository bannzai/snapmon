import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/master/master_data.dart';
import '../features/opponent/pvp_opponent.dart';
import '../features/opponent/report_reason.dart';
import '../master/master_repository.dart';
import 'session.dart';

// 非同期 PvP の Functions (functions/src/pvp.ts) の呼び出しと、自分の戦績の読み込み。

/// ログインしていれば、その uid を返す。無ければ null
/// (Functions と Rules がログインの無い呼び出しを拒否するため。DEBUG ビルドでログインを飛ばした時に当たる)。
String? _signedInUid() => FirebaseAuth.instance.currentUser?.uid;

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
  if (_signedInUid() == null) {
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

/// [base] に、Firestore の `definitions/{definitionId}` ([definitionIds]) を読んで足した定義を返す。
/// 無い定義があれば [StateError] を投げる (相手の属性・技を引けないまま戦わせないため)。
Future<MasterData> fetchDefinitionsWithFirebase({
  required MasterData base,
  required List<String> definitionIds,
}) async {
  var definitions = base;
  for (final definitionId in definitionIds.toSet()) {
    final definitionJson = (await fetchDefinition(
      firestore: FirebaseFirestore.instance,
      definitionId: definitionId,
    )).data();
    if (definitionJson == null) {
      throw StateError('定義 $definitionId が Firestore にありません');
    }
    definitions = mergeMasterData(
      base: definitions,
      additional: MasterData.fromJson(json: definitionJson),
    );
  }
  return definitions;
}

/// Functions の reportMonster を呼び、[monsterOwnerUid] のモンスター [monsterId] を [reason] で通報する。
Future<void> reportMonsterWithFirebase({
  required String monsterOwnerUid,
  required String monsterId,
  required ReportReason reason,
}) => _call(
  name: 'reportMonster',
  data: {
    'monsterOwnerUid': monsterOwnerUid,
    'monsterId': monsterId,
    'reason': reason.value,
  },
);

/// Functions の blockUser を呼び、[blockedUid] のユーザーをブロックする。
Future<void> blockUserWithFirebase({required String blockedUid}) =>
    _call(name: 'blockUser', data: {'blockedUid': blockedUid});

/// 自分の `users/{uid}/battles` のうち、勝った・負けた記録の数を数えて返す (集計を Firestore に持たないため、数えるクエリで読む。
/// .claude/rules/firestore.md)。ログインが無い時は null を返す。
Future<({int wins, int losses})?> fetchBattleRecordWithFirebase() async {
  final uid = _signedInUid();
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

/// Functions の getDisplayName を呼び、自分の表示名を返す。ログインが無い時は呼ばずに null を返す。
Future<String?> fetchDisplayNameWithFirebase() async {
  if (_signedInUid() == null) {
    return null;
  }
  return (await _call(name: 'getDisplayName', data: null))['displayName']!
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
