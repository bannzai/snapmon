import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/sample/sample_data.dart';

import '../sample_data_fixture.dart';

void main() {
  final sampleJson =
      jsonDecode(File(sampleDataAssetPath).readAsStringSync())
          as Map<String, dynamic>;
  final masterJson =
      jsonDecode(File('assets/master/master.json').readAsStringSync())
          as Map<String, dynamic>;
  final sampleData = loadSampleDataFixture();

  test('見本の属性・技・エフェクトの定義と相性表は master と同じ ID・同じ値', () {
    final sampleDefinitions = sampleJson['definitions'] as Map<String, dynamic>;
    expect(sampleDefinitions['version'], masterJson['version']);
    for (final key in ['elementTypes', 'moves', 'effects']) {
      final masterById = {
        for (final entry in masterJson[key] as List<dynamic>)
          (entry as Map<String, dynamic>)['id']: entry,
      };
      for (final entry in sampleDefinitions[key] as List<dynamic>) {
        final sampleEntry = entry as Map<String, dynamic>;
        expect(
          sampleEntry,
          masterById[sampleEntry['id']],
          reason: '$key の ${sampleEntry['id']}',
        );
      }
    }
    // 相性表が無いと倍率が常に 1 になり、バトルで属性の相性が効かないため、master と同じ表を持つ
    expect(sampleDefinitions['typeChart'], masterJson['typeChart']);
  });

  test('見本のモンスターの属性・技はすべて見本の定義にある', () {
    final elementTypeIds = {
      for (final elementType in sampleData.definitions.elementTypes)
        elementType.id,
    };
    for (final monster in sampleData.monsters) {
      expect(
        elementTypeIds.containsAll(monster.definition.elementTypeIds),
        isTrue,
      );
      for (final learnsetEntry in monster.definition.learnset) {
        final move = sampleData.definitions.moveById(
          moveId: learnsetEntry.moveId,
        );
        expect(
          () => sampleData.definitions.effectById(effectId: move.effectId),
          returnsNormally,
        );
      }
    }
  });

  test('見本のモンスターは同梱した切り出し画像を持ち、出典が LICENSES.md にある', () {
    final licenses = File(
      '${sampleArtAssetDirectory}LICENSES.md',
    ).readAsStringSync();
    for (final monster in sampleData.monsters) {
      final artPath = monster.artPath!;
      expect(isBundledArtPath(artPath: artPath), isTrue, reason: artPath);
      expect(File(artPath).existsSync(), isTrue, reason: artPath);
      expect(licenses, contains('| ${artPath.split('/').last} |'));
      // 見本のモンスターは元の写真を持たない (結果の画面が Storage の写真を読まないため)
      expect(monster.definition.sourcePhotoReference, isNull);
    }
  });

  test('見本の対戦相手は見本のモンスターを 1〜3 体持つ', () {
    expect(sampleData.opponents, isNotEmpty);
    for (final opponent in sampleData.opponents) {
      expect(opponent.monsterIds.length, inInclusiveRange(1, maximumPartySize));
      for (final monsterId in opponent.monsterIds) {
        expect(
          () => sampleData.monsterById(monsterId: monsterId),
          returnsNormally,
        );
      }
    }
  });
}
