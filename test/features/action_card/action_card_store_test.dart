import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:snapmon/features/action_card/action_card_client.dart';
import 'package:snapmon/features/action_card/action_card_store.dart';
import 'package:snapmon/features/dex/dex_store.dart';

import '../../action_card_client_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  late FakeActionCards fakeActionCards;
  // 値を変えるとログインが変わった時と同じく購読し直す
  late ValueNotifier<int> sessionChanges;
  late ActionCardStore store;

  setUp(() {
    fakeActionCards = FakeActionCards();
    sessionChanges = ValueNotifier(0);
    store = ActionCardStore(
      client: fakeActionCards.client(),
      sessionChanges: sessionChanges,
      sampleActionCards: null,
    );
  });

  tearDown(() => store.dispose());

  test('表示の切り替えが false でも 技に結び付いていない購入があれば Action Card の画面の入口を出す', () async {
    fakeActionCards
      ..isActionCardsVisible.value = false
      ..purchases.value = [
        testActionCardPurchase(
          actionCardPurchaseID: 'p1',
          rank: 2,
          moveID: null,
        ),
      ];
    await pumpEventQueue();
    expect(store.isPurchaseEntryVisible, isFalse);
    expect(store.isScreenEntryVisible, isTrue);
  });

  test('購入がひとつも無く 表示の切り替えが false なら Action Card の画面の入口を出さない', () async {
    fakeActionCards.isActionCardsVisible.value = false;
    await pumpEventQueue();
    expect(store.isScreenEntryVisible, isFalse);
  });

  test('買い切った技は技のある購入から 技に結び付いていない購入は技の無い購入から出す', () async {
    fakeActionCards.purchases.value = [
      testActionCardPurchase(
        actionCardPurchaseID: 'p1',
        rank: 1,
        moveID: 'fire_1c',
      ),
      testActionCardPurchase(actionCardPurchaseID: 'p2', rank: 3, moveID: null),
      testActionCardPurchase(
        actionCardPurchaseID: 'p3',
        rank: 2,
        moveID: 'water_3',
      ),
    ];
    await pumpEventQueue();
    expect(store.ownedMoveIDs, ['fire_1c', 'water_3']);
    expect(
      store.unassignedPurchases.map(
        (purchase) => purchase.actionCardPurchaseID,
      ),
      ['p2'],
    );
  });

  test('アカウントが変わったら 前のアカウントの購入を出さない', () async {
    fakeActionCards.purchases.value = [
      testActionCardPurchase(
        actionCardPurchaseID: 'p1',
        rank: 1,
        moveID: 'fire_1c',
      ),
    ];
    await pumpEventQueue();
    expect(store.ownedMoveIDs, ['fire_1c']);
    fakeActionCards.purchases.value = const [];
    sessionChanges.value += 1;
    await pumpEventQueue();
    expect(store.ownedMoveIDs, isEmpty);
  });

  test('package の読み込みが並んだ時 先に始めた読み込みが後から失敗で返っても 後の成功を空で上書きしない', () async {
    // setUp の store の最初の読み込みは済ませてから、2 つの読み込みを待たせて走らせる
    await pumpEventQueue();
    final earlierCompleter = Completer<List<Package>>();
    final laterCompleter = Completer<List<Package>>();
    fakeActionCards.packagesCompleters.addAll([
      earlierCompleter,
      laterCompleter,
    ]);
    final earlierRefresh = store.refreshPackages();
    final laterRefresh = store.refreshPackages();
    laterCompleter.complete([testActionCardPackage(rank: 1)]);
    await laterRefresh;
    earlierCompleter.completeError(StateError('通信の失敗'));
    await earlierRefresh;
    expect(store.packages.map((package) => package.identifier), [
      'actioncard_rank1',
    ]);
  });

  test('package の読み込みが並んだ時 後に始めた読み込みが失敗しても 先に始めた読み込みの成功を反映する', () async {
    await pumpEventQueue();
    fakeActionCards.packages = const [];
    await store.refreshPackages();
    final earlierCompleter = Completer<List<Package>>();
    final laterCompleter = Completer<List<Package>>();
    fakeActionCards.packagesCompleters.addAll([
      earlierCompleter,
      laterCompleter,
    ]);
    final earlierRefresh = store.refreshPackages();
    final laterRefresh = store.refreshPackages();
    laterCompleter.completeError(StateError('通信の失敗'));
    await laterRefresh;
    earlierCompleter.complete([testActionCardPackage(rank: 2)]);
    await earlierRefresh;
    expect(store.packages.map((package) => package.identifier), [
      'actioncard_rank2',
    ]);
  });

  test('package の読み込みが並んだ時 先に始めた読み込みの成功が後から返っても 後の成功を上書きしない', () async {
    await pumpEventQueue();
    final earlierCompleter = Completer<List<Package>>();
    final laterCompleter = Completer<List<Package>>();
    fakeActionCards.packagesCompleters.addAll([
      earlierCompleter,
      laterCompleter,
    ]);
    final earlierRefresh = store.refreshPackages();
    final laterRefresh = store.refreshPackages();
    laterCompleter.complete([testActionCardPackage(rank: 3)]);
    await laterRefresh;
    earlierCompleter.complete([testActionCardPackage(rank: 1)]);
    await earlierRefresh;
    expect(store.packages.map((package) => package.identifier), [
      'actioncard_rank3',
    ]);
  });

  test('package の読み込みの途中でアカウントが変わっても 新しいアカウントで読み込みを始めて入口を出す', () async {
    final pendingCompleter = Completer<List<Package>>();
    fakeActionCards.packagesCompleters.add(pendingCompleter);
    final switchingStore = ActionCardStore(
      client: fakeActionCards.client(),
      sessionChanges: sessionChanges,
      sampleActionCards: null,
    );
    addTearDown(switchingStore.dispose);
    await pumpEventQueue();
    sessionChanges.value += 1;
    await pumpEventQueue();
    expect(switchingStore.isPurchaseEntryVisible, isTrue);
    // 前のアカウントの読み込みが後から返っても 新しいアカウントの一覧を変えない
    pendingCompleter.complete(const []);
    await pumpEventQueue();
    expect(switchingStore.isPurchaseEntryVisible, isTrue);
  });

  test('package の読み直しが例外で失敗したら 前に読めた一覧を残し 空が返ったら空にする', () async {
    await pumpEventQueue();
    expect(store.packages, hasLength(actionCardRanks.length));
    final failingCompleter = Completer<List<Package>>();
    fakeActionCards.packagesCompleters.add(failingCompleter);
    final failingRefresh = store.refreshPackages();
    failingCompleter.completeError(StateError('通信の失敗'));
    await failingRefresh;
    expect(store.packages, hasLength(actionCardRanks.length));
    fakeActionCards.packages = const [];
    await store.refreshPackages();
    expect(store.packages, isEmpty);
  });

  testWidgets('一度も package を読めないまま読み込みが失敗したら 30 秒後に読み直す', (tester) async {
    final failingCompleter = Completer<List<Package>>();
    fakeActionCards.packagesCompleters.add(failingCompleter);
    final retryingStore = ActionCardStore(
      client: fakeActionCards.client(),
      sessionChanges: ValueNotifier(0),
      sampleActionCards: null,
    );
    addTearDown(retryingStore.dispose);
    await tester.pump();
    failingCompleter.completeError(StateError('通信の失敗'));
    await tester.pump();
    expect(retryingStore.isPurchaseEntryVisible, isFalse);
    await tester.pump(const Duration(seconds: 29));
    expect(retryingStore.isPurchaseEntryVisible, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(retryingStore.isPurchaseEntryVisible, isTrue);
  });

  test('技のランクの表に端末の定義に無い技があれば 定義を 1 回だけ読み直す', () async {
    final sampleData = loadSampleDataFixture();
    var refreshCount = 0;
    final dexStore = DexStore(definitions: sampleData.definitions)
      ..connectServer(
        savePartyMonsterIDs: ({required monsterIDs}) async {},
        refreshDefinitions: () async => refreshCount += 1,
      );
    fakeActionCards.rankByMoveID.value = {'fire_1c': 1, 'newer_move': 2};
    await pumpEventQueue();
    final requestedMoveIDs = <String>{};
    await refreshDefinitionsForActionCardMoves(
      actionCardStore: store,
      dexStore: dexStore,
      requestedMoveIDs: requestedMoveIDs,
    );
    await refreshDefinitionsForActionCardMoves(
      actionCardStore: store,
      dexStore: dexStore,
      requestedMoveIDs: requestedMoveIDs,
    );
    expect(refreshCount, 1);
    expect(requestedMoveIDs, {'newer_move'});
  });
}
