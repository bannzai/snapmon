import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/widgets/monster_parts.dart';
import 'package:snapmon/widgets/storage_image.dart';

import '../../card_sharer_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  testWidgets('生まれたカードは元の写真を出さず、モンスターの絵を 1 枚の正方形で出す', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final loadedStoragePaths = <String>[];
    final loadedArtPaths = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        locale: const Locale('ja'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StorageImageLoaderScope(
          loadBytes: ({required storagePath}) {
            loadedStoragePaths.add(storagePath);
            return Completer<Uint8List?>().future;
          },
          child: MonsterArtImageLoaderScope(
            // 読み終わらない画像にする (widget test の偽の時間の中では画像のデコードが終わらないため)
            loadArtImage: ({required artPath}) {
              loadedArtPaths.add(artPath);
              return Completer<ui.Image>().future;
            },
            child: ResultScreen(
              monster: ownedMonsterWithArt(
                monster: sampleData.monsterById(monsterId: 'sample-mugmon'),
                artPath: 'monsters/sample-mugmon/art.png',
                sourcePhotoReference: 'users/uid-1/photos/original-photo',
              ),
              dexStore: DexStore(definitions: sampleData.definitions),
              origin: ResultScreenOrigin.newlyBorn,
              cardSharer: fakeCardSharer(
                calls: RecordedShareCalls(),
                artImage: null,
                shareResultStatus: ShareResultStatus.success,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(StorageImage), findsNothing);
    expect(loadedStoragePaths, isEmpty);
    expect(find.text('写真'), findsNothing);
    expect(find.byType(MonsterArt), findsOneWidget);
    expect(loadedArtPaths, ['monsters/sample-mugmon/art.png']);
    final artSize = tester.getSize(find.byType(MonsterArt));
    expect(artSize.width, artSize.height);
    // 画面の幅 390 から外側の余白 (左右 20) とカードの内側の余白 (左右 18) を除いた幅いっぱいに出す
    expect(artSize.width, 390 - 20 * 2 - 18 * 2);
  });
}
