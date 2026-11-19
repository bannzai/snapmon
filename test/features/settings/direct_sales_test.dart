import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/capture/ticket_purchase_sheet.dart';
import 'package:snapmon/features/settings/direct_sales.dart';
import 'package:snapmon/features/settings/settings_screen.dart';
import 'package:snapmon/l10n/l10n.dart';

import '../../account_store_fixture.dart';
import '../../monster_generator_fixture.dart';

void main() {
  /// 画面を開く言語 (原文の日本語) の文言。画面の文言はここから引いて探す。
  final l10n = lookupAppLocalizations(const Locale('ja'));

  /// 購入の関数に渡された package (呼ばれた順)。
  late List<Package> purchasedPackages;

  /// リンクを開く関数に渡された URL (呼ばれた順)。
  late List<Uri> openedUris;

  /// リンクを開く関数が開けたと返すか。
  late bool opensURL;

  setUp(() {
    purchasedPackages = [];
    openedUris = [];
    opensURL = true;
  });

  /// 生成チケットの購入画面を開く。[accountLink] があれば提供者が直接売るビルド (Web 版) として、アプリと同じく Navigator の外の
  /// [DirectSalesScope] の下で開く。null ならストアで売るアプリ (iOS・Android) として開く。
  Future<void> pumpTicketPurchaseSheet({
    required WidgetTester tester,
    required FakeAccountLink? accountLink,
  }) async {
    final accountStore = accountLink?.accountStore();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => accountStore == null
            ? child!
            : DirectSalesScope(
                accountStore: accountStore,
                openURL: ({required uri}) async {
                  openedUris.add(uri);
                  return opensURL;
                },
                child: child!,
              ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showTicketPurchaseSheet(
                context: context,
                packages: const [testTicketPackage],
                purchaseTicketPackage: ({required package}) async {
                  purchasedPackages.add(package);
                  return TicketPurchaseResult.cancelled;
                },
                watchGenerationTickets: () => const Stream.empty(),
                logEvent: ({required event, required parameters}) async {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// 購入画面の買うボタン (ストアの価格を出している)。
  final buyButton = find.textContaining(
    testTicketPackage.storeProduct.priceString,
  );

  /// 購入の前の連携の案内。
  final linkDialog = find.byKey(const Key('link-before-purchase-dialog'));

  /// 案内の「データを引き継ぐ」を押して出る、連携に使うサインインの一覧の [providerName] の行。
  Finder linkProviderTile({required String providerName}) =>
      find.byKey(Key('settings-link-provider-$providerName'));

  /// 案内の「データを引き継ぐ」を押し、下からの一覧で [providerName] を選ぶ。
  Future<void> linkFromDialog({
    required WidgetTester tester,
    required String providerName,
  }) async {
    await tester.tap(find.byKey(const Key('link-before-purchase-link')));
    await tester.pumpAndSettle();
    await tester.tap(linkProviderTile(providerName: providerName));
    await tester.pumpAndSettle();
  }

  group('生成チケットの購入の前の連携の確認', () {
    testWidgets('提供者が直接売るビルドで匿名のままなら 購入を始めずに連携の案内を出し やめると何もしない', (
      tester,
    ) async {
      final accountLink = FakeAccountLink(isLinked: false);
      await pumpTicketPurchaseSheet(tester: tester, accountLink: accountLink);

      await tester.tap(buyButton);
      await tester.pumpAndSettle();
      expect(linkDialog, findsOneWidget);
      expect(
        find.text(l10n.purchaseLinkRequiredMessage('Apple / Google')),
        findsOneWidget,
      );
      expect(purchasedPackages, isEmpty);

      await tester.tap(find.text(l10n.commonCancel));
      await tester.pumpAndSettle();
      expect(linkDialog, findsNothing);
      expect(accountLink.linkedWithProviderNames, isEmpty);
      expect(purchasedPackages, isEmpty);
      // 購入画面は開いたままで もう一度買える
      expect(buyButton, findsOneWidget);
    });

    testWidgets('案内から連携できたら 案内を閉じてそのまま購入に進む', (tester) async {
      final accountLink = FakeAccountLink(isLinked: false);
      await pumpTicketPurchaseSheet(tester: tester, accountLink: accountLink);

      await tester.tap(buyButton);
      await tester.pumpAndSettle();
      await linkFromDialog(tester: tester, providerName: 'Google');

      expect(accountLink.linkedWithProviderNames, ['Google']);
      expect(linkDialog, findsNothing);
      expect(purchasedPackages, [testTicketPackage]);
    });

    testWidgets('案内の「データを引き継ぐ」は 設定画面と同じ一覧で連携先を選ばせ 選んだ連携先で連携する', (tester) async {
      final accountLink = FakeAccountLink(isLinked: false);
      await pumpTicketPurchaseSheet(tester: tester, accountLink: accountLink);

      await tester.tap(buyButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('link-before-purchase-link')));
      await tester.pumpAndSettle();
      expect(linkProviderTile(providerName: 'Apple'), findsOneWidget);
      expect(linkProviderTile(providerName: 'Google'), findsOneWidget);
      // 選ぶまでは連携も購入も始めない
      expect(accountLink.linkedWithProviderNames, isEmpty);
      expect(purchasedPackages, isEmpty);

      await tester.tap(linkProviderTile(providerName: 'Apple'));
      await tester.pumpAndSettle();
      expect(accountLink.linkedWithProviderNames, ['Apple']);
      expect(linkDialog, findsNothing);
      expect(purchasedPackages, [testTicketPackage]);
    });

    testWidgets('一覧で連携先を選ばずに閉じたら 連携も購入も始めず 案内に戻る', (tester) async {
      final accountLink = FakeAccountLink(isLinked: false);
      await pumpTicketPurchaseSheet(tester: tester, accountLink: accountLink);

      await tester.tap(buyButton);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('link-before-purchase-link')));
      await tester.pumpAndSettle();
      // 一覧の外 (画面の上端) を押して閉じる
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(linkProviderTile(providerName: 'Google'), findsNothing);
      expect(linkDialog, findsOneWidget);
      expect(accountLink.linkedWithProviderNames, isEmpty);
      expect(purchasedPackages, isEmpty);
    });

    testWidgets('提供者が直接売るビルドで連携済みなら 案内を出さずに購入に進む', (tester) async {
      final accountLink = FakeAccountLink(isLinked: true);
      await pumpTicketPurchaseSheet(tester: tester, accountLink: accountLink);

      await tester.tap(buyButton);
      await tester.pumpAndSettle();

      expect(linkDialog, findsNothing);
      expect(accountLink.linkedWithProviderNames, isEmpty);
      expect(purchasedPackages, [testTicketPackage]);
    });

    testWidgets('ストアで売るアプリでは 匿名のままでも案内を出さずに購入に進む', (tester) async {
      await pumpTicketPurchaseSheet(tester: tester, accountLink: null);

      await tester.tap(buyButton);
      await tester.pumpAndSettle();

      expect(linkDialog, findsNothing);
      expect(purchasedPackages, [testTicketPackage]);
    });

    testWidgets('DEBUG ビルドでログインを飛ばした間は 連携するアカウントが無いため 案内を出さずに購入に進む', (
      tester,
    ) async {
      final accountLink = FakeAccountLink.sessionSkippedForDebug();
      await pumpTicketPurchaseSheet(tester: tester, accountLink: accountLink);

      await tester.tap(buyButton);
      await tester.pumpAndSettle();

      expect(linkDialog, findsNothing);
      expect(accountLink.linkedWithProviderNames, isEmpty);
      expect(purchasedPackages, [testTicketPackage]);
    });

    testWidgets('選んだアカウントが別のデータと連携済みなら 切り替えずにそのことを出し 購入を始めない', (tester) async {
      var signInToLinkedAccountCallCount = 0;
      await pumpTicketPurchaseSheet(
        tester: tester,
        accountLink: FakeAccountLink(isLinked: false)
          ..linkAccount = () async => () async {
            signInToLinkedAccountCallCount++;
            return 'uid-linked';
          },
      );

      await tester.tap(buyButton);
      await tester.pumpAndSettle();
      await linkFromDialog(tester: tester, providerName: 'Google');

      expect(linkDialog, findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('link-before-purchase-failure')))
            .data,
        l10n.purchaseLinkAlreadyUsed('Google'),
      );
      expect(signInToLinkedAccountCallCount, 0);
      expect(purchasedPackages, isEmpty);
    });

    testWidgets('連携に失敗したら 失敗の内容をそのまま出し 購入を始めない', (tester) async {
      await pumpTicketPurchaseSheet(
        tester: tester,
        accountLink: FakeAccountLink(isLinked: false)
          ..linkAccount = () async => throw StateError('連携の失敗'),
      );

      await tester.tap(buyButton);
      await tester.pumpAndSettle();
      await linkFromDialog(tester: tester, providerName: 'Google');

      expect(linkDialog, findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const Key('link-before-purchase-failure')))
            .data,
        StateError('連携の失敗').toString(),
      );
      expect(purchasedPackages, isEmpty);
    });
  });

  group('特定商取引法に基づく表記へのリンク', () {
    /// 購入画面のリンク。
    final link = find.byKey(
      const Key('specified-commercial-transactions-link'),
    );

    /// リンクを開けなかった時の表示。
    final failure = find.byKey(
      const Key('specified-commercial-transactions-failure'),
    );

    testWidgets('提供者が直接売るビルドの購入画面に出し 押すと表記のページを開く', (tester) async {
      await pumpTicketPurchaseSheet(
        tester: tester,
        accountLink: FakeAccountLink(isLinked: true),
      );
      expect(
        find.descendant(
          of: link,
          matching: find.text(l10n.purchaseSpecifiedCommercialTransactions),
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(openedUris, [specifiedCommercialTransactionsUri]);
      expect(failure, findsNothing);
    });

    testWidgets('ページを開けなかったら リンクの下にそのことを出す', (tester) async {
      opensURL = false;
      await pumpTicketPurchaseSheet(
        tester: tester,
        accountLink: FakeAccountLink(isLinked: true),
      );

      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(failure).data,
        l10n.commonCouldNotOpenURL(
          specifiedCommercialTransactionsUri.toString(),
        ),
      );
    });

    testWidgets('ストアで売るアプリの購入画面には出さない', (tester) async {
      await pumpTicketPurchaseSheet(tester: tester, accountLink: null);

      expect(buyButton, findsOneWidget);
      expect(link, findsNothing);
    });
  });
}
