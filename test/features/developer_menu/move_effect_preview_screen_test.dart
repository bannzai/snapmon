import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:snapmon/features/developer_menu/move_effect_preview_screen.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../card_sharer_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  testWidgets('横向きのスマホ (844×390) でも技の一覧が見え、選ぶとその技のエフェクトが選ばれた状態になる', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(844, 390)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        home: MoveEffectPreviewScreen(
          playerMonster: sampleData.monsters[0],
          opponentMonster: sampleData.monsters[1],
          cardSharer: fakeCardSharer(
            calls: RecordedShareCalls(),
            artImage: null,
            shareResultStatus: ShareResultStatus.success,
          ),
          definitions: sampleData.definitions,
        ),
      ),
    );
    await tester.pump();

    // 一覧の先頭は炎の段階 1 の技のエフェクト (master の effects の順)
    const fireTile = Key('move-effect-preview-fire_1');
    expect(find.byKey(fireTile), findsOneWidget);
    await tester.tap(find.byKey(fireTile));
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.takeException(), isNull);
    expect(tester.widget<ListTile>(find.byKey(fireTile)).selected, isTrue);
    // 当て続けるタイマーを画面を閉じて止める
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
