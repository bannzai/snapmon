import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/master/master_data.dart';

void main() {
  test('master の技はすべてスプライトシートで描くエフェクトを指す', () {
    // master はアプリに同梱しない (pubspec.yaml) ため、リポジトリのファイルを直接読む
    final masterJson =
        jsonDecode(File('assets/master/master.json').readAsStringSync())
            as Map<String, dynamic>;
    final master = MasterData.fromJson(json: masterJson);
    // 書き出しのスクリプトは pixelfxID の最後の部分をファイル名にするため、spriteSheet と一致し、別の素材が同じ名前を持たない
    final pixelfxIDsBySheet = <String, Set<String>>{};
    for (final effect in masterJson['effects'] as List<dynamic>) {
      if ((effect as Map<String, dynamic>)['spriteSheet']
          case final String spriteSheet) {
        final pixelfxID = effect['pixelfxID'] as String;
        expect(spriteSheet, pixelfxID.split('/').last, reason: effect['id']);
        (pixelfxIDsBySheet[spriteSheet] ??= {}).add(pixelfxID);
      }
    }
    for (final MapEntry(key: sheet, value: pixelfxIDs)
        in pixelfxIDsBySheet.entries) {
      expect(pixelfxIDs, hasLength(1), reason: sheet);
    }
    for (final move in master.moves) {
      final effect = master.effectByID(effectID: move.effectID);
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
