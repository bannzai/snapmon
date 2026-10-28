import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../domain/monster/monster_decoration.dart';
import '../features/dex/owned_monster.dart';
import '../theme/snapmon_colors.dart';

/// 装飾を重ねる時に、絵の枠の各辺から空ける割合 (枠の短い辺に対する)。手足とオーラが枠の外に切れないようにするため、
/// 被写体の大きさの 1/4 ほどはみ出すオーラ (後述の [_auraReachRatio]) が収まる値にした。
const double _decorationPaddingRatio = 0.12;

/// 切り出した画像の縁にある、被写体の外の余白の割合 (画像の長い辺に対する。4 辺とも同じ幅)。
/// functions/src/generation/cutout.ts の `applyMask` は被写体の長い辺の `CUTOUT_MARGIN_RATIO` (0.04) を 4 辺に同じ幅で足すため、
/// 画像の長い辺 (被写体の長い辺の 1.08 倍) で割った値になる。被写体の範囲を測っていない画像 ([measureArtSubjectBounds] を通らない、
/// テストの画像など) で、画像の枠から被写体の枠を見積もるのに使う。
const double _cutoutMarginRatio = 0.04 / 1.08;

/// オーラが被写体の縁からはみ出す長さ (被写体の幅・高さの半分に対する割合)。被写体を包む光に見え、隣の絵と重ならない長さにした。
const double _auraReachRatio = 0.25;

/// 輪郭線の太さ (絵の枠の短い辺に対する割合)。カードの小さな絵 (100 px 前後) でも 2〜3 px になり見える太さにした。
const double _outlineWidthRatio = 0.025;

/// 両目の中心の間隔 (目の直径に対する割合)。2 つの目が触れずに並んで 1 つの顔に見える間隔にした。
const double _eyeSpacingRatio = 1.4;

/// 目の半径の下限 (絵の枠の短い辺に対する割合)。横に広い被写体で eyeScale が小さいと、カードやバトルの小さな絵
/// (100 px 前後) で目が数 px になり見えなくなったため (サボテンの見本の写真で確認)。切り出した画像の範囲ではなく枠に対して決めるのは、
/// 横に広い被写体では画像の範囲の短い辺が枠より大きく縮み、下限も一緒に小さくなってしまうため。
const double _minEyeRadiusRatio = 0.07;

/// 目と口の黒。画面の地の色と同じにして、モックの色の数を増やさない。
const Color _inkColor = SnapmonColors.background;

/// 目の白。カードの生成りの白と同じにする。
const Color _eyeWhiteColor = SnapmonColors.card;

/// 被写体の画素とみなす不透明度の下限 (0〜255)。切り出しの縁のなめらかにした半透明の画素を被写体の外に数えるため、半分にした。
const int _subjectAlphaThreshold = 128;

/// 切り出した画像ごとの、被写体の画素を囲む範囲 (画像の画素の座標)。[measureArtSubjectBounds] が書き、
/// 画像が捨てられると一緒に消える。測っていない画像は、切り出しの余白から見積もる。
final Expando<Rect> _subjectBoundsByArtImage = Expando();

/// [artImage] の不透明な画素 (被写体) を囲む範囲を測って覚え、以後の [paintMonsterArt] が手足・目・口を被写体の縁に合わせて置く。
/// 写真の端に接する被写体は切り出しの余白が切り詰められ、画像の枠から余白を見積もれないため、実際の画素から測る。
/// 不透明な画素が無い時と画素を読めない時は覚えない (余白からの見積もりのまま描く)。同じ画像に何度呼んでも結果は同じ。
Future<void> measureArtSubjectBounds({required ui.Image artImage}) async {
  final byteData = await artImage.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  if (byteData == null) {
    return;
  }
  final pixels = byteData.buffer.asUint8List();
  var left = artImage.width;
  var top = artImage.height;
  var right = -1;
  var bottom = -1;
  for (var y = 0; y < artImage.height; y++) {
    for (var x = 0; x < artImage.width; x++) {
      if (pixels[(y * artImage.width + x) * 4 + 3] >= _subjectAlphaThreshold) {
        left = math.min(left, x);
        right = math.max(right, x);
        top = math.min(top, y);
        bottom = math.max(bottom, y);
      }
    }
  }
  if (right < 0) {
    return;
  }
  _subjectBoundsByArtImage[artImage] = Rect.fromLTRB(
    left.toDouble(),
    top.toDouble(),
    right + 1.0,
    bottom + 1.0,
  );
}

