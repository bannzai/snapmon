import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/capture/sample_generation.dart';
import 'package:snapmon/features/dex/dex_store.dart';

import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();
  final monsters = sampleData.monsters;

  test('同じモンスターは二重に図鑑へ入らない', () {
    final dexStore = DexStore()
      ..addMonster(monster: monsters[0])
      ..addMonster(monster: monsters[0]);
    expect(dexStore.monsters, hasLength(1));
  });

  test('手持ちは 3 体まで、図鑑にいないモンスターは入らない', () {
    final dexStore = DexStore();
    for (final monster in monsters) {
      dexStore.addMonster(monster: monster);
    }
    dexStore.addToParty(monsterId: 'not-in-dex');
    for (final monster in monsters) {
      dexStore.addToParty(monsterId: monster.definition.id);
    }
    expect(
      dexStore.party.map((monster) => monster.definition.id),
      monsters.take(3).map((monster) => monster.definition.id),
    );
    expect(dexStore.hasPartyVacancy, isFalse);
  });

  test('手持ちから外すと空きができ、別のモンスターを入れられる', () {
    final dexStore = DexStore()..replaceAll(monsters: monsters);
    dexStore
      ..removeFromParty(monsterId: monsters[1].definition.id)
      ..removeFromParty(monsterId: 'not-in-party')
      ..addToParty(monsterId: monsters[3].definition.id);
    expect(
      dexStore.party.map((monster) => monster.definition.id),
      [
        monsters[0],
        monsters[2],
        monsters[3],
      ].map((monster) => monster.definition.id),
    );
  });

  test('replaceAll は図鑑を置き換えて先頭 3 体を手持ちにし、clear で空になる', () {
    final dexStore = DexStore()..replaceAll(monsters: monsters);
    expect(dexStore.monsters, hasLength(monsters.length));
    expect(dexStore.party, hasLength(3));
    dexStore.replaceAll(monsters: monsters);
    expect(dexStore.monsters, hasLength(monsters.length));
    dexStore.clear();
    expect(dexStore.monsters, isEmpty);
    expect(dexStore.party, isEmpty);
  });

  test('見本の生成は図鑑にいない次の見本を図鑑に入れて返す', () {
    final dexStore = DexStore()..addMonster(monster: monsters[0]);
    final generated = generateSampleMonster(
      sampleData: sampleData,
      dexStore: dexStore,
    );
    expect(generated.definition.id, monsters[1].definition.id);
    expect(dexStore.monsters, hasLength(2));
  });

  test('見本が全員図鑑にいる時は先頭を返し、図鑑は増えない', () {
    final dexStore = DexStore()..replaceAll(monsters: monsters);
    final generated = generateSampleMonster(
      sampleData: sampleData,
      dexStore: dexStore,
    );
    expect(generated.definition.id, monsters[0].definition.id);
    expect(dexStore.monsters, hasLength(monsters.length));
  });
}
