import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:snapmon/features/capture/subject_mask.dart';

void main() {
  /// 幅 [width]・高さ [height] の赤い写真の JPEG。
  Uint8List redPhoto({required int width, required int height}) =>
      img.encodeJpg(
        img.Image(width: width, height: height)
          ..clear(img.ColorUint8.rgb(255, 0, 0)),
      );

  test('photoPixelSize は写真の画素の大きさを返し、読めない形式は FormatException にする', () {
    expect(photoPixelSize(photo: redPhoto(width: 40, height: 30)), (
      width: 40,
      height: 30,
    ));
    expect(
      () => photoPixelSize(photo: Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });

  test('initialSquareCrop は写真の中央の短辺いっぱいの正方形にする', () {
    expect(initialSquareCrop(photoWidth: 400, photoHeight: 300), (
      left: 50.0,
      top: 0.0,
      side: 300.0,
    ));
    expect(initialSquareCrop(photoWidth: 300, photoHeight: 400), (
      left: 0.0,
      top: 50.0,
      side: 300.0,
    ));
  });

  group('updateSquareCrop', () {
    test('中心を動かし、写真の外にはみ出さないよう止める', () {
      const crop = (left: 50.0, top: 50.0, side: 100.0);
      expect(
        updateSquareCrop(
          crop: crop,
          centerDelta: (dx: 30, dy: -10),
          scaleChange: 1,
          photoWidth: 400,
          photoHeight: 300,
        ),
        (left: 80.0, top: 40.0, side: 100.0),
      );
      expect(
        updateSquareCrop(
          crop: crop,
          centerDelta: (dx: 1000, dy: -1000),
          scaleChange: 1,
          photoWidth: 400,
          photoHeight: 300,
        ),
        (left: 300.0, top: 0.0, side: 100.0),
      );
    });

    test('大きさは中心を保って変え、短辺の 20% から短辺までに収める', () {
      const crop = (left: 100.0, top: 100.0, side: 100.0);
      expect(
        updateSquareCrop(
          crop: crop,
          centerDelta: (dx: 0, dy: 0),
          scaleChange: 0.5,
          photoWidth: 400,
          photoHeight: 300,
        ),
        (left: 125.0, top: 125.0, side: 50.0),
      );
      expect(
        updateSquareCrop(
          crop: crop,
          centerDelta: (dx: 0, dy: 0),
          scaleChange: 0.1,
          photoWidth: 400,
          photoHeight: 300,
        ).side,
        60,
      );
      expect(
        updateSquareCrop(
          crop: crop,
          centerDelta: (dx: 0, dy: 0),
          scaleChange: 10,
          photoWidth: 400,
          photoHeight: 300,
        ),
        (left: 0.0, top: 0.0, side: 300.0),
      );
    });
  });

  test('squareMaskPng は写真と同じ大きさで、枠の内側だけを白にする', () {
    final mask = img.decodePng(
      squareMaskPng(
        photoWidth: 40,
        photoHeight: 30,
        crop: (left: 10, top: 5, side: 20),
      ),
    )!;
    expect((mask.width, mask.height), (40, 30));
    expect(mask.getPixel(10, 5).r, 255);
    expect(mask.getPixel(29, 24).r, 255);
    expect(mask.getPixel(9, 5).r, 0);
    expect(mask.getPixel(30, 24).r, 0);
    expect(mask.getPixel(10, 25).r, 0);
  });

  test('cutoutPreviewPng はマスクの値を透明度にし、写真の色を残す', () {
    final preview = img.decodePng(
      cutoutPreviewPng(
        photo: redPhoto(width: 40, height: 30),
        mask: squareMaskPng(
          photoWidth: 40,
          photoHeight: 30,
          crop: (left: 10, top: 5, side: 20),
        ),
      ),
    )!;
    expect((preview.width, preview.height), (40, 30));
    expect(preview.getPixel(20, 15).a, 255);
    expect(preview.getPixel(20, 15).r, greaterThan(200));
    expect(preview.getPixel(0, 0).a, 0);
  });
}
