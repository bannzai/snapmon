import 'package:flutter/material.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/square_icon_button.dart';
import '../dex/dex_store.dart';
import '../home/home_shell.dart';
import '../result/result_screen.dart';
import 'sample_generation.dart';

/// 撮る画面 (モックの Main.dc.html)。カメラ・アルバムの読み込みと生成 (#13・#14) を繋ぐまでは、
/// シャッターとアルバムのボタンで見本のモンスターが生まれる。
class CaptureScreen extends StatelessWidget {
  /// 撮る画面を作る。
  const CaptureScreen({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.onSelectTab,
    required this.onOpenSettings,
  });

  /// 見本データ。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 下タブを切り替える。
  final void Function({required HomeTab tab}) onSelectTab;

  /// 設定画面を開く。
  final VoidCallback onOpenSettings;

  Future<void> _generate({required BuildContext context}) async {
    // builder は再び呼ばれることがあるため、生成は push の前に 1 回だけ行う
    final monster = generateSampleMonster(
      sampleData: sampleData,
      dexStore: dexStore,
    );
    final action = await Navigator.of(context).push(
      MaterialPageRoute<ResultScreenAction>(
        builder: (context) => ResultScreen(
          monster: monster,
          sampleData: sampleData,
          dexStore: dexStore,
          isNewlyBorn: true,
        ),
      ),
    );
    if (action == ResultScreenAction.openDex) {
      onSelectTab(tab: HomeTab.dex);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Row(
          children: [
            // 端末の文字を大きくした時は、右のボタンを押し出さないようロゴの方を縮める
            const Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('snapmon', style: SnapmonTextStyles.logo),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: dexStore,
              builder: (context, _) => Material(
                color: SnapmonColors.surface,
                borderRadius: SnapmonRadii.button,
                child: InkWell(
                  borderRadius: SnapmonRadii.button,
                  onTap: () => onSelectTab(tab: HomeTab.dex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.grid_view_rounded,
                          color: SnapmonColors.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '図鑑 ${dexStore.monsters.length}',
                          style: SnapmonTextStyles.label,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SquareIconButton(
              icon: Icons.settings_outlined,
              tooltip: '設定',
              onPressed: onOpenSettings,
              size: 44,
            ),
          ],
        ),
      ),
      const Expanded(child: _Viewfinder()),
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Text(
          '身の回りの物を撮る\nモンスターが生まれる',
          textAlign: TextAlign.center,
          style: SnapmonTextStyles.hero,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SquareIconButton(
              icon: Icons.photo_library_outlined,
              tooltip: 'アルバムから選ぶ',
              onPressed: () => _generate(context: context),
              size: 56,
            ),
            const SizedBox(width: 28),
            Tooltip(
              message: '撮る',
              child: Material(
                color: SnapmonColors.accent,
                shape: const CircleBorder(
                  side: BorderSide(color: SnapmonColors.background, width: 6),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _generate(context: context),
                  child: const SizedBox.square(
                    dimension: 84,
                    child: Icon(
                      Icons.photo_camera_outlined,
                      color: SnapmonColors.textOnCard,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 28),
            SquareIconButton(
              icon: Icons.sports_martial_arts,
              tooltip: '対戦する',
              onPressed: () => onSelectTab(tab: HomeTab.opponent),
              size: 56,
            ),
          ],
        ),
      ),
    ],
  );
}

/// ファインダー。カメラの映像 (#14) を繋ぐまでは枠と案内だけを描く。
class _Viewfinder extends StatelessWidget {
  const _Viewfinder();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: ClipRRect(
      borderRadius: SnapmonRadii.panel,
      child: ColoredBox(
        color: SnapmonColors.surfaceRaised,
        child: Stack(
          children: [
            for (final alignment in [
              Alignment.topLeft,
              Alignment.topRight,
              Alignment.bottomLeft,
              Alignment.bottomRight,
            ])
              Align(
                alignment: alignment,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _ViewfinderCorner(alignment: alignment),
                ),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: SnapmonColors.scrim,
                    borderRadius: SnapmonRadii.button,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Text('被写体を枠に入れる', style: SnapmonTextStyles.body),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// ファインダーの四隅の鉤形。
class _ViewfinderCorner extends StatelessWidget {
  const _ViewfinderCorner({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Transform.scale(
    // 左上の鉤形を描き、他の隅は左右・上下に反転して描く
    scaleX: alignment.x < 0 ? 1 : -1,
    scaleY: alignment.y < 0 ? 1 : -1,
    child: const CustomPaint(
      size: Size.square(36),
      painter: _ViewfinderCornerPainter(),
    ),
  );
}

class _ViewfinderCornerPainter extends CustomPainter {
  const _ViewfinderCornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 4.0;
    const cornerRadius = 10.0;
    const inset = strokeWidth / 2;
    canvas.drawPath(
      Path()
        ..moveTo(inset, size.height)
        ..lineTo(inset, inset + cornerRadius)
        ..arcToPoint(
          const Offset(inset + cornerRadius, inset),
          radius: const Radius.circular(cornerRadius),
        )
        ..lineTo(size.width, inset),
      Paint()
        ..color = SnapmonColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderCornerPainter oldDelegate) => false;
}