/// [monster] の切り出した被写体の画像 [artImage] を、[canvas] の [size] の範囲に縦横比を保って収めて描き、
/// [OwnedMonster.decoration] があれば装飾 (属性のオーラ・手足・輪郭線・目・口) を重ねる。
/// 図鑑・生まれた画面のカード、共有カード、バトルのフィールドの 3 か所から使い、同じモンスターは同じ見た目になる。
/// 装飾の描き方は [OwnedMonster.decorationVersion] ごとに分ける (生まれた時の見た目を後から変えないため。
/// 描き方を変える時は版を足し、既存の版の描き方は変えない)。装飾が無い時 (描けない版を含む) は画像だけを枠いっぱいに描く。
void paintMonsterArt({
  required Canvas canvas,
  required Size size,
  required OwnedMonster monster,
  required ui.Image artImage,
}) {
  final decoration = monster.decoration;
  switch (monster.decorationVersion) {
    case 1 when decoration != null:
      _paintDecorationVersion1(
        canvas: canvas,
        size: size,
        monster: monster,
        decoration: decoration,
        artImage: artImage,
      );
    default:
      canvas.drawImageRect(
        artImage,
        _imageSourceRect(image: artImage),
        _containRect(image: artImage, bounds: Offset.zero & size),
        Paint()..filterQuality = FilterQuality.medium,
      );
  }
}

/// [image] の全体の範囲。
Rect _imageSourceRect({required ui.Image image}) =>
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

/// [image] を縦横比を保って [bounds] に収めた時の範囲 (中央寄せ)。切り出した画像は被写体ごとに縦横比が違うため引き伸ばさない。
Rect _containRect({required ui.Image image, required Rect bounds}) {
  final scale = math.min(
    bounds.width / image.width,
    bounds.height / image.height,
  );
  return Rect.fromCenter(
    center: bounds.center,
    width: image.width * scale,
    height: image.height * scale,
  );
}

/// `#RRGGBB` の色。
Color _colorFromHex({required String colorHex}) =>
    Color(0xFF000000 | int.parse(colorHex.substring(1), radix: 16));

