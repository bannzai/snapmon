import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_text_styles.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/widgets/monster_parts.dart';
import 'package:snapmon/widgets/move_summary.dart';

import '../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// ゆげのもや (炎・威力 35・PP 35・先に動くと強い)。特殊効果を持つ技として使う。
  final effectMove = sampleData.definitions.moveById(moveId: 'fire_1b');

  /// ブリキパンチ (鋼・威力 40・PP 30)。特殊効果を持たない技として使う。
  final plainMove = sampleData.definitions.moveById(moveId: 'steel_1');

  /// [remainingPowerPoints]・[typeMultiplier] を渡した [MoveSummary] を [moveId] の技で描く。
  Future<void> pumpMoveSummary({
    required WidgetTester tester,
    required int? remainingPowerPoints,
    required String moveId,
    required double? typeMultiplier,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: snapmonThemeData(),
      locale: const Locale('ja'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MoveSummary(
          move: sampleData.definitions.moveById(moveId: moveId),
          remainingPowerPoints: remainingPowerPoints,
          typeMultiplier: typeMultiplier,
          definitions: sampleData.definitions,
        ),
      ),
    ),
  );

  testWidgets('名前・属性の札・威力と PP・特殊効果の説明を別の段と書体で描く', (tester) async {
    await pumpMoveSummary(
      tester: tester,
      remainingPowerPoints: 12,
      moveId: effectMove.id,
      typeMultiplier: null,
    );
    // 名前は見出しの書体で、属性の札・説明 (本文の書体) と区別する
    expect(
      tester.widget<Text>(find.text('ゆげのもや')).style?.fontFamily,
      headingFontFamily,
    );
    expect(
      tester.widget<ElementTypeTag>(find.byType(ElementTypeTag)).elementTypeId,
      effectMove.elementTypeId,
    );
    expect(
      find.text('威力 ${effectMove.power}', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.text('PP 12/${effectMove.powerPoints}', findRichText: true),
      findsOneWidget,
    );
    expect(
      tester.widget<Text>(find.text('先に動くと強い')).style?.fontFamily,
      bodyFontFamily,
    );
    // 名前・札と数値・説明の順に上から並ぶ
    expect(
      tester.getTopLeft(find.byType(ElementTypeTag)).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('ゆげのもや')).dy),
    );
    expect(
      tester.getTopLeft(find.text('先に動くと強い')).dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(ElementTypeTag)).dy,
      ),
    );
  });

  testWidgets('バトルの外 (残りの PP が null) では最大の PP だけを出し、特殊効果が無ければ説明を出さない', (
    tester,
  ) async {
    await pumpMoveSummary(
      tester: tester,
      remainingPowerPoints: null,
      moveId: plainMove.id,
      typeMultiplier: null,
    );
    expect(
      find.text('PP ${plainMove.powerPoints}', findRichText: true),
      findsOneWidget,
    );
    // 名前・札の中の属性名・威力・PP の 4 つだけで、説明の段と相性の札は無い
    expect(find.byType(RichText), findsNWidgets(4));
  });

  // 等倍 (1) は「似ているが出さない」側。0.25・4 は 2 属性の相手への積で、桁を落とさずに出す
  for (final (typeMultiplier, expectedText) in [
    (2.0, '▲×2'),
    (4.0, '▲×4'),
    (0.5, '▼×0.5'),
    (0.25, '▼×0.25'),
    (1.0, null),
    (null, null),
  ]) {
    testWidgets('相性の倍率 $typeMultiplier は ${expectedText ?? '出さない'}', (
      tester,
    ) async {
      await pumpMoveSummary(
        tester: tester,
        remainingPowerPoints: 12,
        moveId: plainMove.id,
        typeMultiplier: typeMultiplier,
      );
      final multiplierTag = find.byKey(const Key('move-type-multiplier'));
      if (expectedText == null) {
        expect(multiplierTag, findsNothing);
        return;
      }
      expect(tester.widget<Text>(multiplierTag).data, expectedText);
      // 属性の札の右に並べ、段を足さない (足すと技のボタンが高くなり、バトルの場が狭まる)
      expect(
        tester.getTopLeft(multiplierTag).dx,
        greaterThan(tester.getTopRight(find.byType(ElementTypeTag)).dx),
      );
      // 札の地を付けず、属性の札より小さく見せる (地を持つのは属性の札の 1 つだけ。https://github.com/bannzai/snapmon/issues/259 )
      expect(
        find.descendant(
          of: find.byType(MoveSummary),
          matching: find.byType(DecoratedBox),
        ),
        findsOneWidget,
      );
    });
  }
}
