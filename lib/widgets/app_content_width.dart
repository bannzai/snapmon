import 'dart:math';

import 'package:flutter/widgets.dart';

import '../theme/snapmon_colors.dart';

/// 画面の内容の幅の上限 (論理ピクセル)。
///
/// Material 3 の window size class で compact (スマホの縦) の上限が 600dp のため
/// ( https://m3.material.io/foundations/layout/applying-layout/window-size-classes )。
/// スマホの縦の幅 (モックの 390px を含む) は上限に届かず今と同じに描き、
/// それより広い画面 (PC の Web・iPad) だけをこの幅に収める。
const double appContentMaxWidth = 600;

/// [child] (アプリの全画面を載せる Navigator) を幅 [appContentMaxWidth] までに収めて中央に寄せる。
///
/// 下タブ・ダイアログ・ボトムシートも同じ幅に収まる。内側の [MediaQuery] の幅も収めた幅に揃え、
/// 画面の幅から大きさを決める widget が広い画面の幅で描かないようにする。左右の余白は地の色で塗る。
/// 幅が上限を跨いで変わっても木の形を変えない (Navigator の状態を失わないため)。
Widget constrainToAppContentWidth({required Widget child}) => LayoutBuilder(
  builder: (context, constraints) {
    final mediaQuery = MediaQuery.of(context);
    final contentWidth = min(constraints.maxWidth, appContentMaxWidth);
    return ColoredBox(
      color: SnapmonColors.background,
      child: Center(
        child: SizedBox(
          width: contentWidth,
          height: constraints.maxHeight,
          child: MediaQuery(
            data: mediaQuery.copyWith(
              size: Size(contentWidth, mediaQuery.size.height),
            ),
            child: child,
          ),
        ),
      ),
    );
  },
);
