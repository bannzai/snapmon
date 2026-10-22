import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/master/master_data.dart';

// master (属性・技・相性表・分類) はアプリに同梱せず、Firestore の master/{version} から最新の版を読む。
// 起動時と対戦の前に読み直す (相性表は対戦時点の最新の版を両者に適用するため。documents/adr/0001-tech-stack.md)。
// 投入は functions/scripts/seed-master.mjs (deploy-functions.yml) が行い、各版に数値の version フィールドを付ける。

/// 最新の版の master のドキュメントを返す。投入された版が 1 つも無ければ null。
Future<DocumentSnapshot<Map<String, dynamic>>?> fetchLatestMaster({
  required FirebaseFirestore firestore,
}) async {
  final snapshot = await firestore
      .collection('master')
      .orderBy('version', descending: true)
      .limit(1)
      .get();
  return snapshot.docs.isEmpty ? null : snapshot.docs.first;
}

/// 生成時にその場で作った属性・技の定義 (definitions/{definitionId}) を返す。他人のモンスターが参照する定義の解決にも使う。
Future<DocumentSnapshot<Map<String, dynamic>>> fetchDefinition({
  required FirebaseFirestore firestore,
  required String definitionId,
}) {
  return firestore.collection('definitions').doc(definitionId).get();
}

/// 図鑑と対戦で属性・技を引く定義の集まりを返す: 最新の版の master [latestMasterJson] に、図鑑のモンスターが参照する
/// その場で作った定義 [definitionJsons] を足す (同じ ID は master を優先する。[mergeMasterData])。
/// master が投入されていない ([latestMasterJson] が null) 時は [StateError] を投げる
/// (空の定義で続けると、図鑑のモンスターの属性・技を引けずに画面が壊れるため)。
MasterData buildDexDefinitions({
  required Map<String, dynamic>? latestMasterJson,
  required List<Map<String, dynamic>> definitionJsons,
}) {
  if (latestMasterJson == null) {
    throw StateError('Firestore に master が投入されていません');
  }
  return definitionJsons.fold(
    MasterData.fromJson(json: latestMasterJson),
    (definitions, definitionJson) => mergeMasterData(
      base: definitions,
      additional: MasterData.fromJson(json: definitionJson),
    ),
  );
}
