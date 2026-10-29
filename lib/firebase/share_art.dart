import 'dart:ui' as ui;

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';

import '../features/dex/owned_monster.dart';

/// 写真から切り出した被写体の画像の大きさの上限。firebase_storage の getData の既定 (10 MB) に合わせた。
const int _artImageMaximumBytes = 10 * 1024 * 1024;

/// 写真から切り出した被写体の画像 [artPath] を読んでデコードする (CardSharer.loadArtImage の実体)。
/// 見本の画像 ([isBundledArtPath]) は同梱の asset から、それ以外は Storage から読む。
/// 読めない時は throw する。
Future<ui.Image> loadArtImageWithFirebase({required String artPath}) async {
  final bytes = isBundledArtPath(artPath: artPath)
      ? (await rootBundle.load(artPath)).buffer.asUint8List()
      : await FirebaseStorage.instance
            .ref(artPath)
            .getData(_artImageMaximumBytes);
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
