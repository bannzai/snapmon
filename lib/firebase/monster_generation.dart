import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../features/capture/monster_generator.dart';
import 'age_verified_session.dart';

// 生成の呼び出し (functions/src/generation/generate.ts の generate) と、その途中の段階の読み出し。
// 写真の置き場と要求 ID の形は generate.ts の handleGenerateRequest が検査する。

/// callable の待ち時間。生成の Functions のタイムアウト (generate.ts の 300 秒) に、写真の受け渡しと
/// コールドスタートの分を足した。これを過ぎても生成が続いている時は、生成のレコードの終了を待つ。
const Duration _generateCallableTimeout = Duration(seconds: 330);

/// callable が待ち時間を過ぎた後に、生成のレコードの終了を待つ時間。予約の期間 (pipeline.ts の 10 分) を過ぎると
/// 再試行のタスクが引き継ぐため、それまでに終わらなければ失敗として画面に出す。
const Duration _generationRecordWaitTimeout = Duration(minutes: 10);

/// ログイン中のユーザーの uid。ログインしていない時は [StateError] を投げる。
String _signedInUid() {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('ログインしていないため生成できません');
  }
  return user.uid;
}

DocumentReference<Map<String, dynamic>> _generationDocument({
  required String uid,
  required String requestId,
}) => FirebaseFirestore.instance
    .collection('users')
    .doc(uid)
    .collection('generations')
    .doc(requestId);

/// [photo] (JPEG) を Storage の `users/{uid}/photos/{requestId}` に置く ([MonsterGenerator.uploadPhoto])。
Future<void> uploadGenerationPhotoWithFirebase({
  required String requestId,
  required Uint8List photo,
}) async {
  await FirebaseStorage.instance
      .ref('users/${_signedInUid()}/photos/$requestId')
      .putData(photo, SettableMetadata(contentType: 'image/jpeg'));
}

/// generate を呼んで結果を返す ([MonsterGenerator.requestGeneration])。呼んでいる間は生成のレコードの段階を
/// [onCompletedStage] に渡す。callable が待ち時間を過ぎたら、生成のレコードが処理中でなくなるのを待って、その結果を返す。
Future<GenerationResult> requestGenerationWithFirebase({
  required String requestId,
  required void Function({required GenerationStage completedStage})
  onCompletedStage,
}) async {
  final uid = _signedInUid();
  final generationDocument = _generationDocument(
    uid: uid,
    requestId: requestId,
  );
  final stageSubscription = generationDocument.snapshots().listen((snapshot) {
    final completedStage = snapshot.data()?['completedStage'];
    if (completedStage != null) {
      onCompletedStage(
        completedStage: GenerationStage.values.byName(completedStage as String),
      );
    }
  }, onError: (Object _) {});
  try {
    final result = await FirebaseFunctions.instanceFor(region: functionsRegion)
        .httpsCallable(
          'generate',
          options: HttpsCallableOptions(timeout: _generateCallableTimeout),
        )
        .call<Object?>({
          'requestId': requestId,
          'photoPath': 'users/$uid/photos/$requestId',
        });
    return GenerationResult.fromJson(
      json: Map<String, dynamic>.from(result.data! as Map<Object?, Object?>),
    );
  } on FirebaseFunctionsException catch (error) {
    if (error.code != 'deadline-exceeded') {
      rethrow;
    }
    final finishedSnapshot = await generationDocument
        .snapshots()
        .firstWhere(
          (snapshot) =>
              snapshot.exists &&
              snapshot.data()!['status'] !=
                  GenerationStatus.processing.statusName,
        )
        .timeout(_generationRecordWaitTimeout);
    return GenerationResult.fromJson(
      json: {...finishedSnapshot.data()!, 'requestId': requestId},
    );
  } finally {
    await stageSubscription.cancel();
  }
}

/// [requestId] の生成のレコードを読み直して結果を返す ([MonsterGenerator.fetchGeneration])。
/// レコードが無い時は [StateError] を投げる。
Future<GenerationResult> fetchGenerationWithFirebase({
  required String requestId,
}) async {
  final snapshot = await _generationDocument(
    uid: _signedInUid(),
    requestId: requestId,
  ).get();
  if (!snapshot.exists) {
    throw StateError('生成の記録 $requestId がありません');
  }
  return GenerationResult.fromJson(
    json: {...snapshot.data()!, 'requestId': requestId},
  );
}
