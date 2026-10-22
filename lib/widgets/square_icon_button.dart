import 'package:flutter/material.dart';

import '../theme/snapmon_colors.dart';
import '../theme/snapmon_radii.dart';

/// 四角に近い角丸の、アイコンだけのボタン (設定・戻る・アルバムなど)。
class SquareIconButton extends StatelessWidget {
  /// アイコンのボタンを作る。[tooltip] は読み上げとテストの検索に使う。
  const SquareIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.size,
  });

  /// 描くアイコン。
  final IconData icon;

  /// ボタンの説明。
  final String tooltip;

  /// 押した時の処理。
  final VoidCallback onPressed;

  /// ボタンの一辺の長さ。
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: Material(
      color: SnapmonColors.surface,
      borderRadius: SnapmonRadii.button,
      child: InkWell(
        borderRadius: SnapmonRadii.button,
        onTap: onPressed,
        child: SizedBox.square(
          dimension: size,
          child: Icon(icon, color: SnapmonColors.textOnBackground, size: 22),
        ),
      ),
    ),
  );
}
