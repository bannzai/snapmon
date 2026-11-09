import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_text_styles.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/monster_ui/monster_parts.dart';
import 'package:snapmon/monster_ui/move_card.dart';

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

  testWidgets('2 列の技のボタンの幅で文字を 3 倍にしても 1 段目がはみ出さず、札が名前の下の行に下りる', (
    tester,
  ) async {
    // 390 の画面の 2 列の技のボタンの幅 (173) に、2 枚の札を 3 倍の文字で入れる。
    // 名前と札を Row に並べると「RenderFlex overflowed」の例外が出る (Codex のレビューと観点レビューの指摘)
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
    final elementTypeTag = find.byType(ElementTypeTag);
    final effectivenessTag = find.byKey(const Key('move-type-effectiveness'));
    expect(effectivenessTag, findsOneWidget);
    // 札は名前の右に並ばず、名前の下の行に下りる
    expect(
      tester.getTopLeft(elementTypeTag).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('ブリキパンチ')).dy),
    );
    // どの札も技のボタンの幅からはみ出さない
    expect(
      tester.getBottomRight(effectivenessTag).dx,
      lessThanOrEqualTo(tester.getTopRight(find.byType(MoveCard)).dx),
    );
  });

  testWidgets('バトルの技のボタンの属性の札は、カードの属性の札より余白と文字が小さい', (tester) async {
    // 2 列の技のボタンの幅 (390 の画面で約 142) に名前と 2 枚の札を並べるため、技のボタンの中だけ小さくする。
    // 他の画面 (モンスターのカード・図鑑・技の詳細) の札は変えない (https://github.com/bannzai/snapmon/issues/281 )
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(
            children: [
              ElementTypeTag(
                key: const Key('card-tag'),
                elementTypeId: plainMove.elementTypeId,
                definitions: sampleData.definitions,
              ),
              MoveCard(
                key: const Key('battle-move'),
                move: plainMove,
                remainingPowerPoints: 12,
                typeMultiplier: 2,
                definitions: sampleData.definitions,
              ),
              // モンスターのカードの覚えている技の行 (バトルの外。残りの PP が無い) は同じ MoveCard を通るが、札は小さくしない
              MoveCard(
                key: const Key('card-move'),
                move: plainMove,
                remainingPowerPoints: null,
                typeMultiplier: null,
                definitions: sampleData.definitions,
              ),
            ],
          ),
        ),
      ),
    );
    final cardTag = find.byKey(const Key('card-tag'));
    final moveTag = find.descendant(
      of: find.byKey(const Key('battle-move')),
      matching: find.byType(ElementTypeTag),
    );
    expect(
      tester.getSize(
        find.descendant(
          of: find.byKey(const Key('card-move')),
          matching: find.byType(ElementTypeTag),
        ),
      ),
      tester.getSize(cardTag),
    );
    // 余白 8/4 + 文字 11 のカードの札に対し、技のボタンの札は余白 6/2 + 文字 10 で、幅・高さとも小さい
    expect(
      tester.getSize(moveTag).width,
      lessThan(tester.getSize(cardTag).width),
    );
    expect(
      tester.getSize(moveTag).height,
      lessThan(tester.getSize(cardTag).height),
    );
    // 相性の札 (余白 4/2 + 矢印 14) も、カードの属性の札より低い
    expect(
      tester.getSize(find.byKey(const Key('move-type-effectiveness'))).height,
      lessThan(tester.getSize(cardTag).height),
    );
  });

  testWidgets('名前と属性の札・威力・特殊効果の説明と PP を別の段と書体で描く', (tester) async {
    await pumpMoveCard(
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
    // 名前・札の中の属性名・威力・PP の 4 つだけで、説明の段と相性の札は無い
    expect(find.byType(RichText), findsNWidgets(4));
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
        // 倍率の文字は画面に出さない (札の中は矢印だけ)
        expect(find.textContaining('×'), findsNothing);
        // 属性の札の右に並べ、「鋼 ⇈」のように属性と相性を続けて読ませる
        expect(
          tester.getTopLeft(effectivenessTag).dx,
          greaterThan(tester.getTopRight(find.byType(ElementTypeTag)).dx),
        );
      }
      semanticsHandle.dispose();
    });
  }
}