/// 描画の版 1 の装飾。奥から順に、属性のオーラ・手足・輪郭線・切り出した画像・目・口を描く。
/// 目の位置 ([MonsterDecoration.eyeCenterX]・[MonsterDecoration.eyeCenterY]) は、Claude が見た画像 (切り出した画像と同じ大きさ) に
/// 対する割合なので、画像を描いた範囲に対して決める。
void _paintDecorationVersion1({
  required Canvas canvas,
  required Size size,
  required OwnedMonster monster,
  required MonsterDecoration decoration,
  required ui.Image artImage,
}) {
  final artRect = _containRect(
    image: artImage,
    bounds: (Offset.zero & size).deflate(
      size.shortestSide * _decorationPaddingRatio,
    ),
  );
  final subjectBounds = _subjectBoundsByArtImage[artImage];
  final artScale = artRect.width / artImage.width;
  final subjectRect = subjectBounds == null
      // 測っていない画像は余白から見積もる。写真の端で余白が切り詰められた細い画像では、長い辺の余白が短い辺の半分を超えて
      // 枠の幅が負になり、手足の角丸 (負の半径を assert で拒む) と目の大きさが壊れるため、短い辺の半分までに抑える
      ? artRect.deflate(
          math.min(
            artRect.longestSide * _cutoutMarginRatio,
            artRect.shortestSide / 2,
          ),
        )
      : Rect.fromLTRB(
          artRect.left + subjectBounds.left * artScale,
          artRect.top + subjectBounds.top * artScale,
          artRect.left + subjectBounds.right * artScale,
          artRect.top + subjectBounds.bottom * artScale,
        );
  final outlineColor = _colorFromHex(colorHex: decoration.outlineColorHex);
  _paintAura(
    canvas: canvas,
    subjectRect: subjectRect,
    auraStyle: decoration.auraStyle,
    auraColor: elementTypeColor(
      elementTypeId: monster.definition.elementTypeIds.first,
    ),
  );
  _paintLimbs(
    canvas: canvas,
    subjectRect: subjectRect,
    limbStyle: decoration.limbStyle,
    limbColor: outlineColor,
  );
  // 線の太さの下限 (1〜2 px) は、小さな絵でも線が途切れず 1 本の線に見える最小の太さとして置いた (以下の線も同じ)
  final outlineWidth = math.max(1.5, artRect.shortestSide * _outlineWidthRatio);
  // 被写体の形を輪郭線の色で塗った画像を周りにずらして重ね、上に元の画像を描くと、はみ出た分が輪郭線になる
  final outlinePaint = Paint()
    ..colorFilter = ColorFilter.mode(outlineColor, BlendMode.srcIn);
  for (var index = 0; index < 8; index++) {
    final angle = index * math.pi / 4;
    canvas.drawImageRect(
      artImage,
      _imageSourceRect(image: artImage),
      artRect.shift(Offset(math.cos(angle), math.sin(angle)) * outlineWidth),
      outlinePaint,
    );
  }
  canvas.drawImageRect(
    artImage,
    _imageSourceRect(image: artImage),
    artRect,
    Paint()..filterQuality = FilterQuality.medium,
  );
  // 両目の外端は中心から (間隔 + 1) 個分の半径、口の下端は目の中心から半径の 3 倍下にある。
  // 細長い被写体で下限の大きさの目が被写体からはみ出さないよう、両目と口が被写体の枠に収まる大きさと位置に抑える
  final eyeReach = _eyeSpacingRatio + 1;
  final eyeRadius = math.min(
    math.max(
      subjectRect.width * decoration.eyeScale / 2,
      size.shortestSide * _minEyeRadiusRatio,
    ),
    math.min(subjectRect.width / (eyeReach * 2), subjectRect.height / 4),
  );
  // 上限が効いた時は下端と上端が等しくなり、浮動小数の丸めで下端が上端を上回り得るため、
  // 下端 > 上端で例外を投げる num.clamp ではなく min・max で抑える
  final eyeCenter = Offset(
    math.min(
      math.max(
        artRect.left + artRect.width * decoration.eyeCenterX,
        subjectRect.left + eyeRadius * eyeReach,
      ),
      subjectRect.right - eyeRadius * eyeReach,
    ),
    math.min(
      math.max(
        artRect.top + artRect.height * decoration.eyeCenterY,
        subjectRect.top + eyeRadius,
      ),
      subjectRect.bottom - eyeRadius * 3,
    ),
  );
  for (final side in [-1.0, 1.0]) {
    _paintEye(
      canvas: canvas,
      center: eyeCenter + Offset(side * eyeRadius * _eyeSpacingRatio, 0),
      radius: eyeRadius,
      eyeStyle: decoration.eyeStyle,
      side: side,
    );
  }
  _paintMouth(
    canvas: canvas,
    center: eyeCenter + Offset(0, eyeRadius * 2),
    eyeRadius: eyeRadius,
    mouthStyle: decoration.mouthStyle,
  );
}

