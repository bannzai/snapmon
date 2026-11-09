import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/common_ui/scene_route.dart';

void main() {
  testWidgets('sceneRoute で開いた画面は画面単位の Semantics (scopesRoute) で包まれる', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              sceneRoute<void>(
                builder: (context) => const Scaffold(body: Text('開いた画面')),
              ),
            ),
            child: const Text('開く'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('開く'));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.text('開いた画面'),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.scopesRoute == true &&
              widget.explicitChildNodes,
        ),
      ),
      findsOneWidget,
    );
  });
}
