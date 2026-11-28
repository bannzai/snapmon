import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snapmon/maintenance/maintenance_resolver.dart';
import 'package:snapmon/maintenance/maintenance_state.dart';

/// テストで状態を読む先として渡す URL
final stateURL = Uri.parse(
  'https://service-maintenance.example.workers.dev/snapmon',
);

/// message と button を持つメンテナンス中の応答 (状態を返す Worker が返す JSON)
const inMaintenanceWithButton = {
  'maintenance': true,
  'message': '復旧までお待ちください',
  'button': {'label': 'お知らせを見る', 'url': 'https://example.com/news'},
  'source': 'owner',
  'changedAt': '2026-11-25T07:00:00.000Z',
};

/// message も button も無いメンテナンス中の応答
const inMaintenanceWithoutButton = {
  'maintenance': true,
  'message': null,
  'button': null,
  'source': 'cost',
  'changedAt': '2026-11-25T07:00:00.000Z',
};

/// メンテナンス中でない応答
const notInMaintenance = {
  'maintenance': false,
  'message': null,
  'button': null,
  'source': 'owner',
  'changedAt': '2026-11-25T08:00:00.000Z',
};

/// 返す応答を後から差し替えられる HTTP のクライアントの代わり。読まれた URL を requestedURLs に残す。
/// テストが途中で body・statusCode・fail を書き換えて読むため、書き換えられる値を持つ class にした
/// (Dart には、書き換えられる値を持つ物を作る関数の書き方として、TypeScript の object literal に当たるものが無い)
class SwitchableClient {
  /// 最初に返す応答の body から作る
  SwitchableClient(this.body);

  /// 応答の body (JSON にして返す値)
  Object? body;

  /// 応答の HTTP の status
  int statusCode = 200;

  /// true の間、通信の失敗として例外を投げる
  bool fail = false;

  /// 読まれた URL (読まれた順)
  final requestedURLs = <Uri>[];

  /// MaintenanceResolver に渡す HTTP のクライアント
  http.Client get client => MockClient((request) async {
    requestedURLs.add(request.url);
    if (fail) throw http.ClientException('connection failed');
    return http.Response.bytes(utf8.encode(jsonEncode(body)), statusCode);
  });
}

/// 応答を返さない HTTP のクライアント。読まれた URL と、閉じられたかを残す。
/// 時間切れの時に、読み取りに使った client が閉じられるかを確かめるために使う
class UnansweredClient extends http.BaseClient {
  /// 読まれた URL (読まれた順)
  final requestedURLs = <Uri>[];

  /// close が呼ばれたら true
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requestedURLs.add(request.url);
    return Completer<http.StreamedResponse>().future;
  }

  @override
  void close() => closed = true;
}

/// 読み終わるまでの間に出す色を確かめるための、アプリの背景の色。既定の色と区別できればよく、原色の緑にした
const appBackgroundColor = Color(0xFF00FF00);

/// MaintenanceResolver を、アプリの一番上 (MaterialApp の builder) に置いたアプリを組む。
/// 押されたボタンの URL を openedURLs に、本来の画面が作られた回数を childBuildCount に残す。
/// 書き換えられる値を持つため class にした (理由は [SwitchableClient] と同じ)
class ResolverApp {
  /// 押されたボタンの URL (押された順)
  final openedURLs = <Uri>[];

  /// 本来の画面 (MaintenanceResolver の child の中身) が build された回数
  int childBuildCount = 0;