/// [subjectRect] の被写体を囲む [auraStyle] の形のオーラを [auraColor] で描く。
void _paintAura({
  required Canvas canvas,
  required Rect subjectRect,
  required MonsterAuraStyle auraStyle,
  required Color auraColor,
}) {
  final center = subjectRect.center;
  final radiusX = subjectRect.width / 2;
  final radiusY = subjectRect.height / 2;

  /// 被写体の中心から [angle] の向きに、縁から [reach] (半径に対する割合) だけ外の点。
  Offset pointAround({required double angle, required double reach}) =>
      center +
      Offset(
        math.cos(angle) * radiusX * (1 + reach),
        math.sin(angle) * radiusY * (1 + reach),
      );

  // オーラは被写体の後ろの光なので半透明にし、地の色が透けて被写体より目立たない濃さにした
  final fillPaint = Paint()..color = auraColor.withValues(alpha: 0.55);
  switch (auraStyle) {
    case MonsterAuraStyle.soft:
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: subjectRect.width * (1 + _auraReachRatio) * 1.1,
          height: subjectRect.height * (1 + _auraReachRatio) * 1.1,
        ),
        Paint()
          ..shader = ui.Gradient.radial(
            center,
            math.max(radiusX, radiusY) * (1 + _auraReachRatio) * 1.1,
            [auraColor.withValues(alpha: 0.7), auraColor.withValues(alpha: 0)],
          ),
      );
    case MonsterAuraStyle.flame:
      // 炎・稲妻・泡・葉の数は、被写体の周りを途切れずに囲み、1 つずつの形がつぶれずに見分けられる数にした
      const flameCount = 12;
      for (var index = 0; index < flameCount; index++) {
        final angle = index * 2 * math.pi / flameCount - math.pi / 2;
        final halfWidth = math.pi / flameCount;
        final base = pointAround(angle: angle - halfWidth, reach: -0.1);
        final bulge = pointAround(angle: angle - halfWidth * 0.2, reach: 0.15);
        final tip = pointAround(
          angle: angle + halfWidth * 0.5,
          reach: _auraReachRatio,
        );
        final baseEnd = pointAround(angle: angle + halfWidth, reach: -0.1);
        canvas.drawPath(
          Path()
            ..moveTo(base.dx, base.dy)
            ..quadraticBezierTo(bulge.dx, bulge.dy, tip.dx, tip.dy)
            ..lineTo(baseEnd.dx, baseEnd.dy)
            ..close(),
          fillPaint,
        );
      }
    case MonsterAuraStyle.spark:
      const sparkCount = 8;
      final strokePaint = Paint()
        ..color = auraColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5, subjectRect.shortestSide * 0.03)
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      for (var index = 0; index < sparkCount; index++) {
        final angle = index * 2 * math.pi / sparkCount;
        final start = pointAround(angle: angle, reach: 0.06);
        final kink = pointAround(angle: angle + 0.12, reach: 0.15);
        final end = pointAround(angle: angle - 0.04, reach: _auraReachRatio);
        canvas.drawPath(
          Path()
            ..moveTo(start.dx, start.dy)
            ..lineTo(kink.dx, kink.dy)
            ..lineTo(end.dx, end.dy),
          strokePaint,
        );
      }
    case MonsterAuraStyle.bubble:
      const bubbleCount = 9;
      final strokePaint = Paint()
        ..color = auraColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, subjectRect.shortestSide * 0.015);
      for (var index = 0; index < bubbleCount; index++) {
        final angle = index * 2 * math.pi / bubbleCount + 0.3;
        final bubbleCenter = pointAround(
          angle: angle,
          reach: index.isEven ? 0.12 : 0.18,
        );
        final bubbleRadius =
            subjectRect.shortestSide * (index.isEven ? 0.07 : 0.045);
        canvas
          ..drawCircle(bubbleCenter, bubbleRadius, fillPaint)
          ..drawCircle(bubbleCenter, bubbleRadius, strokePaint);
      }
    case MonsterAuraStyle.leaf:
      const leafCount = 8;
      for (var index = 0; index < leafCount; index++) {
        final angle = index * 2 * math.pi / leafCount + 0.2;
        final leafCenter = pointAround(angle: angle, reach: 0.14);
        canvas
          ..save()
          ..translate(leafCenter.dx, leafCenter.dy)
          ..rotate(angle + math.pi / 4)
          ..drawOval(
            Rect.fromCenter(
              center: Offset.zero,
              width: subjectRect.shortestSide * 0.2,
              height: subjectRect.shortestSide * 0.09,
            ),
            fillPaint,
          )
          ..restore();
      }
  }
}

