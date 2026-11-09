import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:snapmon/features/action_card/action_card_screen.dart';
import 'package:snapmon/features/action_card/action_card_store.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../action_card_client_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// 技のランクの表の見本。ランク 1 に 2 つ (威力 40 と 35)、ランク 3 に 1 つ。
  const sampleRankByMoveId = {'fire_1c': 1, 'water_1b': 1, 'water_3': 3};

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

    testWidgets('課金を使えないビルドでも 買い切った技があれば Action Card の画面に入れるが 買うボタンは出さない', (
      tester,
    ) async {
      fakeActionCards
        ..isPurchaseSupported = false
        ..ownedMoveIds.value = ['water_3'];
      await pump(tester: tester, home: dexDetail());
      await tester.tap(find.byKey(const Key('action-card-entry-dex')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-card-buy')), findsNothing);
      expect(
        find.byKey(const Key('action-card-owned-water_3')),
        findsOneWidget,
      );
    });
  });

  group('購入画面', () {
    testWidgets('3 つのランクの価格と そのランクの技の数と例の技を出す', (tester) async {
      fakeActionCards.rankByMoveId.value = sampleRankByMoveId;
      await pump(
        tester: tester,
        home: ActionCardScreen(definitions: sampleData.definitions),
      );
      await tester.tap(find.byKey(const Key('action-card-buy')));
      await tester.pumpAndSettle();
      expect(find.text('ランク 1  ¥100'), findsOneWidget);
      expect(find.text('ランク 2  ¥200'), findsOneWidget);
      expect(find.text('ランク 3  ¥300'), findsOneWidget);
      expect(find.text('このランクの技 2 個'), findsOneWidget);
      expect(find.text('このランクの技 0 個'), findsOneWidget);
      // ランク 1 の例は威力の大きい アイロンがけ (fire_1c、威力 45)
      expect(find.text('たとえば アイロンがけ'), findsOneWidget);
      expect(find.text('たとえば おおつなみ'), findsOneWidget);
    });

    testWidgets('技のランクの表がまだ無い間は 準備中を出し 買うボタンを押せない', (tester) async {
      await pump(
        tester: tester,
        home: ActionCardScreen(definitions: sampleData.definitions),
      );
      await tester.tap(find.byKey(const Key('action-card-buy')));
      await tester.pumpAndSettle();
      expect(find.textContaining('技のランクを準備しています'), findsWidgets);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const Key('action-card-package-1')),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('カードを持ったまま買っても 残高が増えるまでは届いたと出さない', (tester) async {
      fakeActionCards
        ..rankByMoveId.value = sampleRankByMoveId
        ..creditsByRank.value = {1: 1};
      await pump(
        tester: tester,
        home: ActionCardScreen(definitions: sampleData.definitions),
      );
      await tester.tap(find.byKey(const Key('action-card-buy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-card-package-1')));
      await tester.pump();
      expect(fakeActionCards.purchasedPackageIds, ['actioncard_rank1']);
      expect(find.text('カードを受け取っています'), findsOneWidget);
      expect(find.text('カードが届きました'), findsNothing);

      fakeActionCards.creditsByRank.value = {1: 2};
      await tester.pump();
      expect(find.text('カードが届きました'), findsOneWidget);
      expect(find.byKey(const Key('action-card-choose-move')), findsOneWidget);
    });

    testWidgets('別のランクの残高が増えても 買ったランクが増えるまでは届いたと出さない', (tester) async {
      fakeActionCards.rankByMoveId.value = sampleRankByMoveId;
      await pump(
        tester: tester,
        home: ActionCardScreen(definitions: sampleData.definitions),
      );
      await tester.tap(find.byKey(const Key('action-card-buy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-card-package-3')));
      await tester.pump();
      fakeActionCards.creditsByRank.value = {1: 1};
      await tester.pump();
      expect(find.text('カードが届きました'), findsNothing);
    });

    testWidgets('支払いが保留になったら 支払いを待つ案内を出す', (tester) async {
      fakeActionCards
        ..rankByMoveId.value = sampleRankByMoveId
        ..purchaseResult = TicketPurchaseResult.pending;
      await pump(
        tester: tester,
        home: ActionCardScreen(definitions: sampleData.definitions),
      );
      await tester.tap(find.byKey(const Key('action-card-buy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('action-card-package-2')));
      await tester.pump();
      expect(find.textContaining('支払いの完了を待っています'), findsOneWidget);
    });
  });

  group('技を選んで買い切る', () {
    testWidgets('持っているカードのランク以下の技だけを出し 使うカードを確かめてから買い切る', (tester) async {
      fakeActionCards
        ..rankByMoveId.value = sampleRankByMoveId
        ..creditsByRank.value = {1: 1};
      await pump(
        tester: tester,
        home: ActionCardScreen(definitions: sampleData.definitions),
      );
      expect(
        find.byKey(const Key('action-card-redeem-fire_1c')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('action-card-redeem-water_3')), findsNothing);

      await tester.tap(find.byKey(const Key('action-card-redeem-fire_1c')));
      await tester.pumpAndSettle();
      expect(find.text('ランク 1 のカードを 1 枚使います。買い切った後は取り消せません。'), findsOneWidget);
      await tester.tap(find.byKey(const Key('action-card-redeem-confirm')));
      await tester.pumpAndSettle();
      expect(fakeActionCards.redeemedMoveIds, ['fire_1c']);
      expect(find.text('アイロンがけ を買い切りました'), findsOneWidget);
    });

    testWidgets('確かめる画面でやめたら 買い切らない', (tester) async {
      fakeActionCards
        ..rankByMoveId.value = sampleRankByMoveId
        ..creditsByRank.value = {3: 1};
      await pump(
        tester: tester,
        home: ActionCardScreen(definitions: sampleData.definitions),
      );
      await tester.tap(find.byKey(const Key('action-card-redeem-water_3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('やめる'));
      await tester.pumpAndSettle();
      expect(fakeActionCards.redeemedMoveIds, isEmpty);
    });

    testWidgets('属性で絞り込むと その属性の技だけを出す', (tester) async {
      fakeActionCards
        ..rankByMoveId.value = sampleRankByMoveId
        ..creditsByRank.value = {3: 1};
      await pump(
        tester: tester,
        home: ActionCardScreen(definitions: sampleData.definitions),
      );
      await tester.tap(find.byKey(const Key('action-card-filter-water')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('action-card-redeem-fire_1c')), findsNothing);
      expect(
        find.byKey(const Key('action-card-redeem-water_3')),
        findsOneWidget,
      );
    });
  });

  group('図鑑の詳細で覚えさせる・忘れさせる', () {
    testWidgets('覚えさせる技を選ぶ時に 外れる技を出し 選ぶと覚えさせて技の枠に出す', (tester) async {
      fakeActionCards
        ..ownedMoveIds.value = ['water_3']
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
            .firstWhere(
              (monster) => monster.definition.id == 'sample-mugmon',
            )
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
        ..ownedMoveIds.value = ['water_3']
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
