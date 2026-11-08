import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:snapmon/features/developer_menu/move_effect_preview_screen.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../card_sharer_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  testWidgets('横向きのスマホ (844×390) でも属性の一覧が見え、選ぶとその属性が選ばれた状態になる', (tester) async {
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
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('fire_particle'));
    await tester.pump(const Duration(milliseconds: 700));

    expect(tester.takeException(), isNull);
    final fireTile = tester.widget<ListTile>(
      find.widgetWithText(ListTile, 'fire_particle'),
    );
    expect(fireTile.selected, isTrue);
    // 当て続けるタイマーを画面を閉じて止める
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