/// [subjectRect] の被写体の縁から生える [limbStyle] の形の手足を [limbColor] で描く。被写体の画像より奥に描き、付け根を隠す。
void _paintLimbs({
  required Canvas canvas,
  required Rect subjectRect,
  required MonsterLimbStyle limbStyle,
  required Color limbColor,
}) {
  final width = subjectRect.width;
  final height = subjectRect.height;
  final fillPaint = Paint()..color = limbColor;
  final strokePaint = Paint()
    ..color = limbColor
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = math.max(2, subjectRect.shortestSide * 0.06);
  switch (limbStyle) {
    case MonsterLimbStyle.none:
      return;
    case MonsterLimbStyle.stubby:
      for (final ratioX in [0.3, 0.7]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(
                subjectRect.left + width * ratioX,
                subjectRect.bottom,
              ),
              width: width * 0.2,
              height: height * 0.18,
            ),
            Radius.circular(width * 0.08),
          ),
          fillPaint,
        );
      }
      for (final side in [-1.0, 1.0]) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(
              subjectRect.center.dx + side * width / 2,
              subjectRect.top + height * 0.58,
            ),
            width: width * 0.2,
            height: height * 0.13,
          ),
          fillPaint,
        );
      }
    case MonsterLimbStyle.long:
      for (final side in [-1.0, 1.0]) {
        final shoulder = Offset(
          subjectRect.center.dx + side * width * 0.42,
          subjectRect.top + height * 0.5,
        );
        final hand = Offset(
          subjectRect.center.dx + side * width * 0.68,
          subjectRect.top + height * 0.68,
        );
        canvas.drawPath(
          Path()
            ..moveTo(shoulder.dx, shoulder.dy)
            ..quadraticBezierTo(
              subjectRect.center.dx + side * width * 0.64,
              subjectRect.top + height * 0.46,
              hand.dx,
              hand.dy,
            ),
          strokePaint,
        );
        final hip = Offset(
          subjectRect.center.dx + side * width * 0.16,
          subjectRect.bottom - height * 0.08,
        );
        canvas.drawLine(
          hip,
          hip + Offset(side * width * 0.04, height * 0.2),
          strokePaint,
        );
      }
    case MonsterLimbStyle.wings:
      for (final side in [-1.0, 1.0]) {
        canvas
          ..save()
          ..translate(
            subjectRect.center.dx + side * width * 0.46,
            subjectRect.top + height * 0.38,
          )
          ..rotate(side * -0.5)
          ..drawOval(
            Rect.fromCenter(
              center: Offset(side * width * 0.14, 0),
              width: width * 0.34,
              height: height * 0.2,
            ),
            fillPaint,
          )
          ..restore();
      }
    case MonsterLimbStyle.tentacles:
      for (final ratioX in [0.2, 0.4, 0.6, 0.8]) {
        final root = Offset(
          subjectRect.left + width * ratioX,
          subjectRect.bottom - height * 0.06,
        );
        final sway = ratioX < 0.5 ? -1.0 : 1.0;
        canvas.drawPath(
          Path()
            ..moveTo(root.dx, root.dy)
            ..cubicTo(
              root.dx + sway * width * 0.08,
              root.dy + height * 0.08,
              root.dx - sway * width * 0.06,
              root.dy + height * 0.14,
              root.dx + sway * width * 0.05,
              root.dy + height * 0.22,
            ),
          strokePaint,
        );
      }
  }
}