  /// [client] で状態を読むアプリを画面に出す。[settle] が false の時は、読み取りが返るのを待たずに戻る
  /// (読み終わるまでの画面と、返らない読み取りを試すテストのため)
  Future<void> pump(
    WidgetTester tester,
    http.Client client, {
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(scaffoldBackgroundColor: appBackgroundColor),
        builder: (context, child) => MaintenanceResolver(
          stateURL: stateURL,
          defaultMessage: 'ただいまメンテナンス中です',
          onOpenURL: openedURLs.add,
          client: client,
          child: child!,
        ),
        home: Builder(
          builder: (context) {
            childBuildCount += 1;
            return const Scaffold(body: Text('本来の画面'));
          },
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('メンテナンス中は、状態の文とボタンを持つメンテナンス中の画面だけを出し、本来の画面を作らない', (tester) async {
    final switchableClient = SwitchableClient(inMaintenanceWithButton);
    final resolverApp = ResolverApp();
    await resolverApp.pump(tester, switchableClient.client);

    expect(switchableClient.requestedURLs, [stateURL]);
    expect(find.text('復旧までお待ちください'), findsOneWidget);
    expect(find.text('本来の画面', skipOffstage: false), findsNothing);
    expect(resolverApp.childBuildCount, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'お知らせを見る'));
    expect(resolverApp.openedURLs, [Uri.parse('https://example.com/news')]);
  });

  testWidgets('button が null の時はボタンを出さず、message が null の時はサービスの既定の文を出す', (
    tester,
  ) async {
    await ResolverApp().pump(
      tester,
      SwitchableClient(inMaintenanceWithoutButton).client,
    );

    expect(find.text('ただいまメンテナンス中です'), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('本来の画面', skipOffstage: false), findsNothing);
  });

  testWidgets('メンテナンス中でない時は本来の画面を出す', (tester) async {
    final switchableClient = SwitchableClient(notInMaintenance);
    await ResolverApp().pump(tester, switchableClient.client);

    expect(switchableClient.requestedURLs, [stateURL]);
    expect(find.text('本来の画面'), findsOneWidget);
    expect(find.byType(MaintenanceScreen), findsNothing);
  });

  testWidgets('状態を読めない時 (通信の失敗) は本来の画面を出す', (tester) async {
    final switchableClient = SwitchableClient(inMaintenanceWithButton)
      ..fail = true;
    await ResolverApp().pump(tester, switchableClient.client);

    expect(switchableClient.requestedURLs, hasLength(1));
    expect(find.text('本来の画面'), findsOneWidget);
    expect(find.byType(MaintenanceScreen), findsNothing);
  });

  testWidgets('状態を読めない時 (200 以外の応答) は本来の画面を出す', (tester) async {
    await ResolverApp().pump(
      tester,
      (SwitchableClient(inMaintenanceWithButton)..statusCode = 500).client,
    );

    expect(find.text('本来の画面'), findsOneWidget);
    expect(find.byType(MaintenanceScreen), findsNothing);
  });

  testWidgets('状態を読めない時 (形の違う応答) は本来の画面を出す', (tester) async {
    await ResolverApp().pump(
      tester,
      SwitchableClient({'maintenance': 'yes'}).client,
    );

    expect(find.text('本来の画面'), findsOneWidget);
    expect(find.byType(MaintenanceScreen), findsNothing);
  });

  testWidgets('状態を読み終わるまでは、本来の画面もメンテナンス中の画面も作らず、アプリの背景の色だけを出す', (tester) async {
    final pendingResponse = Completer<http.Response>();
    final resolverApp = ResolverApp();
    await resolverApp.pump(
      tester,
      MockClient((_) => pendingResponse.future),
      settle: false,
    );

    expect(resolverApp.childBuildCount, 0);
    expect(find.byType(MaintenanceScreen), findsNothing);
    expect(
      tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(MaintenanceResolver),
              matching: find.byType(ColoredBox),
            ),
          )
          .color,
      appBackgroundColor,
    );

    pendingResponse.complete(
      http.Response.bytes(
        utf8.encode(jsonEncode(inMaintenanceWithButton)),
        200,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('復旧までお待ちください'), findsOneWidget);
    expect(resolverApp.childBuildCount, 0);
  });

  testWidgets('応答が 2 秒返らない時は待つのをやめ、本来の画面を出す', (tester) async {
    final resolverApp = ResolverApp();
    await resolverApp.pump(
      tester,
      MockClient((_) => Completer<http.Response>().future),
      settle: false,
    );

    await tester.pump(const Duration(milliseconds: 1999));
    expect(resolverApp.childBuildCount, 0);
    expect(find.text('本来の画面'), findsNothing);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pumpAndSettle();
    expect(find.text('本来の画面'), findsOneWidget);
    expect(find.byType(MaintenanceScreen), findsNothing);
  });

  testWidgets('メンテナンス中でないと読んだ後は、背面に回って前面に戻っても時間が過ぎても読み直さず、本来の画面のままにする', (
    tester,
  ) async {
    final switchableClient = SwitchableClient(notInMaintenance);
    await ResolverApp().pump(tester, switchableClient.client);
    expect(find.text('本来の画面'), findsOneWidget);

    switchableClient.body = inMaintenanceWithButton;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(hours: 1));
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump(const Duration(hours: 1));
    await tester.pumpAndSettle();

    expect(switchableClient.requestedURLs, hasLength(1));
    expect(find.text('本来の画面'), findsOneWidget);
    expect(find.byType(MaintenanceScreen), findsNothing);
  });

