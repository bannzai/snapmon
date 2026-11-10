import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/battle_engine.dart';
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
      final masterByID = {
        for (final entry in masterJson[key] as List<dynamic>)
          (entry as Map<String, dynamic>)['id']: entry,
      };
      for (final entry in sampleDefinitions[key] as List<dynamic>) {
        final sampleEntry = entry as Map<String, dynamic>;
        expect(
          sampleEntry,
          masterByID[sampleEntry['id']],
          reason: '$key の ${sampleEntry['id']}',
        );
      }
    }
    // 相性表が無いと倍率が常に 1 になり、バトルで属性の相性が効かないため、master と同じ表を持つ
    expect(sampleDefinitions['typeChart'], masterJson['typeChart']);
    // ステータスの段階が無いとカードのステータスの目盛り (種族値の上限) を描けないため、master と同じ段階を持つ
    expect(sampleDefinitions['statGrades'], masterJson['statGrades']);
  });

  test('見本のモンスターの属性・技はすべて見本の定義にある', () {
    final elementTypeIDs = {
      for (final elementType in sampleData.definitions.elementTypes)
        elementType.id,
    };
    for (final monster in sampleData.monsters) {
      expect(
        elementTypeIDs.containsAll(monster.definition.elementTypeIDs),
        isTrue,
      );
      for (final learnsetEntry in monster.definition.learnset) {
        final move = sampleData.definitions.moveByID(
          moveID: learnsetEntry.moveID,
        );
        expect(
          () => sampleData.definitions.effectByID(effectID: move.effectID),
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

  test('見本のモンスターは生まれた時の技 (Lv.1) を技の枠の数だけ持つ', () {
    for (final monster in sampleData.monsters) {
      expect(
        monster.definition.learnset.where(
          (learnsetEntry) => learnsetEntry.unlockLevel == 1,
        ),
        hasLength(maximumEquippedMoveCount),
        reason: monster.definition.id,
      );
    }
  });

  test('CPU トレーナーの名前は 1 つ以上あり、重複せず、CPU で始まる', () {
    expect(sampleData.cpuTrainerNames, isNotEmpty);
    expect(
      sampleData.cpuTrainerNames.toSet(),
      hasLength(sampleData.cpuTrainerNames.length),
    );
    for (final cpuTrainerName in sampleData.cpuTrainerNames) {
      expect(cpuTrainerName, startsWith('CPU '));
    }
  });

  test(
    '見本のモンスターは手持ちの上限の 2 倍以上いて、絵が互いに重ならない (自分の手持ちと同じ絵を除いても CPU の手持ちを組めるため)',
    () {
      expect(
        sampleData.monsters.length,
        greaterThanOrEqualTo(maximumPartySize * 2),
      );
      expect({
        for (final monster in sampleData.monsters) monster.artPath,
      }, hasLength(sampleData.monsters.length));
    },
  );

  test('見本の対戦相手は見本のモンスターを 1〜3 体持つ', () {
    expect(sampleData.opponents, isNotEmpty);
    for (final opponent in sampleData.opponents) {
      expect(opponent.monsterIDs.length, inInclusiveRange(1, maximumPartySize));
      for (final monsterID in opponent.monsterIDs) {
        expect(
          () => sampleData.monsterByID(monsterID: monsterID),
          returnsNormally,
        );
      }
    }
  });
}
