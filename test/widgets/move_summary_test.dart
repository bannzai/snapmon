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

  /// ゆげのもや (熱・威力 35・PP 35・先に動くと強い)。特殊効果を持つ技として使う。
  final effectMove = sampleData.definitions.moveById(moveId: 'heat_1b');

  /// ブリキパンチ (金属・威力 40・PP 30)。特殊効果を持たない技として使う。
  final plainMove = sampleData.definitions.moveById(moveId: 'metal_1');

  /// [remainingPowerPoints] を渡した [MoveSummary] を [move] で描く。
  Future<void> pumpMoveSummary({
    required WidgetTester tester,
    required int? remainingPowerPoints,
    required String moveId,
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
    );
    expect(
      find.text('PP ${plainMove.powerPoints}', findRichText: true),
      findsOneWidget,
    );
    // 名前・札の中の属性名・威力・PP の 4 つだけで、説明の段は無い
    expect(find.byType(RichText), findsNWidgets(4));
  });
}