  testWidgets('メンテナンス中と読んだ後は、背面に回って前面に戻っても時間が過ぎても読み直さず、メンテナンス中の画面のままにする', (
    tester,
  ) async {
    final switchableClient = SwitchableClient(inMaintenanceWithButton);
    final resolverApp = ResolverApp();
    await resolverApp.pump(tester, switchableClient.client);
    expect(find.text('復旧までお待ちください'), findsOneWidget);

    switchableClient.body = notInMaintenance;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(hours: 1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(hours: 1));
    await tester.pumpAndSettle();

    expect(switchableClient.requestedURLs, hasLength(1));
    expect(find.text('復旧までお待ちください'), findsOneWidget);
    expect(resolverApp.childBuildCount, 0);
  });

  testWidgets('アプリが作り直されても (親の再 build)、読み直さない', (tester) async {
    final switchableClient = SwitchableClient(notInMaintenance);
    final resolverApp = ResolverApp();
    final client = switchableClient.client;
    await resolverApp.pump(tester, client);
    await resolverApp.pump(tester, client);

    expect(switchableClient.requestedURLs, hasLength(1));
    expect(find.text('本来の画面'), findsOneWidget);
  });

  testWidgets('読み取りを待つ間に MaintenanceResolver が画面から外され、その後に応答が返っても例外にならない', (
    tester,
  ) async {
    final pendingResponse = Completer<http.Response>();
    await ResolverApp().pump(
      tester,
      MockClient((_) => pendingResponse.future),
      settle: false,
    );
    await tester.pumpWidget(const SizedBox());

    pendingResponse.complete(
      http.Response.bytes(
        utf8.encode(jsonEncode(inMaintenanceWithButton)),
        200,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('MaintenanceScreen', () {
    testWidgets('小さい画面で文が長い時も、スクロールで文の末尾とボタンを画面の中に出せる', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MaintenanceScreen(
            message: List.generate(40, (index) => '${index + 1} 行目').join('\n'),
            button: MaintenanceButton(
              label: 'お知らせを見る',
              url: Uri.parse('https://example.com/news'),
            ),
            onOpenURL: (_) {},
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(FilledButton)).bottom,
        lessThanOrEqualTo(480),
      );
    });

    testWidgets('文が短い時は、文を画面の縦の中央に出す', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: MaintenanceScreen(
            message: 'ただいまメンテナンス中です',
            button: null,
            onOpenURL: (_) {},
          ),
        ),
      );

      expect(tester.getCenter(find.byType(Text)).dy, closeTo(240, 1));
    });
  });

  group('fetchMaintenanceState', () {
    test('client を渡さずに時間切れになった時は、自分で作った client を閉じて、メンテナンス中でない状態を返す', () async {
      final unansweredClient = UnansweredClient();
      final state = await http.runWithClient(
        () => fetchMaintenanceState(
          stateURL,
          timeout: const Duration(milliseconds: 10),
        ),
        () => unansweredClient,
      );

      expect(unansweredClient.requestedURLs, [stateURL]);
      expect(unansweredClient.closed, true);
      expect(state.maintenance, false);
    });

    test('client を渡された時は、時間切れになってもその client を閉じない (渡した側が使い続けるため)', () async {
      final unansweredClient = UnansweredClient();
      final state = await fetchMaintenanceState(
        stateURL,
        client: unansweredClient,
        timeout: const Duration(milliseconds: 10),
      );

      expect(unansweredClient.requestedURLs, [stateURL]);
      expect(unansweredClient.closed, false);
      expect(state.maintenance, false);
    });
  });

  group('MaintenanceState.tryParse', () {
    test('5 つの項目がそろった値を読む', () {
      final state = MaintenanceState.tryParse(inMaintenanceWithButton)!;
      expect(state.maintenance, true);
      expect(state.message, '復旧までお待ちください');
      expect(state.button!.label, 'お知らせを見る');
      expect(state.button!.url, Uri.parse('https://example.com/news'));
      expect(state.source, 'owner');
      expect(state.changedAt, '2026-11-25T07:00:00.000Z');
    });

    test('maintenance・source・changedAt の形が違う値は null を返す', () {
      expect(MaintenanceState.tryParse(null), isNull);
      expect(MaintenanceState.tryParse('maintenance'), isNull);
      expect(
        MaintenanceState.tryParse({
          ...inMaintenanceWithButton,
          'maintenance': 'true',
        }),
        isNull,
      );
      expect(
        MaintenanceState.tryParse({
          ...inMaintenanceWithButton,
          'source': 'admin',
        }),
        isNull,
      );
      expect(
        MaintenanceState.tryParse({
          ...inMaintenanceWithButton,
          'changedAt': 1764054000,
        }),
        isNull,
      );
    });

    test('source が usage の値をメンテナンス中として読む', () {
      final state = MaintenanceState.tryParse({
        ...inMaintenanceWithButton,
        'source': 'usage',
      })!;
      expect(state.maintenance, true);
      expect(state.source, 'usage');
    });

    test('空文字と文字列でない message は、メンテナンス中のまま message だけ null にする', () {
      for (final message in ['', 503]) {
        final state = MaintenanceState.tryParse({
          ...inMaintenanceWithButton,
          'message': message,
        })!;
        expect(state.maintenance, true, reason: '$message');
        expect(state.message, isNull, reason: '$message');
      }
    });

    test(
      '開けない url・空の label・文字列でない url の button は、メンテナンス中のまま button だけ null にする',
      () {
        for (final button in [
          {'label': '開く', 'url': 'javascript:alert(1)'},
          {'label': '開く', 'url': 'example.com/news'},
          // authority はあり、スキームだけが http・https でない
          {'label': '開く', 'url': 'ftp://example.com/'},
          // スキームは https で、authority だけが無い
          {'label': '開く', 'url': 'https:news'},
          {'label': '開く'},
          {'label': '開く', 'url': 1},
          {'label': '', 'url': 'https://example.com/news'},
          {'url': 'https://example.com/news'},
          'https://example.com/news',
        ]) {
          final state = MaintenanceState.tryParse({
            ...inMaintenanceWithButton,
            'button': button,
          })!;
          expect(state.maintenance, true, reason: '$button');
          expect(state.button, isNull, reason: '$button');
        }
      },
    );

    test('http の url の button は読む', () {
      expect(
        MaintenanceState.tryParse({
          ...inMaintenanceWithButton,
          'button': {'label': '開く', 'url': 'http://example.com/'},
        })!.button!.url,
        Uri.parse('http://example.com/'),
      );
    });
  });
}
