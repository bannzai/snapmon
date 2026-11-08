import 'dart:collection';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Storage の画像 1 つの大きさの上限。firebase_storage の getData の既定 (10 MB) に合わせた。
const int storageImageMaximumBytes = 10 * 1024 * 1024;

/// Storage の [storagePath] の画像の中身を読む関数。読めない時は null を返すか throw する。
typedef ReadStorageImageBytes =
    Future<Uint8List?> Function({required String storagePath});

/// 一度読んだ Storage の画像の中身を、パスごとにこの起動の間だけ持つインメモリのキャッシュ。
/// 同じ画像を画面を開くたびに Storage から読み直さないため (Storage のダウンロードの数を減らす。#234)。
/// パスで持ってよいのは、Storage の画像のパスが中身の変わらないものだけのため
/// (`monsters/{monsterId}/art.png` は saved の後に作り直さず、アイコンは `users/{uid}/icons/{uploadId}.png` と登録のたびに別のパス)。
/// 読んでいる途中の同じパスの要求は 1 つの読み込みにまとめ、読めなかった (throw した・null だった) パスは残さず次の要求で読み直す
/// (一時的な失敗でその起動の間ずっと描けないのを避けるため)。
/// 状態 (持っている中身と読んでいる途中の Future) を持つため関数ではなく class にし、テストは別の instance で行う。
class StorageImageBytesCache {
  /// 合計 [maximumTotalBytes] バイトまで持つキャッシュを作る。
  StorageImageBytesCache({required this.maximumTotalBytes});

  /// 持つ中身の合計の上限。超える時は使われていない順に捨てる。上限より大きい 1 つの中身は持たない。
  final int maximumTotalBytes;

  /// 読み終えた中身。使った順 (末尾が最近) に並ぶ。
  final LinkedHashMap<String, Uint8List> _bytesByPath = LinkedHashMap();

  /// 読んでいる途中の読み込み。
  final Map<String, Future<Uint8List?>> _inFlightByPath = {};

  /// 持っている中身の合計のバイト数。
  int get totalBytes =>
      _bytesByPath.values.fold(0, (sum, bytes) => sum + bytes.length);

  /// [storagePath] の中身を、持っていればそれを、無ければ [read] で読んで返す。読めない時は [read] のとおり null を返すか throw する。
  Future<Uint8List?> read({
    required String storagePath,
    required ReadStorageImageBytes read,
  }) {
    final cachedBytes = _bytesByPath.remove(storagePath);
    if (cachedBytes != null) {
      _bytesByPath[storagePath] = cachedBytes;
      return Future.value(cachedBytes);
    }
    return _inFlightByPath[storagePath] ??= () async {
      try {
        final bytes = await read(storagePath: storagePath);
        if (bytes != null) {
          _store(storagePath: storagePath, bytes: bytes);
        }
        return bytes;
      } finally {
        _inFlightByPath.remove(storagePath);
      }
    }();
  }

  /// [bytes] を [storagePath] の中身として持つ。合計が上限を超える分は使われていない順に捨てる。
  void _store({required String storagePath, required Uint8List bytes}) {
    if (bytes.length > maximumTotalBytes) {
      return;
    }
    _bytesByPath.remove(storagePath);
    while (_bytesByPath.isNotEmpty &&
        totalBytes + bytes.length > maximumTotalBytes) {
      _bytesByPath.remove(_bytesByPath.keys.first);
    }
    _bytesByPath[storagePath] = bytes;
  }
}

/// アプリ全体で共有する Storage の画像のキャッシュ。
/// 合計 50 MB: Flutter の ImageCache の既定 (100 MB) より小さくした。持つのはエンコード済みの PNG で、デコード後の画像は読んだ側が別に持つため。
final StorageImageBytesCache storageImageBytesCache = StorageImageBytesCache(
  maximumTotalBytes: 50 * 1024 * 1024,
);

/// Storage の [storagePath] の画像の中身を [storageImageBytesCache] を通して読む。
/// 持っていなければ Firebase の Storage から読む (読むたびに Storage の Rules を通す)。読めない時は null を返すか throw する。
Future<Uint8List?> readStorageImageBytesWithFirebase({
  required String storagePath,
}) => storageImageBytesCache.read(
  storagePath: storagePath,
  read: ({required storagePath}) => FirebaseStorage.instance
      .ref(storagePath)
      .getData(storageImageMaximumBytes),
);
