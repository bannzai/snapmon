import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/widgets/storage_image.dart';

void main() {
  testWidgets('StorageImageLoaderScope の下では、その関数で読んだ中身を描く (Firebase を呼ばない)', (
    tester,
  ) async {
    final requestedPaths = <String>[];
    // 1 × 1 の PNG (デコードできる中身にし、画像の読み込みのエラーを出さないため)
    final imageBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
    );
    await tester.pumpWidget(
      StorageImageLoaderScope(
        loadBytes: ({required storagePath}) async {
          requestedPaths.add(storagePath);
          return imageBytes;
        },
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: StorageImage(
            storagePath: 'monsters/monster-1/art.png',
            fit: BoxFit.contain,
            placeholder: SizedBox(key: Key('placeholder')),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('placeholder')), findsOneWidget);
    await tester.pump();
    expect(requestedPaths, ['monsters/monster-1/art.png']);
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as MemoryImage).bytes, imageBytes);
  });
}
