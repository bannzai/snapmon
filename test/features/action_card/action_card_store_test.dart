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

  test('表示の切り替えが false でも 技に換えていないカードがあれば Action Card の画面の入口を出す', () async {
    fakeActionCards
      ..isActionCardsVisible.value = false
      ..creditsByRank.value = {2: 1};
    await pumpEventQueue();
    expect(store.isPurchaseEntryVisible, isFalse);
    expect(store.isScreenEntryVisible, isTrue);
  });

  test('買い切りの応答を待っている間にアカウントが変わったら 返った残高を反映しない', () async {
    final redeemCompleter = Completer<Map<int, int>>();
    fakeActionCards
      ..creditsByRank.value = {1: 1}
      ..redeemCompleter = redeemCompleter;
    await pumpEventQueue();
    final redeeming = store.redeem(moveId: 'fire_1c', creditRank: 1);
    fakeActionCards.creditsByRank.value = {3: 5};
    sessionChanges.value += 1;
    await pumpEventQueue();
    redeemCompleter.complete({1: 0});
    await redeeming;
    expect(store.creditsByRank, {3: 5});
    expect(store.ownedMoveIds, isEmpty);
  });

  test('買い切りの応答より先に購読の新しい残高が届いたら 古い応答で上書きしない', () async {
    final redeemCompleter = Completer<Map<int, int>>();
    fakeActionCards
      ..creditsByRank.value = {1: 1}
      ..redeemCompleter = redeemCompleter;
    await pumpEventQueue();
    final redeeming = store.redeem(moveId: 'fire_1c', creditRank: 1);
    // 買い切りで 0 枚になった後に別の端末の購入で 1 枚足された値が、応答より先に届く
    fakeActionCards.creditsByRank.value = {1: 1, 2: 1};
    await pumpEventQueue();
    redeemCompleter.complete({1: 0});
    await redeeming;
    expect(store.creditsByRank, {1: 1, 2: 1});
  });

  test('購読の値が届く前に買い切りの応答が返ったら 返った残高を出す', () async {
    final redeemCompleter = Completer<Map<int, int>>();
    fakeActionCards
      ..creditsByRank.value = {1: 1}
      ..redeemCompleter = redeemCompleter;
    await pumpEventQueue();
    final redeeming = store.redeem(moveId: 'fire_1c', creditRank: 1);
    redeemCompleter.complete({1: 0});
    await redeeming;
    expect(store.creditsByRank, {1: 0});
    expect(store.ownedMoveIds, ['fire_1c']);
  });

  test('使うカードのランクが変わったと断られたら 断られた時の残高を出して 例外を投げ直し 技を足さない', () async {
    fakeActionCards
      ..creditsByRank.value = {1: 1}
      ..redeemErrors.add(
        const ActionCardCreditRankChangedException(
          creditRank: 2,
          creditsByRank: {1: 0, 2: 1},
        ),
      );
    await pumpEventQueue();
    await expectLater(
      store.redeem(moveId: 'fire_1c', creditRank: 1),
      throwsA(isA<ActionCardCreditRankChangedException>()),
    );
    expect(store.creditsByRank, {1: 0, 2: 1});
    expect(store.ownedMoveIds, isEmpty);
  });

  test('断られるより先に購読の新しい残高が届いていたら 断られた時の残高で上書きしない', () async {
    final redeemCompleter = Completer<Map<int, int>>();
    fakeActionCards
      ..creditsByRank.value = {1: 1}
      ..redeemCompleter = redeemCompleter;
    await pumpEventQueue();
    final redeeming = store.redeem(moveId: 'fire_1c', creditRank: 1);
    fakeActionCards.creditsByRank.value = {1: 0, 2: 1, 3: 1};
    await pumpEventQueue();
    redeemCompleter.completeError(
      const ActionCardCreditRankChangedException(
        creditRank: 2,
        creditsByRank: {1: 0, 2: 1},
      ),
    );
    await expectLater(
      redeeming,
      throwsA(isA<ActionCardCreditRankChangedException>()),
    );
    expect(store.creditsByRank, {1: 0, 2: 1, 3: 1});
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
        savePartyMonsterIds: ({required monsterIds}) async {},
        refreshDefinitions: () async => refreshCount += 1,
      );
    fakeActionCards.rankByMoveId.value = {'fire_1c': 1, 'newer_move': 2};
    await pumpEventQueue();
    final requestedMoveIds = <String>{};
    await refreshDefinitionsForActionCardMoves(
      actionCardStore: store,
      dexStore: dexStore,
      requestedMoveIds: requestedMoveIds,
    );
    await refreshDefinitionsForActionCardMoves(
      actionCardStore: store,
      dexStore: dexStore,
      requestedMoveIds: requestedMoveIds,
    );
    expect(refreshCount, 1);
    expect(requestedMoveIds, {'newer_move'});
  });
}
