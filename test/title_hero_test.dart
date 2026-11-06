import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/title/title_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

void main() {
  /// タイトル画面のヒーローだけを開く。[disableAnimations] は端末の「視差効果を減らす」。
  Future<void> pumpHero({
    required WidgetTester tester,
    required bool disableAnimations,
  }) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: disableAnimations);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: SizedBox(width: 390, height: 400, child: TitleHero()),
        ),
      ),
    );
  }

  /// 今描いているヒーローの絵。
  TitleHeroPainter heroPainter({required WidgetTester tester}) => tester
      .widgetList<CustomPaint>(
        find.descendant(
          of: find.byType(TitleHero),
          matching: find.byType(CustomPaint),
        ),
      )
      .map((customPaint) => customPaint.painter)
      .whereType<TitleHeroPainter>()
      .single;

  group('タイトル画面のマグカップの目', () {
    testWidgets('時間を進めると瞬きし、黒目が動く', (tester) async {
      await pumpHero(tester: tester, disableAnimations: false);
      final initialPainter = heroPainter(tester: tester);
      expect(initialPainter.eyeLidClosure, 0);
      expect(initialPainter.pupilOffset, Offset.zero);

      // 1 回目の瞬きの途中 (1.8 秒から 0.16 秒) で、黒目は左を見ている
      await tester.pump(const Duration(milliseconds: 1880));
      final blinkingPainter = heroPainter(tester: tester);
      expect(blinkingPainter.eyeLidClosure, greaterThan(.9));
      expect(blinkingPainter.pupilOffset.dx, lessThan(0));

      // 瞬きを終えて目が開き、黒目は右を見ている
      await tester.pump(const Duration(milliseconds: 1720));
      final lookingRightPainter = heroPainter(tester: tester);
      expect(lookingRightPainter.eyeLidClosure, 0);
      expect(lookingRightPainter.pupilOffset.dx, greaterThan(0));
    });

    testWidgets('「視差効果を減らす」が有効な時は、時間を進めても目を開いたまま黒目を動かさない', (tester) async {
      await pumpHero(tester: tester, disableAnimations: true);
      for (final elapsed in const [
        Duration(milliseconds: 1880),
        Duration(milliseconds: 1720),
        Duration(milliseconds: 1200),
      ]) {
        await tester.pump(elapsed);
        final painter = heroPainter(tester: tester);
        expect(painter.eyeLidClosure, 0);
        expect(painter.pupilOffset, Offset.zero);
      }
    });
  });

  group('titleHeroEyePose', () {
    test('周期の始まりは、目を開いて黒目を今の絵の位置に置く', () {
      for (final elapsed in [Duration.zero, titleHeroEyeCycle]) {
        final eyePose = titleHeroEyePose(elapsed: elapsed);
        expect(eyePose.eyeLidClosure, 0);
        expect(eyePose.pupilOffset, Offset.zero);
      }
    });

    test('1 周期の中で 4 回瞬きする', () {
      var blinkCount = 0;
      var wasClosed = false;
      for (
        var milliseconds = 0;
        milliseconds < titleHeroEyeCycle.inMilliseconds;
        milliseconds += 10
      ) {
        final isClosed =
            titleHeroEyePose(
              elapsed: Duration(milliseconds: milliseconds),
            ).eyeLidClosure >
            .5;
        if (isClosed && !wasClosed) {
          blinkCount++;
        }
        wasClosed = isClosed;
      }
      expect(blinkCount, 4);
    });

    test('黒目は左・右・上を見て、しばらく止まる', () {
      Offset pupilOffsetAt({required int milliseconds}) => titleHeroEyePose(
        elapsed: Duration(milliseconds: milliseconds),
      ).pupilOffset;

      expect(pupilOffsetAt(milliseconds: 2000), const Offset(-8, 0));
      expect(pupilOffsetAt(milliseconds: 2700), const Offset(-8, 0));
      expect(pupilOffsetAt(milliseconds: 3800), const Offset(2, 0));
      expect(pupilOffsetAt(milliseconds: 5000).dy, lessThan(0));
      expect(pupilOffsetAt(milliseconds: 7000), Offset.zero);
    });
  });
}
