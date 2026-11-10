import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/dex/dex_store.dart';

import '../../monster_generator_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();
  final monsters = sampleData.monsters;
  List<String> partyIDs({required DexStore dexStore}) => [
    for (final monster in dexStore.party) monster.definition.id,
  ];

  /// 手持ちの保存を [savedPartyMonsterIDs] に残すサーバーに繋いだ図鑑。[monsters] の全員が図鑑にいる。
  /// [saveError] を渡すと保存がその例外で失敗する。
  DexStore serverBackedDexStore({
    required List<List<String>> savedPartyMonsterIDs,
    required Object? saveError,
  }) => DexStore(definitions: sampleData.definitions)
    ..connectServer(
      savePartyMonsterIDs: ({required monsterIDs}) async {
        if (saveError != null) {
          throw saveError;
        }
        savedPartyMonsterIDs.add(monsterIDs);
      },
      refreshDefinitions: () async {},
    )
    ..applyServerSnapshot(
      monsters: monsters,
      partyMonsterIDs: const [],
      definitions: null,
    );

  test('手持ちは 3 体まで、図鑑にいないモンスターは入らない', () async {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..applyServerSnapshot(
        monsters: monsters,
        partyMonsterIDs: const [],
        definitions: null,
      );
    await dexStore.addToParty(monsterID: 'not-in-dex');
    for (final monster in monsters) {
      await dexStore.addToParty(monsterID: monster.definition.id);
    }
    expect(
      partyIDs(dexStore: dexStore),
      monsters.take(3).map((monster) => monster.definition.id),
    );
    expect(dexStore.hasPartyVacancy, isFalse);
  });

  test('手持ちが 3 体の時の入れ替えは、外した手持ちの位置に入れる', () async {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: monsters);
    await dexStore.replacePartyMember(
      outgoingMonsterID: monsters[1].definition.id,
      incomingMonsterID: monsters[3].definition.id,
    );
    expect(partyIDs(dexStore: dexStore), [
      monsters[0].definition.id,
      monsters[3].definition.id,
      monsters[2].definition.id,
    ]);
    // 既に手持ちにいるモンスターとは入れ替えない
    await dexStore.replacePartyMember(
      outgoingMonsterID: monsters[0].definition.id,
      incomingMonsterID: monsters[2].definition.id,
    );
    expect(partyIDs(dexStore: dexStore), hasLength(3));
    expect(partyIDs(dexStore: dexStore).toSet(), hasLength(3));
  });

  test('サーバーに繋いだ図鑑は、手持ちの変更を ID の一覧で保存する', () async {
    final savedPartyMonsterIDs = <List<String>>[];
    final dexStore = serverBackedDexStore(
      savedPartyMonsterIDs: savedPartyMonsterIDs,
      saveError: null,
    );
    await dexStore.addToParty(monsterID: monsters[0].definition.id);
    await dexStore.addToParty(monsterID: monsters[1].definition.id);
    await dexStore.removeFromParty(monsterID: monsters[0].definition.id);
    expect(savedPartyMonsterIDs, [
      [monsters[0].definition.id],
      [monsters[0].definition.id, monsters[1].definition.id],
      [monsters[1].definition.id],
    ]);
    expect(dexStore.isServerBacked, isTrue);
  });

  test('サーバーの図鑑から離れると、空の端末の図鑑と渡した定義に戻り、手持ちを保存しなくなる', () async {
    final savedPartyMonsterIDs = <List<String>>[];
    final dexStore =
        serverBackedDexStore(
          savedPartyMonsterIDs: savedPartyMonsterIDs,
          saveError: null,
        )..applyServerSnapshot(
          monsters: null,
          partyMonsterIDs: null,
          definitions: definitionsWithWax(base: sampleData.definitions),
        );
    dexStore.disconnectServer(definitions: sampleData.definitions);
    expect(dexStore.monsters, isEmpty);
    expect(dexStore.isServerBacked, isFalse);
    expect(dexStore.definitions, same(sampleData.definitions));
    dexStore.replaceAll(monsters: monsters);
    await dexStore.removeFromParty(monsterID: monsters[0].definition.id);
    expect(savedPartyMonsterIDs, isEmpty);
  });

  test('手持ちの保存に失敗したら変更の前に戻して例外を投げる', () async {
    final dexStore = serverBackedDexStore(
      savedPartyMonsterIDs: [],
      saveError: Exception('permission-denied'),
    );
    await expectLater(
      dexStore.addToParty(monsterID: monsters[0].definition.id),
      throwsException,
    );
    expect(dexStore.party, isEmpty);
  });

  test('手持ちの ID のうち図鑑にまだ届いていないモンスターは手持ちに出さない', () {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..applyServerSnapshot(
        monsters: monsters.take(1).toList(),
        partyMonsterIDs: [monsters[0].definition.id, 'not-arrived'],
        definitions: null,
      );
    expect(partyIDs(dexStore: dexStore), [monsters[0].definition.id]);
    expect(dexStore.hasPartyVacancy, isTrue);
  });

  test('図鑑にまだ届いていない手持ちも、手持ちを変えて保存する一覧と空きの数に残す', () async {
    final savedPartyMonsterIDs = <List<String>>[];
    final dexStore =
        serverBackedDexStore(
          savedPartyMonsterIDs: savedPartyMonsterIDs,
          saveError: null,
        )..applyServerSnapshot(
          monsters: null,
          partyMonsterIDs: [monsters[0].definition.id, 'not-arrived'],
          definitions: null,
        );
    await dexStore.addToParty(monsterID: monsters[1].definition.id);
    expect(savedPartyMonsterIDs.single, [
      monsters[0].definition.id,
      'not-arrived',
      monsters[1].definition.id,
    ]);
    expect(dexStore.hasPartyVacancy, isFalse);
  });

  test('手持ちの保存の途中は次の変更を受け付けず、保存が済めば受け付ける', () async {
    final pendingSave = Completer<void>();
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..connectServer(
        savePartyMonsterIDs: ({required monsterIDs}) => pendingSave.future,
        refreshDefinitions: () async {},
      )
      ..applyServerSnapshot(
        monsters: monsters,
        partyMonsterIDs: const [],
        definitions: null,
      );
    final firstChange = dexStore.addToParty(
      monsterID: monsters[0].definition.id,
    );
    expect(dexStore.isSavingParty, isTrue);
    await expectLater(
      dexStore.addToParty(monsterID: monsters[1].definition.id),
      throwsStateError,
    );
    pendingSave.complete();
    await firstChange;
    expect(dexStore.isSavingParty, isFalse);
    expect(partyIDs(dexStore: dexStore), [monsters[0].definition.id]);
  });

  test('読み込みの失敗の表示は、手持ちだけが届いても消えず、図鑑か定義が届いた時に消える', () {
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..reportServerError(error: StateError('通信できません'))
      ..applyServerSnapshot(
        monsters: null,
        partyMonsterIDs: const [],
        definitions: null,
      );
    expect(dexStore.serverError, isNotNull);
    dexStore.applyServerSnapshot(
      monsters: monsters,
      partyMonsterIDs: null,
      definitions: null,
    );
    expect(dexStore.serverError, isNull);
  });

  test('サーバーの図鑑と定義を反映し、null の項目は変えない', () {
    final definitions = definitionsWithWax(base: sampleData.definitions);
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..applyServerSnapshot(
        monsters: [generatedWaxMonster(monsterID: 'm1')],
        partyMonsterIDs: const ['m1'],
        definitions: definitions,
      )
      ..applyServerSnapshot(
        monsters: null,
        partyMonsterIDs: null,
        definitions: null,
      );
    expect(dexStore.monsters.single.definition.id, 'm1');
    expect(partyIDs(dexStore: dexStore), ['m1']);
    expect(dexStore.definitions, same(definitions));
  });

  test('waitForMonster は図鑑に届いた時に返し、届かなければ TimeoutException を投げる', () async {
    final dexStore = DexStore(definitions: sampleData.definitions);
    final arrival = dexStore.waitForMonster(
      monsterID: 'm1',
      timeout: const Duration(seconds: 1),
    );
    dexStore.applyServerSnapshot(
      monsters: [generatedWaxMonster(monsterID: 'm1')],
      partyMonsterIDs: null,
      definitions: null,
    );
    expect((await arrival).definition.id, 'm1');
    expect(
      (await dexStore.waitForMonster(
        monsterID: 'm1',
        timeout: const Duration(seconds: 1),
      )).definition.id,
      'm1',
    );
    await expectLater(
      dexStore.waitForMonster(
        monsterID: 'not-arriving',
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
      levelsByMonsterID: {monsters[0].definition.id: 42, 'not-in-dex': 5},
    );
    expect(dexStore.party.first.level, 42);
    expect(dexStore.monsters[1].level, monsters[1].level);
    expect(dexStore.monsters, hasLength(monsters.length));
  });
}
