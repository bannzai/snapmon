import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/features/capture/generation_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/capture/ticket_purchase_sheet.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../monster_generator_fixture.dart';
import '../../pvp_client_fixture.dart';
import '../../sample_data_fixture.dart';

/// サーバーが上限で断った時の文言の見本。
const String _dailyLimitMessage = '今日の生成は 20 回までです';

void main() {
  final sampleData = loadSampleDataFixture();
  late RecordedGenerationCalls calls;

  setUp(() => calls = RecordedGenerationCalls());

  /// 1 回目の生成を上限で断り、2 回目以降は生成に失敗した結果を返す [MonsterGenerator] を返す。
  /// [isAlwaysLimited] が true なら毎回上限で断る。
  MonsterGenerator limitedGenerator({
    required List<Package> ticketPackages,
    Future<List<Package>> Function()? fetchTicketPackages,
    Future<TicketPurchaseResult> Function({required Package package})?
    purchaseTicketPackage,
    Stream<int>? generationTickets,
    bool isAlwaysLimited = false,
  }) {
    var requestCount = 0;
    return fakeMonsterGenerator(
      calls: calls,
      albumPhoto: null,
      uploadError: null,
      requestGeneration: ({required requestId}) async {
        if (isAlwaysLimited || ++requestCount == 1) {
          throw const GenerationDailyLimitException(
            message: _dailyLimitMessage,
          );
        }
        return GenerationResult(
          requestId: requestId,
          status: GenerationStatus.failed,
          monsterId: null,
          rejectionReason: null,
        );
      },
      fetchGeneration: ({required requestId}) =>
          throw StateError('fetchGeneration は呼ばない'),
      ticketPackages: ticketPackages,
      fetchTicketPackages: fetchTicketPackages,
      purchaseTicketPackage: purchaseTicketPackage,
      generationTickets: generationTickets,
    );
  }

  /// [generator] の生成の画面を開き、上限のエラーまで進める。
  Future<void> pumpUntilDailyLimit({
    required WidgetTester tester,
    required MonsterGenerator generator,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GenerationScreen(
          sourcePhoto: testPhotoBytes,
          photoSource: GenerationPhotoSource.album,
          cropsWhenSubjectNotFound: true,
          monsterGenerator: generator,
          dexStore: DexStore(definitions: sampleData.definitions),
          cardSharer: fakeCardSharer(
            calls: RecordedShareCalls(),
            artImage: null,
            shareResultStatus: ShareResultStatus.success,
          ),
          startsFirstBattle: false,
          sampleData: sampleData,
          pvpClient: signedOutPvpClient(calls: RecordedPvpCalls()),
          battleRecorder: fakeBattleRecorder(
            calls: RecordedBattleCalls(),
            startBattleRecord: () async => null,
            recordedLevels: const {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 計測の `ticket_purchase` の `step` (送った順)。
  List<Object?> ticketPurchaseSteps() => [
    for (final logged in calls.loggedEvents)
      if (logged.event == AnalyticsEvent.ticketPurchase)
        logged.parameters?['step'],
  ];

  testWidgets('売っている package が無い間は 購入画面を出さず 上限のエラーの表示のまま', (tester) async {
    await pumpUntilDailyLimit(
      tester: tester,
      generator: limitedGenerator(ticketPackages: const []),
    );

    expect(find.text(_dailyLimitMessage), findsOneWidget);
    expect(find.text('生成チケット'), findsNothing);
    expect(ticketPurchaseSteps(), isEmpty);
  });

  testWidgets('package の取得中に再試行して また上限に当たっても 購入画面を重ねない', (tester) async {
    await pumpUntilDailyLimit(
      tester: tester,
      generator: limitedGenerator(
        ticketPackages: const [],
        fetchTicketPackages: () async {
          await Future<void>.delayed(const Duration(seconds: 1));
          return const [testTicketPackage];
        },
        isAlwaysLimited: true,
      ),
    );

    await tester.tap(find.text('もう一度試す'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.text('生成チケット'), findsOneWidget);
  });

  testWidgets('ストアの購入の途中は 購入画面をドラッグしても閉じない', (tester) async {
    final purchase = Completer<TicketPurchaseResult>();
    await pumpUntilDailyLimit(
      tester: tester,
      generator: limitedGenerator(
        ticketPackages: const [testTicketPackage],
        purchaseTicketPackage: ({required package}) => purchase.future,
      ),
    );

    await tester.tap(find.textContaining('¥200'));
    await tester.pump();
    await tester.drag(find.text('生成チケット'), const Offset(0, 600));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('生成チケット'), findsOneWidget);
    purchase.complete(TicketPurchaseResult.cancelled);
    await tester.pump(const Duration(seconds: 1));
  });

  /// [generator] で撮るタブの残高の表示を開く。
  Future<void> pumpGenerationTicketBalance({
    required WidgetTester tester,
    required MonsterGenerator generator,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: GenerationTicketBalance(monsterGenerator: generator),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('開いた時に package を読めなくても 残高が増えた時に読み直して残高を出す', (tester) async {
    final generationTickets = StreamController<int>.broadcast();
    addTearDown(generationTickets.close);
    var fetchCount = 0;
    await pumpGenerationTicketBalance(
      tester: tester,
      generator: limitedGenerator(
        ticketPackages: const [],
        fetchTicketPackages: () async {
          if (++fetchCount == 1) {
            throw StateError('読めない');
          }
          return const [testTicketPackage];
        },
        generationTickets: generationTickets.stream,
      ),
    );
    expect(find.textContaining('チケット'), findsNothing);

    generationTickets.add(10);
    await tester.pump();
    await tester.pump();

    expect(find.text('チケット 10 枚'), findsOneWidget);
  });

  testWidgets('閉じ直した後は アプリに戻った時に残高を消す', (tester) async {
    final generationTickets = StreamController<int>.broadcast();
    addTearDown(generationTickets.close);
    var isSelling = true;
    await pumpGenerationTicketBalance(
      tester: tester,
      generator: limitedGenerator(
        ticketPackages: const [],
        fetchTicketPackages: () async =>
            isSelling ? const [testTicketPackage] : const [],
        generationTickets: generationTickets.stream,
      ),
    );
    generationTickets.add(10);
    await tester.pump();
    await tester.pump();
    expect(find.text('チケット 10 枚'), findsOneWidget);

    isSelling = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('チケット'), findsNothing);
  });

  testWidgets('package がある時は 上限の後に購入画面を出し ストアの価格を出す', (tester) async {
    await pumpUntilDailyLimit(
      tester: tester,
      generator: limitedGenerator(ticketPackages: const [testTicketPackage]),
    );

    expect(find.text('生成チケット'), findsOneWidget);
    expect(find.textContaining('¥200'), findsOneWidget);
    expect(ticketPurchaseSteps(), ['shown']);
  });

  testWidgets('購入の後に残高が増えたら 同じ写真を置き直して生成をやり直せる', (tester) async {
    final generationTickets = StreamController<int>.broadcast();
    addTearDown(generationTickets.close);
    await pumpUntilDailyLimit(
      tester: tester,
      generator: limitedGenerator(
        ticketPackages: const [testTicketPackage],
        purchaseTicketPackage: ({required package}) async =>
            TicketPurchaseResult.purchased,
        generationTickets: generationTickets.stream,
      ),
    );

    await tester.tap(find.textContaining('¥200'));
    await tester.pump();
    expect(find.text('チケットを受け取っています'), findsOneWidget);
    expect(find.text('この写真で生成する'), findsNothing);

    generationTickets.add(10);
    await tester.pump();
    expect(find.text('チケット 10 枚'), findsOneWidget);

    await tester.tap(find.text('この写真で生成する'));
    await tester.pumpAndSettle();

    expect(calls.requestedRequestIds, ['request-1', 'request-1']);
    expect(calls.uploadedRequestIds, ['request-1', 'request-1']);
    expect(ticketPurchaseSteps(), ['shown', 'purchased']);
    // 反映の案内のタイマーを終わらせる
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('購入の後に残高が増えないまま時間が経ったら 反映を待っている案内を出す', (tester) async {
    await pumpUntilDailyLimit(
      tester: tester,
      generator: limitedGenerator(
        ticketPackages: const [testTicketPackage],
        purchaseTicketPackage: ({required package}) async =>
            TicketPurchaseResult.purchased,
      ),
    );

    await tester.tap(find.textContaining('¥200'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));

    expect(find.textContaining('反映を待っています'), findsOneWidget);
    expect(calls.requestedRequestIds, ['request-1']);
  });

  testWidgets('ストアの購入を閉じたら 購入画面のままで生成をやり直さない', (tester) async {
    await pumpUntilDailyLimit(
      tester: tester,
      generator: limitedGenerator(
        ticketPackages: const [testTicketPackage],
        purchaseTicketPackage: ({required package}) async =>
            TicketPurchaseResult.cancelled,
      ),
    );

    await tester.tap(find.textContaining('¥200'));
    await tester.pumpAndSettle();

    expect(find.text('生成チケット'), findsOneWidget);
    expect(calls.requestedRequestIds, ['request-1']);
    expect(ticketPurchaseSteps(), ['shown', 'cancelled']);
  });

  testWidgets('ストアの購入が失敗したら エラーをそのまま出す', (tester) async {
    await pumpUntilDailyLimit(
      tester: tester,
      generator: limitedGenerator(
        ticketPackages: const [testTicketPackage],
        purchaseTicketPackage: ({required package}) async =>
            throw StateError('ストアの失敗'),
      ),
    );

    await tester.tap(find.textContaining('¥200'));
    await tester.pumpAndSettle();

    expect(find.textContaining('ストアの失敗'), findsOneWidget);
    expect(ticketPurchaseSteps(), ['shown', 'failed']);
  });

  /// [generator] で設定画面の「購入の状態を同期する」を開く。
  Future<void> pumpSyncTile({
    required WidgetTester tester,
    required MonsterGenerator generator,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TicketPurchaseSyncTile(monsterGenerator: generator),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('売っている間は 同期の項目を出し 押すと同期する', (tester) async {
    await pumpSyncTile(
      tester: tester,
      generator: limitedGenerator(ticketPackages: const [testTicketPackage]),
    );

    await tester.tap(find.text('購入の状態を同期する'));
    await tester.pump();

    expect(calls.syncTicketPurchasesCallCount, 1);
    expect(ticketPurchaseSteps(), ['restored']);
  });

  testWidgets('売っていない間は 同期の項目を出さない', (tester) async {
    await pumpSyncTile(
      tester: tester,
      generator: limitedGenerator(ticketPackages: const []),
    );

    expect(find.text('購入の状態を同期する'), findsNothing);
  });
}
