import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:snapmon/features/action_card/action_card_client.dart';
import 'package:snapmon/features/action_card/action_card_screen.dart';
import 'package:snapmon/features/action_card/action_card_store.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/profile/profile_screen.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../action_card_client_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../pvp_client_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// 技ごとの商品の表の見本。100 円の商品に 2 つ (fire_1c・water_1b)、300 円の商品に 1 つ (water_3)。
  const sampleProductIDByMoveID = {'fire_1c': testCheapActionCardProductID, 'water_1b': testCheapActionCardProductID, 'water_3': testExpensiveActionCardProductID};

  late FakeActionCards fakeActionCards;
  late DexStore dexStore;

  setUp(() {
    fakeActionCards = FakeActionCards();
    dexStore = DexStore(definitions: sampleData.definitions)
      ..replaceAll(monsters: sampleData.monsters);
  });

  /// Action Card の [home] を、アプリと同じく Navigator の外の [ActionCardScope] の下で開く。
  Future<void> pump({
    required WidgetTester tester,
    required Widget home,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = ActionCardStore(
      client: fakeActionCards.client(),
      sessionChanges: ChangeNotifier(),
      sampleActionCards: null,
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) =>
            ActionCardScope(actionCardStore: store, child: child!),
        home: home,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 図鑑の詳細 (見本の mugmon。Lv.7 で技の枠は fire_1・steel_1・fire_1b・steel_1b)。
  Widget dexDetail() => ResultScreen(
    monster: sampleData.monsterById(monsterId: 'sample-mugmon'),
    dexStore: dexStore,
    origin: ResultScreenOrigin.dex,
    cardSharer: fakeCardSharer(
      calls: RecordedShareCalls(),
      artImage: null,
      shareResultStatus: ShareResultStatus.success,
    ),
  );

  group('購入の入口', () {
    testWidgets('表示の切り替えが true で package がある時は 図鑑の詳細に入口を出す', (tester) async {
      await pump(tester: tester, home: dexDetail());
      expect(find.byKey(const Key('action-card-entry-dex')), findsOneWidget);
    });

    testWidgets('表示の切り替えが false の時は 入口も節も出さない', (tester) async {
      fakeActionCards.isActionCardsVisible.value = false;
      await pump(tester: tester, home: dexDetail());
      expect(find.byKey(const Key('action-card-entry-dex')), findsNothing);
      expect(find.text('Action Card の技'), findsNothing);
    });

    testWidgets('売っている package が無い時は 入口を出さない', (tester) async {
      fakeActionCards.packages = const [];
      await pump(tester: tester, home: dexDetail());
      expect(find.byKey(const Key('action-card-entry-dex')), findsNothing);
    });

    testWidgets('課金を使えないビルド (Web) では 入口を出さない', (tester) async {
      fakeActionCards.isPurchaseSupported = false;
      await pump(tester: tester, home: dexDetail());
      expect(find.byKey(const Key('action-card-entry-dex')), findsNothing);
    });

    testWidgets('起動直後の package の読み込みが例外で失敗しても 図鑑の詳細を開いた時に読み直して入口を出す', (
      tester,
    ) async {
      final failingCompleter = Completer<List<Package>>();
      fakeActionCards.packagesCompleters.add(failingCompleter);
      final store = ActionCardStore(
        client: fakeActionCards.client(),
        sessionChanges: ChangeNotifier(),
        sampleActionCards: null,
      );
      addTearDown(store.dispose);
      await tester.pump();
      // ストアが起動直後の読み込みを始めてから失敗させる (待つ側がいない間に失敗させるとテストの外へ漏れるため)
      failingCompleter.completeError(StateError('通信の失敗'));
      await tester.pumpAndSettle();
      expect(store.isPurchaseEntryVisible, isFalse);
      tester.view
        ..physicalSize = const Size(390, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: snapmonThemeData(),
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              ActionCardScope(actionCardStore: store, child: child!),
          home: dexDetail(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-card-entry-dex')), findsOneWidget);
    });

    testWidgets('課金を使えないビルドでも 買い切った技があれば Action Card の画面に入れるが 買うボタンは出さない', (
      tester,
    ) async {
      fakeActionCards
        ..isPurchaseSupported = false
        ..productIDByMoveID.value = sampleProductIDByMoveID
        ..purchases.value = [
          testActionCardPurchase(
            actionCardPurchaseID: 'p1',
            productID: testExpensiveActionCardProductID,
            moveID: 'water_3',
          ),
        ];
      await pump(tester: tester, home: dexDetail());
      await tester.tap(find.byKey(const Key('action-card-entry-dex')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-card-buy-fire_1c')), findsNothing);
      expect(find.text('今は技を売っていません'), findsOneWidget);
      expect(
        find.byKey(const Key('action-card-owned-water_3')),
        findsOneWidget,
      );
    });
  });

  group('プロフィールの入口', () {
    /// プロフィール画面 (アイコンの写真は選ばない)。
    Widget profile() => ProfileScreen(
      initialProfile: (displayName: 'トレーナー', iconPath: null),
      onProfileChanged: ({required profile}) {},
      pvpClient: signedOutPvpClient(calls: RecordedPvpCalls()),
      pickPhoto: () async => null,
      preparePhoto: ({required sourceBytes}) async => sourceBytes,
      dexStore: dexStore,
    );

    testWidgets('表示の切り替えが true で package がある時は 入口を出す', (tester) async {
      await pump(tester: tester, home: profile());
      expect(
        find.byKey(const Key('action-card-entry-profile')),
        findsOneWidget,
      );
    });

    testWidgets('表示の切り替えが false の時は 入口を出さない', (tester) async {
      fakeActionCards.isActionCardsVisible.value = false;
      await pump(tester: tester, home: profile());
      expect(find.byKey(const Key('action-card-entry-profile')), findsNothing);
    });

    testWidgets('売っている package が無い時は 入口を出さない', (tester) async {
      fakeActionCards.packages = const [];
      await pump(tester: tester, home: profile());
      expect(find.byKey(const Key('action-card-entry-profile')), findsNothing);
    });

    testWidgets('課金を使えないビルド (Web) では 入口を出さない', (tester) async {
      fakeActionCards.isPurchaseSupported = false;
      await pump(tester: tester, home: profile());
      expect(find.byKey(const Key('action-card-entry-profile')), findsNothing);
    });

    testWidgets('起動直後の package の読み込みが例外で失敗しても 開いた時に読み直して入口を出す', (tester) async {
      final failingCompleter = Completer<List<Package>>();
      fakeActionCards.packagesCompleters.add(failingCompleter);
      final store = ActionCardStore(
        client: fakeActionCards.client(),
        sessionChanges: ChangeNotifier(),
        sampleActionCards: null,
      );
      addTearDown(store.dispose);
      await tester.pump();
      // ストアが起動直後の読み込みを始めてから失敗させる (待つ側がいない間に失敗させるとテストの外へ漏れるため)
      failingCompleter.completeError(StateError('通信の失敗'));
      await tester.pump();
      expect(store.isPurchaseEntryVisible, isFalse);
      await tester.pumpWidget(
        MaterialApp(
          theme: snapmonThemeData(),
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              ActionCardScope(actionCardStore: store, child: child!),
          home: profile(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('action-card-entry-profile')),
        findsOneWidget,
      );
    });
  });

  group('技を選んで買う', () {
    testWidgets('買い切っていない技を 今の値段を付けて並べ 買い切った技は出さない', (tester) async {
      fakeActionCards
        ..productIDByMoveID.value = sampleProductIDByMoveID
        ..purchases.value = [
          testActionCardPurchase(
            actionCardPurchaseID: 'p0',
            productID: testCheapActionCardProductID,
            moveID: 'water_1b',
          ),
        ];
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      expect(find.byKey(const Key('action-card-buy-fire_1c')), findsOneWidget);
      expect(find.text('¥100'), findsOneWidget);
      expect(find.text('¥300'), findsOneWidget);
      // 値段の段の名前 (ランク) は出さない
      expect(find.textContaining('ランク'), findsNothing);
      expect(find.byKey(const Key('action-card-buy-water_1b')), findsNothing);
      expect(
        find.byKey(const Key('action-card-owned-water_1b')),
        findsOneWidget,
      );
      // 技に結び付いていない購入が無い時は 選び直しの節を出さない
      expect(find.text('受け取っていない Action Card'), findsNothing);
    });

    testWidgets('売っていない商品の技は 値段を出せないため並べない', (tester) async {
      fakeActionCards
        ..productIDByMoveID.value = sampleProductIDByMoveID
        ..packages = [testActionCardPackage(productID: testCheapActionCardProductID)];
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      expect(find.byKey(const Key('action-card-buy-fire_1c')), findsOneWidget);
      expect(find.byKey(const Key('action-card-buy-water_3')), findsNothing);
    });

    testWidgets('技ごとの商品の表がまだ無い間は 準備中を出し 技を並べない', (tester) async {
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      expect(find.textContaining('技の値段を準備しています'), findsOneWidget);
      expect(find.byKey(const Key('action-card-buy-fire_1c')), findsNothing);
    });

    testWidgets('技を選んで買うと 技を控えてから その技の商品を買い 控えの購入が届いたら手に入れたと出す', (
      tester,
    ) async {
      fakeActionCards.productIDByMoveID.value = sampleProductIDByMoveID;
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      await tester.tap(find.byKey(const Key('action-card-buy-water_3')));
      await tester.pumpAndSettle();
      expect(find.text('¥300 で買う'), findsOneWidget);
      await tester.tap(find.byKey(const Key('action-card-purchase-buy')));
      await tester.pump();
      expect(fakeActionCards.reservedMoves, [(moveID: 'water_3', productID: testExpensiveActionCardProductID)]);
      expect(fakeActionCards.purchasedPackageIds, ['actioncard_test300']);
      expect(find.text('技を受け取っています'), findsOneWidget);

      // 別の端末の購入 (控えの ID が違う) が届いても 自分の購入が届いたとは出さない
      fakeActionCards.purchases.value = [
        testActionCardPurchase(
          actionCardPurchaseID: 'other',
          productID: testCheapActionCardProductID,
          moveID: 'fire_1c',
          actionCardMoveReservationID: 'reservation-from-other-device',
        ),
      ];
      await tester.pump();
      expect(find.text('技を受け取っています'), findsOneWidget);

      fakeActionCards.purchases.value = [
        ...fakeActionCards.purchases.value,
        testActionCardPurchase(
          actionCardPurchaseID: 'p1',
          productID: testExpensiveActionCardProductID,
          moveID: 'water_3',
          actionCardMoveReservationID: 'reservation-1',
        ),
      ];
      await tester.pump();
      expect(find.text('おおつなみ を手に入れました'), findsOneWidget);
      await tester.tap(find.byKey(const Key('action-card-purchase-close')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('action-card-owned-water_3')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('action-card-buy-water_3')), findsNothing);
    });

    testWidgets('控えた技を受け取れなかった購入が届いたら 選び直しの案内を出し 画面に選び直しの節を出す', (tester) async {
      fakeActionCards.productIDByMoveID.value = sampleProductIDByMoveID;
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      await tester.tap(find.byKey(const Key('action-card-buy-fire_1c')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-card-purchase-buy')));
      await tester.pump();
      // 購入が届くまでの間に fire_1c の商品が変わった
      fakeActionCards.purchases.value = [
        testActionCardPurchase(
          actionCardPurchaseID: 'p1',
          productID: testCheapActionCardProductID,
          moveID: null,
          actionCardMoveReservationID: 'reservation-1',
        ),
      ];
      await tester.pump();
      expect(
        find.byKey(const Key('action-card-purchase-unassigned')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('action-card-purchase-close')));
      await tester.pumpAndSettle();
      expect(find.text('受け取っていない Action Card'), findsOneWidget);
      expect(
        find.byKey(const Key('action-card-unassigned-p1')),
        findsOneWidget,
      );
      // 受け取っていない購入は 買った商品の値段で出す
      expect(find.text('¥100 の Action Card'), findsOneWidget);
    });

    testWidgets('値段を出している間に技の商品が変わって控えを断られたら 買わずに 値段が変わったと出す', (tester) async {
      fakeActionCards
        ..productIDByMoveID.value = sampleProductIDByMoveID
        ..reserveErrors.add(
          const ActionCardMoveProductChangedException(
            productID: testExpensiveActionCardProductID,
          ),
        );
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      await tester.tap(find.byKey(const Key('action-card-buy-fire_1c')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-card-purchase-buy')));
      await tester.pump();
      expect(fakeActionCards.purchasedPackageIds, isEmpty);
      expect(
        find.byKey(const Key('action-card-purchase-price-changed')),
        findsOneWidget,
      );
      // 新しい商品が購読で届くと 新しい値段で買い直せる
      fakeActionCards.productIDByMoveID.value = {
        ...sampleProductIDByMoveID,
        'fire_1c': testExpensiveActionCardProductID,
      };
      await tester.pump();
      expect(find.text('¥300 で買う'), findsOneWidget);
    });

    testWidgets('支払いが保留になったら 支払いを待つ案内を出す', (tester) async {
      fakeActionCards
        ..productIDByMoveID.value = sampleProductIDByMoveID
        ..purchaseResult = TicketPurchaseResult.pending;
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      await tester.tap(find.byKey(const Key('action-card-buy-fire_1c')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-card-purchase-buy')));
      await tester.pump();
      expect(find.textContaining('支払いの完了を待っています'), findsOneWidget);
    });

    testWidgets('ストアの購入をやめたら 買う前の画面に戻る', (tester) async {
      fakeActionCards
        ..productIDByMoveID.value = sampleProductIDByMoveID
        ..purchaseResult = TicketPurchaseResult.cancelled;
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      await tester.tap(find.byKey(const Key('action-card-buy-fire_1c')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-card-purchase-buy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-card-purchase-buy')), findsOneWidget);
      expect(find.text('技を受け取っています'), findsNothing);
    });

    testWidgets('属性で絞り込むと その属性の技だけを出す', (tester) async {
      fakeActionCards.productIDByMoveID.value = sampleProductIDByMoveID;
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      await tester.tap(find.byKey(const Key('action-card-filter-water')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-card-buy-fire_1c')), findsNothing);
      expect(find.byKey(const Key('action-card-buy-water_3')), findsOneWidget);
    });
  });

  group('技に結び付いていない購入で選び直す', () {
    testWidgets('購入した商品と同じ商品で持っていない技だけを出し 選ぶと購入に結び付ける', (tester) async {
      fakeActionCards
        ..productIDByMoveID.value = sampleProductIDByMoveID
        ..purchases.value = [
          testActionCardPurchase(
            actionCardPurchaseID: 'p0',
            productID: testCheapActionCardProductID,
            moveID: 'water_1b',
          ),
          testActionCardPurchase(
            actionCardPurchaseID: 'p1',
            productID: testCheapActionCardProductID,
            moveID: null,
          ),
        ];
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      await tester.tap(
        find.byKey(const Key('action-card-unassigned-choose-p1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('この Action Card で受け取る技'), findsOneWidget);
      expect(
        find.byKey(const Key('action-card-assign-fire_1c')),
        findsOneWidget,
      );
      // 持っている技 (water_1b) と 購入と違う商品の技 (water_3) は出さない
      expect(
        find.byKey(const Key('action-card-assign-water_1b')),
        findsNothing,
      );
      expect(find.byKey(const Key('action-card-assign-water_3')), findsNothing);
      await tester.tap(find.byKey(const Key('action-card-assign-fire_1c')));
      await tester.pumpAndSettle();
      expect(fakeActionCards.assignedMoves, [
        (actionCardPurchaseID: 'p1', moveID: 'fire_1c'),
      ]);
      expect(find.text('アイロンがけ を受け取りました'), findsOneWidget);
    });

    testWidgets('断られたら 失敗を出して選ぶ画面に残る', (tester) async {
      fakeActionCards
        ..productIDByMoveID.value = sampleProductIDByMoveID
        ..purchases.value = [
          testActionCardPurchase(
            actionCardPurchaseID: 'p1',
            productID: testCheapActionCardProductID,
            moveID: null,
          ),
        ]
        ..assignErrors.add(StateError('この Action Card では受け取れません'));
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      await tester.tap(
        find.byKey(const Key('action-card-unassigned-choose-p1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-card-assign-fire_1c')));
      await tester.pumpAndSettle();
      expect(find.textContaining('受け取れません'), findsOneWidget);
      expect(
        find.byKey(const Key('action-card-assign-fire_1c')),
        findsOneWidget,
      );
    });
  });

  group('属性の絞り込み', () {
    testWidgets('絞り込んだ属性の最後の技を買い切ると すべてに戻して残りの技を出す', (tester) async {
      fakeActionCards.productIDByMoveID.value = {'fire_1c': testCheapActionCardProductID, 'water_3': testExpensiveActionCardProductID};
      await pump(
        tester: tester,
        home: ActionCardScreen(dexStore: dexStore),
      );
      await tester.tap(find.byKey(const Key('action-card-filter-fire')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-card-buy-water_3')), findsNothing);
      // 炎の技 (fire_1c) を買い切った後の購読の値を流す
      fakeActionCards.purchases.value = [
        testActionCardPurchase(
          actionCardPurchaseID: 'p1',
          productID: testCheapActionCardProductID,
          moveID: 'fire_1c',
        ),
      ];
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-card-filter-fire')), findsNothing);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'すべて'))
            .selected,
        isTrue,
      );
      expect(find.byKey(const Key('action-card-buy-water_3')), findsOneWidget);
      // 後で炎の技がまた買えるようになっても 前の絞り込みは戻らない
      fakeActionCards.purchases.value = const [];
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'すべて'))
            .selected,
        isTrue,
      );
      expect(find.byKey(const Key('action-card-buy-water_3')), findsOneWidget);
    });
  });

  group('図鑑の詳細で覚えさせる・忘れさせる', () {
    testWidgets('覚えさせる技を選ぶ時に 外れる技を出し 選ぶと覚えさせて技の枠に出す', (tester) async {
      fakeActionCards
        ..purchases.value = [
          testActionCardPurchase(
            actionCardPurchaseID: 'p1',
            productID: testExpensiveActionCardProductID,
            moveID: 'water_3',
          ),
        ]
        ..monsterMoveIdsResult = ['water_3'];
      await pump(tester: tester, home: dexDetail());
      await tester.tap(find.byKey(const Key('action-card-teach')));
      await tester.pumpAndSettle();
      // Lv.7 の mugmon の枠は fire_1・steel_1・fire_1b・steel_1b で、一番古い fire_1 (ほかほかタッチ) が外れる
      expect(find.text('ほかほかタッチ をわすれた'), findsOneWidget);
      await tester.tap(find.byKey(const Key('action-card-teach-water_3')));
      await tester.pumpAndSettle();
      expect(fakeActionCards.taughtMoves, [
        (monsterId: 'sample-mugmon', moveId: 'water_3'),
      ]);
      expect(
        dexStore.monsters
            .firstWhere((monster) => monster.definition.id == 'sample-mugmon')
            .actionCardMoveIds,
        ['water_3'],
      );
      expect(find.byKey(const Key('move-chip-water_3')), findsOneWidget);
      expect(find.byKey(const Key('move-chip-fire_1')), findsNothing);
      expect(
        find.byKey(const Key('action-card-taught-water_3')),
        findsOneWidget,
      );
    });

    testWidgets('忘れさせると 技の枠を元に戻す', (tester) async {
      dexStore.updateActionCardMoveIds(
        monsterId: 'sample-mugmon',
        actionCardMoveIds: ['water_3'],
      );
      fakeActionCards
        ..purchases.value = [
          testActionCardPurchase(
            actionCardPurchaseID: 'p1',
            productID: testExpensiveActionCardProductID,
            moveID: 'water_3',
          ),
        ]
        ..monsterMoveIdsResult = const [];
      await pump(tester: tester, home: dexDetail());
      await tester.tap(find.byKey(const Key('action-card-forget-water_3')));
      await tester.pumpAndSettle();
      expect(fakeActionCards.forgottenMoves, [
        (monsterId: 'sample-mugmon', moveId: 'water_3'),
      ]);
      expect(find.byKey(const Key('move-chip-fire_1')), findsOneWidget);
      expect(find.byKey(const Key('move-chip-water_3')), findsNothing);
    });

    testWidgets('表示の切り替えが false でも 覚えさせた技があれば忘れさせられる', (tester) async {
      dexStore.updateActionCardMoveIds(
        monsterId: 'sample-mugmon',
        actionCardMoveIds: ['water_3'],
      );
      fakeActionCards.isActionCardsVisible.value = false;
      await pump(tester: tester, home: dexDetail());
      expect(
        find.byKey(const Key('action-card-forget-water_3')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('action-card-entry-dex')), findsNothing);
    });
  });
}
