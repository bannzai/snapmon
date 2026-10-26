import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Storage の [storagePath] の画像の中身を読む関数。読めない時は null を返すか throw する。
typedef LoadStorageImageBytes =
    Future<Uint8List?> Function({required String storagePath});

/// 子の木の [StorageImage] が画像を読む関数を差し替える。無い時は Firebase の Storage から読む。
/// ストアのスクリーンショットの生成 (store_screenshots/) が、見本の写真と切り出した絵を Firebase を通さずに描くために使う。
class StorageImageLoaderScope extends InheritedWidget {
  /// [loadBytes] で読む範囲を作る。
  const StorageImageLoaderScope({
    super.key,
    required this.loadBytes,
    required super.child,
  });

  /// 画像の中身を読む関数。
  final LoadStorageImageBytes loadBytes;

  @override
  bool updateShouldNotify(StorageImageLoaderScope oldWidget) =>
      loadBytes != oldWidget.loadBytes;
}

/// Cloud Storage の [storagePath] の画像を描く。読む前と読めなかった時は [placeholder] を描く。
/// URL ではなく中身を SDK で読む (読むたびに Storage の Rules を通し、元の写真を本人以外に見せないため)。
class StorageImage extends StatefulWidget {
  /// Storage の画像を作る。
  const StorageImage({
    super.key,
    required this.storagePath,
    required this.fit,
    required this.placeholder,
  });

  /// 画像の Storage のパス。
  final String storagePath;

  /// 枠への収め方。
  final BoxFit fit;

  /// 読む前と読めなかった時に描くもの。
  final Widget placeholder;

  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
  // 最初の build で読み始める (読む関数を上の StorageImageLoaderScope から引くため、initState では読まない)
  late Future<Uint8List?> _imageBytes = _load();

  /// [StorageImage.storagePath] の画像の中身を読む。上に [StorageImageLoaderScope] があればその関数で、無ければ Storage から読む。
  Future<Uint8List?> _load() {
    final loadBytes = context
        .getInheritedWidgetOfExactType<StorageImageLoaderScope>()
        ?.loadBytes;
    return loadBytes == null
        ? FirebaseStorage.instance.ref(widget.storagePath).getData()
        : loadBytes(storagePath: widget.storagePath);
  }

  @override
  void didUpdateWidget(StorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.storagePath != widget.storagePath) {
      _imageBytes = _load();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _imageBytes,
    builder: (context, snapshot) {
      final bytes = snapshot.data;
      if (snapshot.hasError) {
        debugPrint('${widget.storagePath}: ${snapshot.error}');
      }
      return bytes == null
          ? widget.placeholder
          : Image.memory(bytes, fit: widget.fit, gaplessPlayback: true);
    },
  );
}
