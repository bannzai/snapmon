import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/dex/dex_store.dart';

import '../../monster_generator_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();
  final monsters = sampleData.monsters;
  List<String> partyIds({required DexStore dexStore}) => [
    for (final monster in dexStore.party) monster.definition.id,
  ];

  /// 手持ちの保存を [savedPartyMonsterIds] に残すサーバーに繋いだ図鑑。[monsters] の全員が図鑑にいる。
  /// [saveError] を渡すと保存がその例外で失敗する。
  DexStore serverBackedDexStore({
    required List<List<String>> savedPartyMonsterIds,
    required Object? saveError,
  }) => DexStore(definitions: sampleData.definitions)
    ..connectServer(
      savePartyMonsterIds: ({required monsterIds}) async {
        if (saveError != null) {
          throw saveError;
        }
        savedPartyMonsterIds.add(monsterIds);
      },
    )
    ..applyServerSnapshot(
      monsters: monsters,
      partyMonsterIds: const [],
      definitions: null,
    );

  test('手持ちは 3 体まで、図鑑にいないモンスターは入らない', () async {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..applyServerSnapshot(
        monsters: monsters,
        partyMonsterIds: const [],
        definitions: null,
      );
    await dexStore.addToParty(monsterId: 'not-in-dex');
    for (final monster in monsters) {
      await dexStore.addToParty(monsterId: monster.definition.id);
    }
    expect(
      partyIds(dexStore: dexStore),
      monsters.take(3).map((monster) => monster.definition.id),
    );
    expect(dexStore.hasPartyVacancy, isFalse);
  });

  test('手持ちが 3 体の時の入れ替えは、外した手持ちの位置に入れる', () async {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: monsters);
    await dexStore.replacePartyMember(
      outgoingMonsterId: monsters[1].definition.id,
      incomingMonsterId: monsters[3].definition.id,
    );
    expect(partyIds(dexStore: dexStore), [
      monsters[0].definition.id,
      monsters[3].definition.id,
      monsters[2].definition.id,
    ]);
    // 既に手持ちにいるモンスターとは入れ替えない
    await dexStore.replacePartyMember(
      outgoingMonsterId: monsters[0].definition.id,
      incomingMonsterId: monsters[2].definition.id,
    );
    expect(partyIds(dexStore: dexStore), hasLength(3));
    expect(partyIds(dexStore: dexStore).toSet(), hasLength(3));
  });

  test('サーバーに繋いだ図鑑は、手持ちの変更を ID の一覧で保存する', () async {
    final savedPartyMonsterIds = <List<String>>[];
    final dexStore = serverBackedDexStore(
      savedPartyMonsterIds: savedPartyMonsterIds,
      saveError: null,
    );
    await dexStore.addToParty(monsterId: monsters[0].definition.id);
    await dexStore.addToParty(monsterId: monsters[1].definition.id);
    await dexStore.removeFromParty(monsterId: monsters[0].definition.id);
    expect(savedPartyMonsterIds, [
      [monsters[0].definition.id],
      [monsters[0].definition.id, monsters[1].definition.id],
      [monsters[1].definition.id],
    ]);
    expect(dexStore.isServerBacked, isTrue);
  });

  test('サーバーの図鑑から離れると、空の端末の図鑑と渡した定義に戻り、手持ちを保存しなくなる', () async {
    final savedPartyMonsterIds = <List<String>>[];
    final dexStore =
        serverBackedDexStore(
          savedPartyMonsterIds: savedPartyMonsterIds,
          saveError: null,
        )..applyServerSnapshot(
          monsters: null,
          partyMonsterIds: null,
          definitions: definitionsWithWax(base: sampleData.definitions),
        );
    dexStore.disconnectServer(definitions: sampleData.definitions);
    expect(dexStore.monsters, isEmpty);
    expect(dexStore.isServerBacked, isFalse);
    expect(dexStore.definitions, same(sampleData.definitions));
    dexStore.replaceAll(monsters: monsters);
    await dexStore.removeFromParty(monsterId: monsters[0].definition.id);
    expect(savedPartyMonsterIds, isEmpty);
  });

  test('手持ちの保存に失敗したら変更の前に戻して例外を投げる', () async {
    final dexStore = serverBackedDexStore(
      savedPartyMonsterIds: [],
      saveError: Exception('permission-denied'),
    );
    await expectLater(
      dexStore.addToParty(monsterId: monsters[0].definition.id),
      throwsException,
    );
    expect(dexStore.party, isEmpty);
  });

  test('手持ちの ID のうち図鑑にまだ届いていないモンスターは手持ちに出さない', () {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..applyServerSnapshot(
        monsters: monsters.take(1).toList(),
        partyMonsterIds: [monsters[0].definition.id, 'not-arrived'],
        definitions: null,
      );
    expect(partyIds(dexStore: dexStore), [monsters[0].definition.id]);
    expect(dexStore.hasPartyVacancy, isTrue);
  });

  test('サーバーの図鑑と定義を反映し、null の項目は変えない', () {
    final definitions = definitionsWithWax(base: sampleData.definitions);
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..applyServerSnapshot(
        monsters: [generatedWaxMonster(monsterId: 'm1')],
        partyMonsterIds: const ['m1'],
        definitions: definitions,
      )
      ..applyServerSnapshot(
        monsters: null,
        partyMonsterIds: null,
        definitions: null,
      );
    expect(dexStore.monsters.single.definition.id, 'm1');
    expect(partyIds(dexStore: dexStore), ['m1']);
    expect(dexStore.definitions, same(definitions));
  });

  test('waitForMonster は図鑑に届いた時に返し、届かなければ TimeoutException を投げる', () async {
    final dexStore = DexStore(definitions: sampleData.definitions);
    final arrival = dexStore.waitForMonster(
      monsterId: 'm1',
      timeout: const Duration(seconds: 1),
    );
    dexStore.applyServerSnapshot(
      monsters: [generatedWaxMonster(monsterId: 'm1')],
      partyMonsterIds: null,
      definitions: null,
    );
    expect((await arrival).definition.id, 'm1');
    expect(
      (await dexStore.waitForMonster(
        monsterId: 'm1',
        timeout: const Duration(seconds: 1),
      )).definition.id,
      'm1',
    );
    await expectLater(
      dexStore.waitForMonster(
        monsterId: 'not-arriving',
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('replaceAll は図鑑を置き換えて先頭 3 体を手持ちにし、clear で空になる', () {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: monsters);
    expect(dexStore.monsters, hasLength(monsters.length));
    expect(dexStore.party, hasLength(3));
    expect(dexStore.isServerBacked, isFalse);
    dexStore.clear();
    expect(dexStore.monsters, isEmpty);
    expect(dexStore.party, isEmpty);
  });

  test('レベルを置き換えると図鑑と手持ちに反映され、図鑑にいない ID は無視する', () {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: monsters);
    dexStore.updateLevels(
      levelsByMonsterId: {monsters[0].definition.id: 42, 'not-in-dex': 5},
    );
    expect(dexStore.party.first.level, 42);
    expect(dexStore.monsters[1].level, monsters[1].level);
    expect(dexStore.monsters, hasLength(monsters.length));
  });
}
