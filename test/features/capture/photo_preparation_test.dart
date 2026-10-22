import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:snapmon/features/capture/photo_preparation.dart';

void main() {
  Uint8List pngOf({required int width, required int height}) =>
      img.encodePng(img.Image(width: width, height: height));

  test('長辺が上限を超える横長の写真は、長辺を上限にして縦横比を保った JPEG にする', () {
    final prepared = prepareGenerationPhoto(
      sourceBytes: pngOf(width: 3000, height: 2000),
    );
    final decoded = img.decodeJpg(prepared)!;
    expect(decoded.width, generationPhotoLongestSide);
    expect(decoded.height, 683);
  });

  test('長辺が上限を超える縦長の写真は、高さを上限にする', () {
    final decoded = img.decodeJpg(
      prepareGenerationPhoto(sourceBytes: pngOf(width: 1500, height: 3000)),
    )!;
    expect(decoded.height, generationPhotoLongestSide);
    expect(decoded.width, 512);
  });

  test('長辺が上限以下の写真は縮小せず JPEG に変える', () {
    final decoded = img.decodeJpg(
      prepareGenerationPhoto(sourceBytes: pngOf(width: 640, height: 480)),
    )!;
    expect((decoded.width, decoded.height), (640, 480));
  });

  test('EXIF の向きを画素に反映する', () {
    final rotated = img.Image(width: 2000, height: 1000)
      ..exif.imageIfd.orientation = 6;
    final decoded = img.decodeJpg(
      prepareGenerationPhoto(sourceBytes: img.encodeJpg(rotated)),
    )!;
    expect((decoded.width, decoded.height), (512, 1024));
  });

  test('画像として読めない中身は FormatException を投げる', () {
    expect(
      () => prepareGenerationPhoto(sourceBytes: Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