/// [center] を中心に半径 [radius] の [eyeStyle] の目を描く。[side] は左目が -1、右目が 1 (つり目の傾きを左右で逆にするため)。
void _paintEye({
  required Canvas canvas,
  required Offset center,
  required double radius,
  required MonsterEyeStyle eyeStyle,
  required double side,
}) {
  final inkPaint = Paint()..color = _inkColor;
  final whitePaint = Paint()..color = _eyeWhiteColor;
  final rimPaint = Paint()
    ..color = _inkColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1, radius * 0.16);
  switch (eyeStyle) {
    case MonsterEyeStyle.round:
      canvas
        ..drawCircle(center, radius, whitePaint)
        ..drawCircle(center, radius, rimPaint)
        ..drawCircle(center, radius * 0.55, inkPaint)
        ..drawCircle(
          center + Offset(-radius * 0.2, -radius * 0.22),
          radius * 0.18,
          whitePaint,
        );
    case MonsterEyeStyle.sleepy:
      final lowerHalf = Path()
        ..addArc(Rect.fromCircle(center: center, radius: radius), 0, math.pi)
        ..close();
      canvas
        ..drawPath(lowerHalf, whitePaint)
        ..drawPath(lowerHalf, rimPaint)
        ..drawCircle(center + Offset(0, radius * 0.3), radius * 0.4, inkPaint);
    case MonsterEyeStyle.sharp:
      final eyeShape = Path()
        ..moveTo(center.dx - radius, center.dy - side * radius * 0.5)
        ..lineTo(center.dx + radius, center.dy + side * radius * 0.5)
        ..quadraticBezierTo(
          center.dx,
          center.dy + radius * 1.2,
          center.dx - radius,
          center.dy - side * radius * 0.5,
        )
        ..close();
      canvas
        ..drawPath(eyeShape, whitePaint)
        ..drawPath(eyeShape, rimPaint)
        ..drawCircle(center + Offset(0, radius * 0.3), radius * 0.4, inkPaint);
    // 黒で塗る目は、暗い被写体の上でも見えるよう白い縁を付ける
    case MonsterEyeStyle.sparkle:
      canvas
        ..drawCircle(center, radius * 1.35, whitePaint)
        ..drawCircle(center, radius, inkPaint)
        ..drawCircle(
          center + Offset(-radius * 0.3, -radius * 0.3),
          radius * 0.35,
          whitePaint,
        )
        ..drawCircle(
          center + Offset(radius * 0.35, radius * 0.35),
          radius * 0.15,
          whitePaint,
        );
    case MonsterEyeStyle.dot:
      canvas
        ..drawCircle(center, radius * 0.85, whitePaint)
        ..drawCircle(center, radius * 0.5, inkPaint);
  }
}

/// [center] を中心に、目の半径 [eyeRadius] に合わせた大きさの [mouthStyle] の口を描く。
void _paintMouth({
  required Canvas canvas,
  required Offset center,
  required double eyeRadius,
  required MonsterMouthStyle mouthStyle,
}) {
  final strokePaint = Paint()
    ..color = _inkColor
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = math.max(1.5, eyeRadius * 0.28);
  final smileRect = Rect.fromCenter(
    center: center - Offset(0, eyeRadius * 0.4),
    width: eyeRadius * 2,
    height: eyeRadius * 1.2,
  );
  switch (mouthStyle) {
    case MonsterMouthStyle.none:
      return;
    case MonsterMouthStyle.smile:
      canvas.drawArc(smileRect, 0.2, math.pi - 0.4, false, strokePaint);
    case MonsterMouthStyle.open:
      canvas.drawOval(
        Rect.fromCenter(
          center: center,
          width: eyeRadius * 1.3,
          height: eyeRadius * 0.95,
        ),
        Paint()..color = _inkColor,
      );
    case MonsterMouthStyle.fang:
      canvas.drawArc(smileRect, 0.2, math.pi - 0.4, false, strokePaint);
      for (final side in [-1.0, 1.0]) {
        final fangTop = Offset(
          center.dx + side * eyeRadius * 0.45,
          smileRect.center.dy + smileRect.height / 2 * 0.85,
        );
        final fang = Path()
          ..moveTo(fangTop.dx - eyeRadius * 0.18, fangTop.dy)
          ..lineTo(fangTop.dx + eyeRadius * 0.18, fangTop.dy)
          ..lineTo(fangTop.dx, fangTop.dy + eyeRadius * 0.45)
          ..close();
        canvas
          ..drawPath(fang, Paint()..color = _eyeWhiteColor)
          ..drawPath(
            fang,
            Paint()
              ..color = _inkColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1, eyeRadius * 0.1),
          );
      }
    case MonsterMouthStyle.flat:
      canvas.drawLine(
        center - Offset(eyeRadius * 0.8, 0),
        center + Offset(eyeRadius * 0.8, 0),
        strokePaint,
      );
  }
}
