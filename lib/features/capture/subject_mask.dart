import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import 'monster_generator.dart';

// 生成に送るマスク (被写体が白・背景が黒の PNG。大きさは生成に送る写真と同じ) を端末で作る。
// iOS 17 以降は OS の切り出し (ios/Runner/AppDelegate.swift の Vision の前景のマスク) を使い、使えない時はユーザーが crop で決めた
// 正方形の範囲をマスクにする。サーバーはこのマスクを検査済みの写真に当てて切り出す (functions/src/generation/cutout.ts、ADR 0002)。

/// OS の切り出しを呼ぶ platform channel (ios/Runner/AppDelegate.swift と同じ名前)。
const MethodChannel _subjectMaskChannel = MethodChannel('snapmon/subject_mask');

/// 生成に送る写真 [photo] (向きを画素に反映した JPEG) から、OS の切り出しのマスクを作る ([MonsterGenerator.createSubjectMask])。
/// iOS 以外 (Android・Web) と iOS 16 以前、被写体が見つからなかった時は null。Vision が失敗した時は [PlatformException] を投げる。
Future<Uint8List?> createSubjectMaskWithOs({required Uint8List photo}) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return null;
  }
  return _subjectMaskChannel.invokeMethod<Uint8List>(
    'createSubjectMask',
    photo,
  );
}

/// [photo] の画素の幅と高さ。画像の頭の部分だけを読む (全体を展開しない)。読めない形式は [FormatException] を投げる。
({int width, int height}) photoPixelSize({required Uint8List photo}) {
  final info = img.findDecoderForData(photo)?.startDecode(photo);
  if (info == null) {
    throw const FormatException('この写真の形式は読めません');
  }
  return (width: info.width, height: info.height);
}

/// crop の枠の一辺の下限 (写真の短辺に対する割合)。0.2: 長辺 1024px の写真で 150px 前後になり、Claude が物を読み取れる大きさを残す値として置いた。
const double _minimumSquareCropSideRatio = 0.2;

/// 幅 [photoWidth]・高さ [photoHeight] の写真で、crop の枠の一辺が取れる範囲。
({double minimum, double maximum}) squareCropSideRange({
  required int photoWidth,
  required int photoHeight,
}) {
  final shortSide = math.min(photoWidth, photoHeight).toDouble();
  return (minimum: shortSide * _minimumSquareCropSideRatio, maximum: shortSide);
}

/// crop の枠の初めの位置。写真の中央の、短辺いっぱいの正方形 (そのまま決めると写真の中央を正方形に切り取った範囲になる)。
SquareCrop initialSquareCrop({
  required int photoWidth,
  required int photoHeight,
}) {
  final side = math.min(photoWidth, photoHeight).toDouble();
  return (
    left: (photoWidth - side) / 2,
    top: (photoHeight - side) / 2,
    side: side,
  );
}

/// [crop] を、中心を [centerDelta] (写真の画素) 動かし、一辺を [scaleChange] 倍にした枠にする。
/// 一辺は [squareCropSideRange] に、位置は写真の内側に収める。
SquareCrop updateSquareCrop({
  required SquareCrop crop,
  required ({double dx, double dy}) centerDelta,
  required double scaleChange,
  required int photoWidth,
  required int photoHeight,
}) {
  final sideRange = squareCropSideRange(
    photoWidth: photoWidth,
    photoHeight: photoHeight,
  );
  final side = (crop.side * scaleChange).clamp(
    sideRange.minimum,
    sideRange.maximum,
  );
  final centerX = crop.left + crop.side / 2 + centerDelta.dx;
  final centerY = crop.top + crop.side / 2 + centerDelta.dy;
  return (
    left: (centerX - side / 2).clamp(0, photoWidth - side).toDouble(),
    top: (centerY - side / 2).clamp(0, photoHeight - side).toDouble(),
    side: side,
  );
}

/// 幅 [photoWidth]・高さ [photoHeight] の写真の、[crop] の内側を白・外側を黒にしたマスクの PNG。
Uint8List squareMaskPng({
  required int photoWidth,
  required int photoHeight,
  required SquareCrop crop,
}) {
  final mask = img.Image(width: photoWidth, height: photoHeight, numChannels: 1)
    ..clear(img.ColorUint8.rgb(0, 0, 0));
  img.fillRect(
    mask,
    x1: crop.left.round(),
    y1: crop.top.round(),
    x2: (crop.left + crop.side).round() - 1,
    y2: (crop.top + crop.side).round() - 1,
    color: img.ColorUint8.rgb(255, 255, 255),
  );
  return img.encodePng(mask);
}

/// [photo] の上の [crop] のマスクの PNG を別の isolate で作る ([MonsterGenerator.createSquareMask]。Web では同じスレッドで動く)。
Future<Uint8List> createSquareMaskInBackground({
  required Uint8List photo,
  required SquareCrop crop,
}) => compute(_squareMaskPngFromPhoto, (photo: photo, crop: crop));

Uint8List _squareMaskPngFromPhoto(({Uint8List photo, SquareCrop crop}) input) {
  final size = photoPixelSize(photo: input.photo);
  return squareMaskPng(
    photoWidth: size.width,
    photoHeight: size.height,
    crop: input.crop,
  );
}

/// [photo] に [mask] を当て、マスクの値を透明度にした PNG (プレビュー用。サーバーの切り出しと同じく、マスクは写真の大きさに引き伸ばす)。
/// 読めない形式は [FormatException] を投げる。
Uint8List cutoutPreviewPng({
  required Uint8List photo,
  required Uint8List mask,
}) {
  final decodedPhoto = img.decodeImage(photo);
  final decodedMask = img.decodeImage(mask);
  if (decodedPhoto == null || decodedMask == null) {
    throw const FormatException('写真かマスクの形式が読めません');
  }
  final resizedMask = img.copyResize(
    decodedMask,
    width: decodedPhoto.width,
    height: decodedPhoto.height,
  );
  final preview = decodedPhoto.convert(numChannels: 4);
  for (final pixel in preview) {
    pixel.a = resizedMask.getPixel(pixel.x, pixel.y).r;
  }
  return img.encodePng(preview);
}

/// [cutoutPreviewPng] を別の isolate で実行する ([MonsterGenerator.createCutoutPreview]。Web では同じスレッドで動く)。
Future<Uint8List> createCutoutPreviewInBackground({
  required Uint8List photo,
  required Uint8List mask,
}) => compute(_cutoutPreviewPngFromInput, (photo: photo, mask: mask));

Uint8List _cutoutPreviewPngFromInput(
  ({Uint8List photo, Uint8List mask}) input,
) => cutoutPreviewPng(photo: input.photo, mask: input.mask);
