import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final redeeming = store.redeem(moveId: 'fire_1c');
    fakeActionCards.creditsByRank.value = {3: 5};
    sessionChanges.value += 1;
    await pumpEventQueue();
    redeemCompleter.complete({1: 0});
    await redeeming;
    expect(store.creditsByRank, {3: 5});
    expect(store.ownedMoveIds, isEmpty);
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
