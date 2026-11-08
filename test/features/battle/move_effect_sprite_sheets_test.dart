import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/features/battle/move_effect_sprite_sheets.dart';

void main() {
  test('master のエフェクトはすべてスプライトシートを持つ', () {
    // master はアプリに同梱しない (pubspec.yaml) ため、リポジトリのファイルを直接読む
    final master =
        jsonDecode(File('assets/master/master.json').readAsStringSync())
            as Map<String, dynamic>;
    expect(
      moveEffectSpriteSheetsByEffectId.keys.toSet(),
      {
        for (final effect in master['effects'] as List<dynamic>)
          (effect as Map<String, dynamic>)['id'] as String,
      },
    );
  });
}
