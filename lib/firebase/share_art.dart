import 'dart:ui' as ui;

import 'package:flutter/services.dart';

import '../features/dex/owned_monster.dart';
import 'storage_image_bytes.dart';

/// 写真から切り出した被写体の画像 [artPath] を読んでデコードする (CardSharer.loadArtImage の実体)。
/// 見本の画像 ([isBundledArtPath]) は同梱の asset から、それ以外は Storage から読む
/// ([readStorageImageBytesWithFirebase]。一度読んだ中身は [storageImageBytesCache] が持ち、同じパスは読み直さない)。
/// 読めない時は throw する。
Future<ui.Image> loadArtImageWithFirebase({required String artPath}) async {
  final bytes = isBundledArtPath(artPath: artPath)
      ? (await rootBundle.load(artPath)).buffer.asUint8List()
      : await readStorageImageBytesWithFirebase(storagePath: artPath);
  if (bytes == null) {
    throw StateError('$artPath の画像を読めませんでした');
  }
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
