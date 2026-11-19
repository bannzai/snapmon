import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/sample/sample_generation.dart';

import '../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  test('図鑑にいない最初の見本のモンスターをレベル 1 で図鑑に足し、saved を返す', () {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: [sampleData.monsters.first]);
    final result = generateSampleMonster(
      dexStore: dexStore,
      sampleData: sampleData,
      requestID: 'request-1',
    );
    final expectedMonster = sampleData.monsters[1];
    expect(result.status, GenerationStatus.saved);
    expect(result.requestID, 'request-1');
    expect(result.monsterID, expectedMonster.definition.id);
    expect(dexStore.monsters.map((monster) => monster.definition.id), [
      sampleData.monsters.first.definition.id,
      expectedMonster.definition.id,
    ]);
    expect(dexStore.monsters.last.level, 1);
    // 手持ちは変えない
    expect(dexStore.party.map((monster) => monster.definition.id), [
      sampleData.monsters.first.definition.id,
    ]);
  });

  test('何もいない図鑑 (撮影の準備をしていない) では、先頭の見本のモンスターが生まれ、撮影用の味方は図鑑にも手持ちにも入らない', () {
    final dexStore = DexStore(definitions: sampleData.definitions);
    expect(
      generateSampleMonster(
        dexStore: dexStore,
        sampleData: sampleData,
        requestID: 'request-1',
      ).monsterID,
      'sample-mugmon',
    );
    expect(dexStore.monsters.map((monster) => monster.definition.id), [
      'sample-mugmon',
    ]);
    expect(dexStore.party, isEmpty);
  });

  group('紹介動画の撮影の準備の後 (図鑑に一緒に戦う味方だけがいる)', () {
    /// 撮影の準備 (preparePlayVideo) が作る図鑑。
    DexStore preparedDexStore() =>
        DexStore(definitions: sampleData.definitions)..applyServerSnapshot(
          monsters: [sampleData.playVideo.companionMonster],
          partyMonsterIDs: const [],
          definitions: null,
        );

    test('最初の生成は撮影用のマグモンを Lv.1 で生み、手持ちを生まれた方が先頭の 2 体にして saved を返す', () {
      final dexStore = preparedDexStore();
      final result = generateSampleMonster(
        dexStore: dexStore,
        sampleData: sampleData,
        requestID: 'request-1',
      );
      expect(result.status, GenerationStatus.saved);
      expect(result.requestID, 'request-1');
      expect(result.monsterID, 'play-video-mugmon');
      expect(dexStore.monsters.map((monster) => monster.definition.id), [
        'play-video-pukapukku',
        'play-video-mugmon',
      ]);
      expect(dexStore.party.map((monster) => monster.definition.id), [
        'play-video-mugmon',
        'play-video-pukapukku',
      ]);
      expect(dexStore.party.first.definition.name, 'マグモン');
      expect(dexStore.party.first.level, 1);
    });

    test('2 回目の生成は今までどおり見本のモンスターを足し、手持ちを変えない', () {
      final dexStore = preparedDexStore();
      generateSampleMonster(
        dexStore: dexStore,
        sampleData: sampleData,
        requestID: 'request-1',
      );
      expect(
        generateSampleMonster(
          dexStore: dexStore,
          sampleData: sampleData,
          requestID: 'request-2',
        ).monsterID,
        'sample-mugmon',
      );
      expect(dexStore.monsters.map((monster) => monster.definition.id), [
        'play-video-pukapukku',
        'play-video-mugmon',
        'sample-mugmon',
      ]);
      expect(dexStore.party.map((monster) => monster.definition.id), [
        'play-video-mugmon',
        'play-video-pukapukku',
      ]);
    });
  });

  test('見本のモンスターが全部図鑑にいる時は、図鑑を変えずに先頭の duplicate を返す', () {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters);
    final result = generateSampleMonster(
      dexStore: dexStore,
      sampleData: sampleData,
      requestID: 'request-1',
    );
    expect(result.status, GenerationStatus.duplicate);
    expect(result.monsterID, sampleData.monsters.first.definition.id);
    expect(dexStore.monsters, hasLength(sampleData.monsters.length));
  });
}
