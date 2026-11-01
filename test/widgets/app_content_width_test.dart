import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/widgets/app_content_width.dart';

/// [constrainToAppContentWidth] で包んだ画面の内容と下タブを出すアプリ。
Widget _appWithContentWidth() => MaterialApp(
  builder: (context, child) =>
      constrainToAppContentWidth(child: child ?? const SizedBox.shrink()),
  home: Scaffold(
    body: Builder(
      builder: (context) => SizedBox.expand(
        key: const Key('body'),
        child: Text('${MediaQuery.sizeOf(context).width}'),
      ),
    ),
    bottomNavigationBar: NavigationBar(
      key: const Key('bottomTabs'),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.grid_view), label: 'a'),
        NavigationDestination(icon: Icon(Icons.camera), label: 'b'),
      ],
    ),
  ),
);

void main() {
  /// テストの画面の大きさを [size] にし、テストの終わりに戻す。
  void setSurfaceSize({required WidgetTester tester, required Size size}) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('広い画面では本文と下タブが上限の幅で中央に寄る', (tester) async {
    setSurfaceSize(tester: tester, size: const Size(1280, 800));
    await tester.pumpWidget(_appWithContentWidth());

    for (final key in const [Key('body'), Key('bottomTabs')]) {
      final rect = tester.getRect(find.byKey(key));
      expect(rect.width, appContentMaxWidth);
      expect(rect.center.dx, 640);
    }
    expect(find.text('$appContentMaxWidth'), findsOneWidget);
  });

  testWidgets('スマホの幅では画面の幅いっぱいに描く', (tester) async {
    setSurfaceSize(tester: tester, size: const Size(390, 844));
    await tester.pumpWidget(_appWithContentWidth());

    expect(tester.getRect(find.byKey(const Key('body'))).width, 390);
    expect(tester.getRect(find.byKey(const Key('bottomTabs'))).width, 390);
    expect(find.text('390.0'), findsOneWidget);
  });

  testWidgets('広い画面では左右の safe area から左右の余白の分を差し引く', (tester) async {
    setSurfaceSize(tester: tester, size: const Size(1280, 800));
    tester.view.padding = const FakeViewPadding(left: 700, right: 40, top: 20);
    addTearDown(tester.view.resetPadding);
    late EdgeInsets contentPadding;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            constrainToAppContentWidth(child: child ?? const SizedBox.shrink()),
        home: Builder(
          builder: (context) {
            contentPadding = MediaQuery.paddingOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    // 左右の余白は (1280 - 600) / 2 = 340。
    expect(contentPadding, const EdgeInsets.only(left: 360, top: 20));
  });

  testWidgets('幅が上限を跨いで変わっても画面の状態を保つ', (tester) async {
    setSurfaceSize(tester: tester, size: const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            constrainToAppContentWidth(child: child ?? const SizedBox.shrink()),
        home: const Scaffold(body: TextField()),
      ),
    );
    await tester.enterText(find.byType(TextField), 'kept');

    setSurfaceSize(tester: tester, size: const Size(1280, 800));
    await tester.pump();

    expect(find.text('kept'), findsOneWidget);
  });
}
