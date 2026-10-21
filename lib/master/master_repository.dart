import 'package:cloud_firestore/cloud_firestore.dart';

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
