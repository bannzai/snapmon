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

  testWidgets('2 列の技のボタンの幅で文字を 3 倍にしても 1 段目がはみ出さず、札が折り返す', (tester) async {
    // 390 の画面の 2 列の技のボタンの幅 (173) に、長い倍率 (×0.25) の札を 3 倍の文字で入れる。
    // 札が折り返さないと、Row が「RenderFlex overflowed」の例外を出す (Codex のレビューと観点レビューの指摘)
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(3)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 173,
                child: MoveSummary(
                  move: plainMove,
                  remainingPowerPoints: 12,
                  typeMultiplier: 0.25,
                  definitions: sampleData.definitions,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final elementTypeTag = find.byType(ElementTypeTag);
    final multiplierText = find.byKey(const Key('move-type-multiplier'));
    expect(multiplierText, findsOneWidget);
    // 相性の札は属性の札の右に並ばず、その下に折り返す
    expect(
      tester.getTopLeft(multiplierText).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(elementTypeTag).dy),
    );
    // どの札も技のボタンの幅からはみ出さない
    expect(
      tester.getBottomRight(multiplierText).dx,
      lessThanOrEqualTo(tester.getTopRight(find.byType(MoveSummary)).dx),
    );
  });

  testWidgets('名前と属性の札・威力・特殊効果の説明と PP を別の段と書体で描く', (tester) async {
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
    expect(find.text('PP 12/${effectMove.powerPoints}'), findsOneWidget);
    expect(
      tester.widget<Text>(find.text('先に動くと強い')).style?.fontFamily,
      bodyFontFamily,
    );
    // 1 段目は名前の右に属性の札、その下に威力、いちばん下に説明と PP が並ぶ
    expect(
      tester.getTopLeft(find.byType(ElementTypeTag)).dx,
      greaterThanOrEqualTo(tester.getTopRight(find.text('ゆげのもや')).dx),
    );
    expect(
      tester
          .getTopLeft(find.text('威力 ${effectMove.power}', findRichText: true))
          .dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(ElementTypeTag)).dy,
      ),
    );
    expect(
      tester.getTopLeft(find.text('先に動くと強い')).dy,
      greaterThanOrEqualTo(
        tester
            .getBottomLeft(
              find.text('威力 ${effectMove.power}', findRichText: true),
            )
            .dy,
      ),
    );
    expect(
      tester.getTopLeft(find.text('PP 12/${effectMove.powerPoints}')).dx,
      greaterThanOrEqualTo(tester.getTopRight(find.text('先に動くと強い')).dx),
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
    expect(find.text('PP ${plainMove.powerPoints}'), findsOneWidget);
    // 名前・札の中の属性名・威力・PP の 4 つだけで、説明の段と相性の札は無い
    expect(find.byType(RichText), findsNWidgets(4));
  });

  // 等倍 (1) は「似ているが出さない」側。0.25・4 は 2 属性の相手への積で、桁を落とさずに出す。
  // 言葉は画面に出さず、読み上げの名前にだけ持つ
  for (final (typeMultiplier, expectedText, expectedIcon, expectedLabel) in [
    (2.0, '×2', Icons.keyboard_double_arrow_up, '効果は抜群 ×2'),
    (4.0, '×4', Icons.keyboard_double_arrow_up, '効果は抜群 ×4'),
    (0.5, '×0.5', Icons.keyboard_double_arrow_down, '効果はいまひとつ ×0.5'),
    (0.25, '×0.25', Icons.keyboard_double_arrow_down, '効果はいまひとつ ×0.25'),
    (1.0, null, null, null),
    (null, null, null, null),
  ]) {
    testWidgets('相性の倍率 $typeMultiplier は ${expectedText ?? '出さない'}', (
      tester,
    ) async {
      // 読み上げの名前を find.bySemanticsLabel で確かめるため。テストの終わりの検査より前に dispose する必要があり、addTearDown では間に合わない
      final semanticsHandle = tester.ensureSemantics();
      await pumpMoveSummary(
        tester: tester,
        remainingPowerPoints: 12,
        moveId: plainMove.id,
        typeMultiplier: typeMultiplier,
      );
      final multiplierText = find.byKey(const Key('move-type-multiplier'));
      if (expectedText == null) {
        expect(multiplierText, findsNothing);
        expect(find.byIcon(Icons.keyboard_double_arrow_up), findsNothing);
        expect(find.byIcon(Icons.keyboard_double_arrow_down), findsNothing);
      } else {
        expect(tester.widget<Text>(multiplierText).data, expectedText);
        expect(find.byIcon(expectedIcon!), findsOneWidget);
        expect(find.bySemanticsLabel(expectedLabel!), findsOneWidget);
        expect(find.text(expectedLabel), findsNothing);
        // 属性の札の右に並べ、「鋼 ⇈×2」のように属性と相性を続けて読ませる
        expect(
          tester.getTopLeft(multiplierText).dx,
          greaterThan(tester.getTopRight(find.byType(ElementTypeTag)).dx),
        );
      }
      semanticsHandle.dispose();
    });
  }
}
