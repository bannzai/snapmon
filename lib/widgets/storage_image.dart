import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

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
  late Future<Uint8List?> _imageBytes = _load();

  Future<Uint8List?> _load() =>
      FirebaseStorage.instance.ref(widget.storagePath).getData();

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
