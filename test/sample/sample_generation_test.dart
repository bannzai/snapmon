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
      requestId: 'request-1',
    );
    final expectedMonster = sampleData.monsters[1];
    expect(result.status, GenerationStatus.saved);
    expect(result.requestId, 'request-1');
    expect(result.monsterId, expectedMonster.definition.id);
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

  test('見本のモンスターが全部図鑑にいる時は、図鑑を変えずに先頭の duplicate を返す', () {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters);
    final result = generateSampleMonster(
      dexStore: dexStore,
      sampleData: sampleData,
      requestId: 'request-1',
    );
    expect(result.status, GenerationStatus.duplicate);
    expect(result.monsterId, sampleData.monsters.first.definition.id);
    expect(dexStore.monsters, hasLength(sampleData.monsters.length));
  });
}
