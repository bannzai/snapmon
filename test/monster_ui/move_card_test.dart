import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_element_icons.dart';
import 'package:snapmon/theme/snapmon_text_styles.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/monster_ui/monster_parts.dart';
import 'package:snapmon/monster_ui/move_card.dart';

import '../monster_generator_fixture.dart';
import '../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// ゆげのもや (炎・威力 35・PP 35・先に動くと強い)。特殊効果を持つ技として使う。
  final effectMove = sampleData.definitions.moveById(moveId: 'fire_1b');

  /// ブリキパンチ (鋼・威力 40・PP 30)。特殊効果を持たない技として使う。
  final plainMove = sampleData.definitions.moveById(moveId: 'steel_1');

  /// [remainingPowerPoints]・[typeMultiplier] を渡した [MoveCard] を [moveId] の技で描く。
  Future<void> pumpMoveCard({
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
        body: MoveCard(
          move: sampleData.definitions.moveById(moveId: moveId),
          remainingPowerPoints: remainingPowerPoints,
          typeMultiplier: typeMultiplier,
          definitions: sampleData.definitions,
        ),
      ),
    ),
  );

  testWidgets('2 列の技のボタンの幅で文字を 3 倍にしても 1 段目がはみ出さず、名前が折り返してアイコンは 1 行目の右端に残る', (
    tester,
  ) async {
    // 390 の画面の 2 列の技のボタンの幅 (173) に、2 つのアイコンを 3 倍の文字で入れる。
    // 名前を Expanded にしない Row だと「RenderFlex overflowed」の例外が出る (Codex のレビューと観点レビューの指摘)
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
                child: MoveCard(
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
    final name = find.text('ブリキパンチ');
    final elementTypeIcon = find.byType(ElementTypeIcon);
    final effectivenessIcon = find.byKey(const Key('move-type-effectiveness'));
    expect(effectivenessIcon, findsOneWidget);
    // 名前は `...` で切らずに折り返す (1 行の高さ 15 × 1.2 × 3 倍 = 54 より高い)
    final nameText = tester.widget<Text>(name);
    expect(nameText.overflow, isNot(TextOverflow.ellipsis));
    expect(nameText.maxLines, isNull);
    expect(tester.getSize(name).height, greaterThan(54));
    // アイコンは名前の下の行に下りず、1 行目の上端に揃って名前の右にある
    expect(tester.getTopLeft(elementTypeIcon).dy, tester.getTopLeft(name).dy);
    expect(
      tester.getTopLeft(elementTypeIcon).dx,
      greaterThanOrEqualTo(tester.getTopRight(name).dx),
    );
    // どのアイコンも技のボタンの幅からはみ出さない
    expect(
      tester.getBottomRight(effectivenessIcon).dx,
      lessThanOrEqualTo(tester.getTopRight(find.byType(MoveCard)).dx),
    );
  });

  testWidgets('属性と相性のアイコンは名前の 1 行の高さ (18) の丸で、名前の右端に並ぶ', (tester) async {
    // bannzai の「属性ごとのアイコンを決めよう。そして上向か下向きかのアイコンも含めてタイトルの右端に配置。どちらも小さく」
    // (https://github.com/bannzai/snapmon/issues/281 )
    await pumpMoveCard(
      tester: tester,
      remainingPowerPoints: 12,
      moveId: plainMove.id,
      typeMultiplier: 2,
    );
    final elementTypeIcon = find.byType(ElementTypeIcon);
    final effectivenessIcon = find.byKey(const Key('move-type-effectiveness'));
    expect(tester.getSize(elementTypeIcon), const Size(18, 18));
    expect(tester.getSize(effectivenessIcon), const Size(18, 18));
    // 鋼のアイコンは盾
    expect(
      find.descendant(of: elementTypeIcon, matching: find.byIcon(Icons.shield)),
      findsOneWidget,
    );
    // 属性名の文字は画面に出さず、読み上げの名前にだけ持つ
    expect(find.text('鋼'), findsNothing);
    // 相性のアイコンがいちばん右で、MoveCard の右端に付く
    expect(
      tester.getTopRight(effectivenessIcon).dx,
      moreOrLessEquals(tester.getTopRight(find.byType(MoveCard)).dx),
    );
    expect(
      tester.getTopLeft(effectivenessIcon).dx,
      greaterThan(tester.getTopRight(elementTypeIcon).dx),
    );
  });

  testWidgets('master に無い属性 (その場で作った定義) は代わりの星のアイコンで描く', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        home: Scaffold(
          body: ElementTypeIcon(
            elementTypeId: 'dynamic-wax',
            definitions: definitionsWithWax(base: sampleData.definitions),
          ),
        ),
      ),
    );
    expect(find.byIcon(elementTypeFallbackIcon), findsOneWidget);
  });

  testWidgets('名前と属性の札・威力・特殊効果の説明と PP を別の段と書体で描く', (tester) async {
    await pumpMoveCard(
      tester: tester,
      remainingPowerPoints: 12,
      moveId: effectMove.id,
      typeMultiplier: null,
    );
    // 名前は見出しの書体で、説明 (本文の書体) と区別する
    expect(
      tester.widget<Text>(find.text('ゆげのもや')).style?.fontFamily,
      headingFontFamily,
    );
    expect(
      tester
          .widget<ElementTypeIcon>(find.byType(ElementTypeIcon))
          .elementTypeId,
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
    // 1 段目は名前の右に属性のアイコン、その下に威力、いちばん下に説明と PP が並ぶ
    expect(
      tester.getTopLeft(find.byType(ElementTypeIcon)).dx,
      greaterThanOrEqualTo(tester.getTopRight(find.text('ゆげのもや')).dx),
    );
    expect(
      tester
          .getTopLeft(find.text('威力 ${effectMove.power}', findRichText: true))
          .dy,
      greaterThanOrEqualTo(
        tester.getBottomLeft(find.byType(ElementTypeIcon)).dy,
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
    // PP は段の右端に付く (説明と幅を分け合って右に空白が残る形にしない)
    expect(
      tester.getTopRight(find.text('PP 12/${effectMove.powerPoints}')).dx,
      moreOrLessEquals(tester.getTopRight(find.byType(MoveCard)).dx),
    );
  });

  testWidgets('バトルの外 (残りの PP が null) では最大の PP だけを出し、特殊効果が無ければ説明を出さない', (
    tester,
  ) async {
    await pumpMoveCard(
      tester: tester,
      remainingPowerPoints: null,
      moveId: plainMove.id,
      typeMultiplier: null,
    );
    expect(find.text('PP ${plainMove.powerPoints}'), findsOneWidget);
    // 文字は名前・威力・PP の 3 つだけで、説明の段と相性のアイコンは無い (属性はアイコンで、文字を持たない。
    // RichText で数えないのは、Icon の字形も RichText で描かれるため)
    expect(find.byType(Text), findsNWidgets(3));
    expect(find.byKey(const Key('move-type-effectiveness')), findsNothing);
  });

  // 等倍 (1) は「似ているが出さない」側。0.25・4 は 2 属性の相手への積で、画面では ×2・×0.5 と同じ矢印になり、
  // 読み上げの名前でだけ区別できる。倍率と言葉は画面に出さず、読み上げの名前にだけ持つ
  for (final (typeMultiplier, expectedIcon, expectedLabel) in [
    (2.0, Icons.keyboard_double_arrow_up, '効果は抜群 ×2'),
    (4.0, Icons.keyboard_double_arrow_up, '効果は抜群 ×4'),
    (0.5, Icons.keyboard_double_arrow_down, '効果はいまひとつ ×0.5'),
    (0.25, Icons.keyboard_double_arrow_down, '効果はいまひとつ ×0.25'),
    (1.0, null, null),
    (null, null, null),
  ]) {
    testWidgets('相性の倍率 $typeMultiplier は ${expectedLabel ?? '出さない'}', (
      tester,
    ) async {
      // 読み上げの名前を find.bySemanticsLabel で確かめるため。テストの終わりの検査より前に dispose する必要があり、addTearDown では間に合わない
      final semanticsHandle = tester.ensureSemantics();
      await pumpMoveCard(
        tester: tester,
        remainingPowerPoints: 12,
        moveId: plainMove.id,
        typeMultiplier: typeMultiplier,
      );
      final effectivenessTag = find.byKey(const Key('move-type-effectiveness'));
      if (expectedLabel == null) {
        expect(effectivenessTag, findsNothing);
        expect(find.byIcon(Icons.keyboard_double_arrow_up), findsNothing);
        expect(find.byIcon(Icons.keyboard_double_arrow_down), findsNothing);
      } else {
        expect(tester.widget<Icon>(effectivenessTag).icon, expectedIcon);
        expect(find.bySemanticsLabel(expectedLabel), findsOneWidget);
        expect(find.text(expectedLabel), findsNothing);
        // 倍率の文字は画面に出さない (丸の中は矢印だけ)
        expect(find.textContaining('×'), findsNothing);
        // 属性のアイコンの右に並べ、属性と相性を続けて読ませる
        expect(
          tester.getTopLeft(effectivenessTag).dx,
          greaterThan(tester.getTopRight(find.byType(ElementTypeIcon)).dx),
        );
      }
      semanticsHandle.dispose();
    });
  }
}
