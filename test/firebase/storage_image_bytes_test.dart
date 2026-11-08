import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/firebase/storage_image_bytes.dart';

/// 長さ [length] で中身がすべて [fill] のバイト列。
Uint8List bytesOf({required int length, required int fill}) =>
    Uint8List.fromList(List.filled(length, fill));

void main() {
  group('StorageImageBytesCache', () {
    test('同じパスの 2 回目は読まずに持っている中身を返す', () async {
      final cache = StorageImageBytesCache(maximumTotalBytes: 1024);
      final readPaths = <String>[];
      Future<Uint8List?> read({required String storagePath}) async {
        readPaths.add(storagePath);
        return bytesOf(length: 4, fill: 1);
      }

      final first = await cache.read(
        storagePath: 'monsters/a/art.png',
        read: read,
      );
      final second = await cache.read(
        storagePath: 'monsters/a/art.png',
        read: read,
      );
      expect(readPaths, ['monsters/a/art.png']);
      expect(second, same(first));
    });

    test('別のパスはそれぞれ読む', () async {
      final cache = StorageImageBytesCache(maximumTotalBytes: 1024);
      final readPaths = <String>[];
      Future<Uint8List?> read({required String storagePath}) async {
        readPaths.add(storagePath);
        return bytesOf(length: 4, fill: 1);
      }

      await cache.read(storagePath: 'monsters/a/art.png', read: read);
      await cache.read(storagePath: 'monsters/b/art.png', read: read);
      expect(readPaths, ['monsters/a/art.png', 'monsters/b/art.png']);
    });

    test('読んでいる途中の同じパスの要求は 1 つの読み込みにまとめる', () async {
      final cache = StorageImageBytesCache(maximumTotalBytes: 1024);
      final completer = Completer<Uint8List?>();
      var readCount = 0;
      Future<Uint8List?> read({required String storagePath}) {
        readCount += 1;
        return completer.future;
      }

      final first = cache.read(storagePath: 'monsters/a/art.png', read: read);
      final second = cache.read(storagePath: 'monsters/a/art.png', read: read);
      completer.complete(bytesOf(length: 4, fill: 1));
      expect(await first, await second);
      expect(readCount, 1);
    });

    test('throw した読み込みは残さず、次の要求で読み直す', () async {
      final cache = StorageImageBytesCache(maximumTotalBytes: 1024);
      var readCount = 0;
      Future<Uint8List?> read({required String storagePath}) async {
        readCount += 1;
        if (readCount == 1) {
          throw StateError('一時的な失敗');
        }
        return bytesOf(length: 4, fill: 1);
      }

      await expectLater(
        cache.read(storagePath: 'monsters/a/art.png', read: read),
        throwsStateError,
      );
      expect(
        await cache.read(storagePath: 'monsters/a/art.png', read: read),
        isNotNull,
      );
      expect(readCount, 2);
    });

    test('null だった読み込みは残さず、次の要求で読み直す', () async {
      final cache = StorageImageBytesCache(maximumTotalBytes: 1024);
      var readCount = 0;
      Future<Uint8List?> read({required String storagePath}) async {
        readCount += 1;
        return readCount == 1 ? null : bytesOf(length: 4, fill: 1);
      }

      expect(
        await cache.read(storagePath: 'monsters/a/art.png', read: read),
        isNull,
      );
      expect(
        await cache.read(storagePath: 'monsters/a/art.png', read: read),
        isNotNull,
      );
      expect(readCount, 2);
    });

    test('合計が上限を超えると、使われていない順に捨てる (読んだ・当たった順で最近が残る)', () async {
      final cache = StorageImageBytesCache(maximumTotalBytes: 10);
      final readPaths = <String>[];
      Future<Uint8List?> read({required String storagePath}) async {
        readPaths.add(storagePath);
        return bytesOf(length: 4, fill: storagePath.codeUnitAt(0));
      }

      await cache.read(storagePath: 'a', read: read);
      await cache.read(storagePath: 'b', read: read);
      // a に当たって a を最近にする
      await cache.read(storagePath: 'a', read: read);
      // c を足すと 12 > 10 になり、使われていない b を捨てる
      await cache.read(storagePath: 'c', read: read);
      expect(cache.totalBytes, 8);
      readPaths.clear();
      await cache.read(storagePath: 'a', read: read);
      await cache.read(storagePath: 'c', read: read);
      expect(readPaths, isEmpty);
      await cache.read(storagePath: 'b', read: read);
      expect(readPaths, ['b']);
    });

    test('上限より大きい 1 つの中身は持たず、持っている中身も捨てない', () async {
      final cache = StorageImageBytesCache(maximumTotalBytes: 10);
      final readPaths = <String>[];
      Future<Uint8List?> read({required String storagePath}) async {
        readPaths.add(storagePath);
        return bytesOf(length: storagePath == 'large' ? 11 : 4, fill: 1);
      }

      await cache.read(storagePath: 'small', read: read);
      await cache.read(storagePath: 'large', read: read);
      await cache.read(storagePath: 'large', read: read);
      expect(readPaths, ['small', 'large', 'large']);
      expect(cache.totalBytes, 4);
      await cache.read(storagePath: 'small', read: read);
      expect(readPaths, ['small', 'large', 'large']);
    });

    test('上限ちょうどの中身は持つ', () async {
      final cache = StorageImageBytesCache(maximumTotalBytes: 10);
      var readCount = 0;
      Future<Uint8List?> read({required String storagePath}) async {
        readCount += 1;
        return bytesOf(length: 10, fill: 1);
      }

      await cache.read(storagePath: 'exact', read: read);
      await cache.read(storagePath: 'exact', read: read);
      expect(readCount, 1);
      expect(cache.totalBytes, 10);
    });
  });
}
