import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

/// 生成に送る写真の長辺の上限 (px)。issue #14 の「長辺 1024px」。Claude の画像の推奨の大きさ (長辺 1568px 以下) に収まり、
/// 1 枚の JPEG が Storage の Rules の上限 (4 MB) より十分小さくなる。
const int generationPhotoLongestSide = 1024;

/// 生成に送る JPEG の品質。85: 長辺 1024px の写真で数百 KB に収まり、被写体の切り出しの輪郭が崩れない値として置いた。
const int _generationPhotoJpegQuality = 85;

/// [sourceBytes] (端末の写真の JPEG・PNG 等) を、生成に送る写真 (向きを画素に反映した長辺 [generationPhotoLongestSide] 以下の JPEG) にする。
/// 長辺が上限以下の写真は縮小せず、JPEG に変えるだけ。読めない形式 (HEIC 等) は [FormatException] を投げる。
Uint8List prepareGenerationPhoto({required Uint8List sourceBytes}) {
  final decoded = img.decodeImage(sourceBytes);
  if (decoded == null) {
    throw const FormatException('この写真の形式は読めません');
  }
  final oriented = img.bakeOrientation(decoded);
  return img.encodeJpg(
    oriented.width > generationPhotoLongestSide ||
            oriented.height > generationPhotoLongestSide
        ? img.copyResize(
            oriented,
            width: oriented.width >= oriented.height
                ? generationPhotoLongestSide
                : null,
            height: oriented.width < oriented.height
                ? generationPhotoLongestSide
                : null,
            interpolation: img.Interpolation.average,
          )
        : oriented,
    quality: _generationPhotoJpegQuality,
  );
}

/// [prepareGenerationPhoto] を別の isolate で実行する (縮小の間に画面を止めないため。Web では同じスレッドで動く)。
Future<Uint8List> prepareGenerationPhotoInBackground({
  required Uint8List sourceBytes,
}) => compute(_prepareGenerationPhotoFromBytes, sourceBytes);

Uint8List _prepareGenerationPhotoFromBytes(Uint8List sourceBytes) =>
    prepareGenerationPhoto(sourceBytes: sourceBytes);

/// 端末のアルバムから写真を 1 枚選んでもらい、その中身を返す。選ばずに閉じた時は null。
/// 縮小の上限と品質を渡し、端末で縮小させる (大きな写真を読み込む量を減らすため)。
/// 返った形式を [prepareGenerationPhoto] が読めない時 (HEIC のまま返った等) は、そちらの [FormatException] を画面に出す。
Future<Uint8List?> pickAlbumPhoto() async {
  final file = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: generationPhotoLongestSide.toDouble(),
    maxHeight: generationPhotoLongestSide.toDouble(),
    imageQuality: _generationPhotoJpegQuality,
    requestFullMetadata: false,
  );
  return file?.readAsBytes();
}
