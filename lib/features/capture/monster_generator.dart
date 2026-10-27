import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../../analytics/analytics_events.dart';

/// 生成の段階 (functions/src/generation/records.ts の `GENERATION_STAGES`)。順に進む。
enum GenerationStage {
  /// 写真を受け付けた。
  uploaded,

  /// 不適切な画像・顔の検査を済ませた。
  safesearch,

  /// 被写体を切り出した。
  cutout,

  /// Claude が説明・名前・図鑑の文章を作った。
  claude,

  /// 物の分類を決めた。
  classify,

  /// 同じ被写体の判定を済ませた。
  dedupe,

  /// 属性・技・ステータスを決めた。
  judge,

  /// モンスターを保存した。
  saved,
}

/// 生成の状態 (functions/src/generation/records.ts の `GenerationStatus`)。processing と pendingJudge 以外は終了状態。
enum GenerationStatus {
  /// 処理中。
  processing('processing'),

  /// Jev が答えず、判定を待っている (サーバーが 1 時間おきに再試行する)。
  pendingJudge('pending_judge'),

  /// 新しいモンスターを保存した。
  saved('saved'),

  /// 同じ被写体のモンスターが既に図鑑にいた。
  duplicate('duplicate'),

  /// 写真から生成しなかった ([GenerationResult.rejectionReason])。
  rejected('rejected'),

  /// 失敗した。
  failed('failed');

  const GenerationStatus(this.statusName);

  /// サーバーが返す状態の名前。
  final String statusName;
}

/// 生成しなかった理由 (functions/src/generation/vision.ts の `RejectionReason`)。
enum GenerationRejectionReason {
  /// 不適切な画像。
  explicitContent('explicit_content'),

  /// 顔が写っている。
  faceDetected('face_detected'),

  /// 人が写っている (Claude の判定)。
  personDetected('person_detected'),

  /// 被写体が無い。
  noSubject('no_subject'),

  /// 名前・図鑑の文章が禁止語の検査を通らなかった。
  inappropriateText('inappropriate_text'),

  /// Claude が応答を拒んだ。
  refused('refused');

  const GenerationRejectionReason(this.reasonName);

  /// サーバーが返す理由の名前。
  final String reasonName;
}

/// 生成の callable `generate` が返す結果 (functions/src/generation/records.ts の `GenerationResult`)。
class GenerationResult {
  /// 結果を作る。
  const GenerationResult({
    required this.requestId,
    required this.status,
    required this.monsterId,
    required this.rejectionReason,
  });

  /// callable の戻り値か、生成のレコード (`users/{uid}/generations/{requestId}` に `requestId` を足したもの) から結果を読む。
  factory GenerationResult.fromJson({required Map<String, dynamic> json}) =>
      GenerationResult(
        requestId: json['requestId'] as String,
        status: GenerationStatus.values.firstWhere(
          (status) => status.statusName == json['status'],
          orElse: () => throw FormatException('生成の状態 ${json['status']} を知らない'),
        ),
        monsterId: json['monsterId'] as String?,
        rejectionReason: json['rejectionReason'] == null
            ? null
            : GenerationRejectionReason.values.firstWhere(
                (reason) => reason.reasonName == json['rejectionReason'],
                orElse: () => throw FormatException(
                  '生成しなかった理由 ${json['rejectionReason']} を知らない',
                ),
              ),
      );

  /// 結果を出した生成の要求 ID。同じ写真で別の要求の結果を使い回した時は、送った ID ではなく使い回し先の ID になる。
  final String requestId;

  /// 状態。
  final GenerationStatus status;

  /// saved・duplicate の時のモンスターの ID。
  final String? monsterId;

  /// rejected の理由。
  final GenerationRejectionReason? rejectionReason;
}

/// 生成を受け付ける前にサーバーが写真を見つけられなかった (functions/src/generation/pipeline.ts の `photo_not_found`)。
/// 受け付けを断られた写真はサーバーが後で消すため、同じ要求 ID で写真を置き直してから呼び直す目印にする。
class GenerationPhotoMissingException implements Exception {
  /// 例外を作る。[message] はサーバーが返したエラーの文言。
  const GenerationPhotoMissingException({required this.message});

  /// サーバーが返したエラーの文言。
  final String message;

  @override
  String toString() => message;
}

/// 写真がどこから来たか (計測の `monster_generated` の `source`)。
enum GenerationPhotoSource {
  /// カメラで撮った。
  camera,

  /// アルバムから選んだ。
  album,

  /// 開発者メニューの見本の写真。
  sample,
}

/// 撮る・選ぶ・生成の呼び出し・計測の関数の組。
/// 画面を Firebase と端末の機能から切り離してテストするため、実体 (lib/firebase/monster_generation.dart と
/// lib/features/capture/photo_preparation.dart) は main.dart から渡す。
class MonsterGenerator {
  /// 関数の組を作る。
  const MonsterGenerator({
    required this.listCameras,
    required this.openAppSettings,
    required this.pickAlbumPhoto,
    required this.preparePhoto,
    required this.createRequestId,
    required this.uploadPhoto,
    required this.requestGeneration,
    required this.fetchGeneration,
    required this.logEvent,
  });

  /// 端末のカメラの一覧を返す (camera パッケージの `availableCameras` と同じ形)。
  final Future<List<CameraDescription>> Function() listCameras;

  /// OS の設定アプリでこのアプリの設定 (カメラの権限) を開き、開けたかを返す
  /// (permission_handler の `openAppSettings` と同じ形。Web では開けず false を返す)。
  final Future<bool> Function() openAppSettings;

  /// アルバムから写真を 1 枚選んでもらい、その中身を返す。選ばずに閉じた時は null。
  final Future<Uint8List?> Function() pickAlbumPhoto;

  /// 撮った・選んだ写真 [sourceBytes] を生成に送る写真 (JPEG) にする
  /// (lib/features/capture/photo_preparation.dart の [prepareGenerationPhotoInBackground] と同じ形)。
  final Future<Uint8List> Function({required Uint8List sourceBytes})
  preparePhoto;

  /// 生成の要求 ID (UUID) を作る。写真 1 枚につき 1 回だけ作り、送り直しにも同じ ID を使う
  /// (サーバーは同じ ID の再送に保存済みの結果を返すため)。
  final String Function() createRequestId;

  /// 生成に送る写真 [photo] (JPEG) を [requestId] の置き場 (Storage の `users/{uid}/photos/{requestId}`) に置く。
  final Future<void> Function({
    required String requestId,
    required Uint8List photo,
  })
  uploadPhoto;

  /// [requestId] の写真から生成し、結果を返す。サーバーが段階を済ませるたびに [onCompletedStage] を呼ぶ。
  final Future<GenerationResult> Function({
    required String requestId,
    required void Function({required GenerationStage completedStage})
    onCompletedStage,
  })
  requestGeneration;

  /// [requestId] の生成の今の結果を読み直す (判定待ちの後に生まれたかを確かめる)。
  final Future<GenerationResult> Function({required String requestId})
  fetchGeneration;

  /// Analytics にイベントを送る ([logAnalyticsEvent] と同じ形)。
  final Future<void> Function({
    required AnalyticsEvent event,
    required Map<String, Object>? parameters,
  })
  logEvent;
}
