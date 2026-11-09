import 'package:flutter/rendering.dart';

import '../domain/monster/monster_definition.dart';
import '../domain/random/deterministic_random.dart';
import '../theme/snapmon_colors.dart';

/// 仮の絵の形の種類の数。AI 生成のイラスト (#13・ADR 0002) が入るまでの絵で、識別子のハッシュから選ぶ。
const int _placeholderShapeCount = 3;

/// [definition] のモンスターの仮の絵を [canvas] の [size] の範囲に描く。
/// 色は属性 (1 つめが体、2 つめが頭の飾り)、形は識別子のハッシュで決まり、同じモンスターは毎回同じ絵になる。
/// Flutter の画面 ([PlaceholderMonsterArt]) と Flame のバトルのフィールドの両方から使う。
void paintPlaceholderMonster({
  required Canvas canvas,
  required Size size,
  required MonsterDefinition definition,
}) {
  final bodyColor = elementTypeColor(
    elementTypeId: definition.elementTypeIds.first,
  );
  final accentColor = definition.elementTypeIds.length > 1
      ? elementTypeColor(elementTypeId: definition.elementTypeIds[1])
      : Color.lerp(bodyColor, SnapmonColors.background, 0.3)!;
  final shape = fnv1a32(text: definition.id) % _placeholderShapeCount;
  final width = size.width;
  final height = size.height;
  final bodyRect = switch (shape) {
    0 => Rect.fromLTWH(width * 0.2, height * 0.32, width * 0.6, height * 0.5),
    1 => Rect.fromLTWH(width * 0.3, height * 0.22, width * 0.4, height * 0.62),
    _ => Rect.fromLTWH(width * 0.16, height * 0.4, width * 0.68, height * 0.4),
  };
  final bodyRadius = Radius.circular(switch (shape) {
    0 => bodyRect.width * 0.45,
    1 => bodyRect.width * 0.2,
    _ => bodyRect.height * 0.5,
  });
  canvas
    ..drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(bodyRect.center.dx, bodyRect.top),
          width: bodyRect.width * 0.3,
          height: bodyRect.height * 0.36,
        ),
        Radius.circular(bodyRect.width * 0.15),
      ),
      Paint()..color = accentColor,
    )
    ..drawRRect(
      RRect.fromRectAndRadius(bodyRect, bodyRadius),
      Paint()..color = bodyColor,
    );
  final eyePaint = Paint()..color = SnapmonColors.background;
  final eyeRadius = width * 0.045;
  final eyeY = bodyRect.top + bodyRect.height * 0.4;
  for (final eyeX in [
    bodyRect.center.dx - bodyRect.width * 0.17,
    bodyRect.center.dx + bodyRect.width * 0.17,
  ]) {
    canvas.drawCircle(Offset(eyeX, eyeY), eyeRadius, eyePaint);
  }
}
