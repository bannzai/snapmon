import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/status_condition.dart';
import 'package:snapmon/features/help/help_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/monster_ui/move_card.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

void main() {
  testWidgets('遊び方の画面は手持ち・レベル・属性の相性・状態異常の節を出し、状態異常は全種類を名前と説明で並べる', (tester) async {
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
        home: const HelpScreen(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('遊び方'), findsOneWidget);
    expect(find.text('手持ちは 3 体まで'), findsOneWidget);
    expect(find.text('レベル'), findsOneWidget);
    expect(find.text('属性の相性 (弱点)'), findsOneWidget);
    // バトルの技のボタンと同じ相性のアイコンを見本に出す
    expect(find.byType(TypeEffectivenessIcon), findsNWidgets(2));
    expect(find.text('効果は抜群 ダメージ 2 倍'), findsOneWidget);

    final context = tester.element(find.byType(HelpScreen));
    for (final kind in StatusConditionKind.values) {
      final row = find.byKey(Key('help-status-${kind.name}'));
      await tester.scrollUntilVisible(row, 200);
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            statusConditionLabel(l10n: context.l10n, kind: kind),
          ),
        ),
        findsOneWidget,
        reason: kind.name,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(
            statusConditionHelpDescription(l10n: context.l10n, kind: kind),
          ),
        ),
        findsOneWidget,
        reason: kind.name,
      );
    }
  });
}
