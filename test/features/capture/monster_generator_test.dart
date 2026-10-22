import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/capture/monster_generator.dart';

void main() {
  test('callable の結果の状態・モンスター・拒否の理由を読む', () {
    final saved = GenerationResult.fromJson(
      json: {'requestId': 'request-1', 'status': 'saved', 'monsterId': 'm1'},
    );
    expect(
      (saved.requestId, saved.status, saved.monsterId, saved.rejectionReason),
      ('request-1', GenerationStatus.saved, 'm1', null),
    );
    final rejected = GenerationResult.fromJson(
      json: {
        'requestId': 'request-2',
        'status': 'rejected',
        'rejectionReason': 'face_detected',
      },
    );
    expect(rejected.rejectionReason, GenerationRejectionReason.faceDetected);
    expect(
      GenerationResult.fromJson(
        json: {'requestId': 'request-3', 'status': 'pending_judge'},
      ).status,
      GenerationStatus.pendingJudge,
    );
  });

  test('知らない状態は FormatException を投げる (別の状態として扱わない)', () {
    expect(
      () => GenerationResult.fromJson(
        json: {'requestId': 'request-1', 'status': 'unknown'},
      ),
      throwsFormatException,
    );
  });
}
