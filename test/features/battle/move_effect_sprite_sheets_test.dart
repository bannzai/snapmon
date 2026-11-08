import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/master/master_data.dart';

void main() {
  test('master の技はすべてスプライトシートで描くエフェクトを指す', () {
    // master はアプリに同梱しない (pubspec.yaml) ため、リポジトリのファイルを直接読む
    final master = MasterData.fromJson(
      json:
          jsonDecode(File('assets/master/master.json').readAsStringSync())
              as Map<String, dynamic>,
    );
    for (final move in master.moves) {
      final effect = master.effectById(effectId: move.effectId);
      expect(effect.kind, 'spriteSheet', reason: move.id);
      expect(effect.spriteSheet, isNotNull, reason: move.id);
      // シートの PNG と JSON が同梱されている
      for (final extension in ['png', 'json']) {
        expect(
          File(
            'assets/images/move_effects/${effect.spriteSheet}.$extension',
          ).existsSync(),
          isTrue,
          reason: '${move.id}: ${effect.spriteSheet}.$extension',
        );
      }
    }
    // 同梱したシートに master が参照しないものが無い
    final referenced = {
      for (final effect in master.effects) ?effect.spriteSheet,
    };
    final bundled = {
      for (final file in Directory('assets/images/move_effects').listSync())
        if (file.path.endsWith('.png'))
          file.uri.pathSegments.last.replaceAll('.png', ''),
    };
    expect(bundled, referenced);
  });
}
