import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 写真から切り出した被写体の画像 [artImage] を、[canvas] の [size] の範囲に縦横比を保って収めて (中央寄せ) 描く。
/// 図鑑・生まれた画面のカード、共有カード、バトルのフィールドの 3 か所から使い、同じモンスターは同じ見た目になる。
/// 保存された装飾のパラメータ (`decoration`) は描かない (DIRECTION.md「決めたこと」2026-10-29。物に見えるのが楽しいため)。
/// 切り出した画像は被写体ごとに縦横比が違うため引き伸ばさない。
void paintMonsterArt({
  required Canvas canvas,
  required Size size,
  required ui.Image artImage,
}) {
  final scale = math.min(
    size.width / artImage.width,
    size.height / artImage.height,
  );
  canvas.drawImageRect(
    artImage,
    Rect.fromLTWH(0, 0, artImage.width.toDouble(), artImage.height.toDouble()),
    Rect.fromCenter(
      center: (Offset.zero & size).center,
      width: artImage.width * scale,
      height: artImage.height * scale,
    ),
    Paint()..filterQuality = FilterQuality.medium,
  );
}
