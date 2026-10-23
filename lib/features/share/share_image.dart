import 'dart:typed_data';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

import 'card_sharer.dart';

/// PNG [pngBytes] を OS の共有シートに渡す ([CardSharer.shareImage] の実体)。
/// Web は Web Share API が使えればその共有シートを出し、使えなければ画像をダウンロードする (share_plus の downloadFallbackEnabled)。
Future<ShareResultStatus> shareImageWithSharePlus({
  required Uint8List pngBytes,
  required String fileName,
  required String text,
  required Rect sharePositionOrigin,
}) async => (await SharePlus.instance.share(
  ShareParams(
    files: [XFile.fromData(pngBytes, mimeType: 'image/png')],
    // XFile.fromData の名前は Web 以外で使われないため、ファイル名はこちらで渡す (share_plus の fileNameOverrides の説明)
    fileNameOverrides: [fileName],
    text: text,
    sharePositionOrigin: sharePositionOrigin,
    downloadFallbackEnabled: true,
  ),
)).status;
