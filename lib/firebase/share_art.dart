import 'dart:ui' as ui;

import 'package:firebase_storage/firebase_storage.dart';

/// 写真から切り出した被写体の画像の大きさの上限。firebase_storage の getData の既定 (10 MB) に合わせた。
const int _artImageMaximumBytes = 10 * 1024 * 1024;

/// 写真から切り出した被写体の画像を Storage の [storagePath] から読んでデコードする (CardSharer.loadArtImage の実体)。
/// 読めない時は throw する。
Future<ui.Image> loadArtImageWithFirebase({required String storagePath}) async {
  final bytes = await FirebaseStorage.instance
      .ref(storagePath)
      .getData(_artImageMaximumBytes);
  if (bytes == null) {
    throw StateError('$storagePath の画像を読めませんでした');
  }
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    return (await codec.getNextFrame()).image;
  } finally {
    codec.dispose();
  }
}
