import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/render_widget_png.dart';
import 'package:snapmon/features/share/share_cards.dart';
import 'package:snapmon/widgets/storage_image.dart';

import '../../card_sharer_fixture.dart';
import '../../sample_data_fixture.dart';

/// アプリが同梱する書体 (pubspec.yaml の fonts) の family とファイル。
/// テストの既定の書体は字幅が実際と違うため、はみ出しを実際の書体で確かめる。
const Map<String, List<String>> _bundledFontPaths = {
  'DelaGothicOne': ['assets/fonts/dela_gothic_one/DelaGothicOne-Regular.ttf'],
  'ZenKakuGothicNew': [
    'assets/fonts/zen_kaku_gothic_new/ZenKakuGothicNew-Regular.ttf',
    'assets/fonts/zen_kaku_gothic_new/ZenKakuGothicNew-Bold.ttf',
  ],
};

/// PNG の [pngBytes] の画素の幅と高さ (IHDR に書かれた値)。
(int, int) _pngSize({required Uint8List pngBytes}) {
  final byteData = ByteData.sublistView(pngBytes);
  return (byteData.getUint32(16), byteData.getUint32(20));
}

void main() {
  final sampleData = loadSampleDataFixture();
  const artPath = 'monsters/sample-mugmon/art.png';
  const sourcePhotoReference = 'users/uid-1/photos/original-photo';

  /// 切り出した画像と元の写真を持つ 1 体。
  final monsterWithArt = ownedMonsterWithArt(
    monster: sampleData.monsterById(monsterId: 'sample-mugmon'),
    artPath: artPath,
    sourcePhotoReference: sourcePhotoReference,
  );

  /// [format] の [card] を、論理の大きさの枠に入れて開く。
  Future<void> pumpCard({
    required WidgetTester tester,
    required Widget card,
    required ShareCardFormat format,
  }) async {
    tester.view
      ..physicalSize = const Size(800, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox.fromSize(size: format.logicalSize, child: card),
        ),
      ),
    );
  }

  /// 描いたカードの絵が、Storage から読む部品を使わず、渡した切り出した画像 [artImage] だけであることを確かめる。
  void expectOnlyArtImage({
    required WidgetTester tester,
    required ui.Image artImage,
  }) {
    expect(find.byType(StorageImage), findsNothing);
    final rawImages = find.byType(RawImage);
    expect(rawImages, findsOneWidget);
    expect(tester.widget<RawImage>(rawImages).image, same(artImage));
  }

  /// 8×8 の切り出した画像の代わり。テストの終わりに dispose する。
  Future<ui.Image> createArtImage({required WidgetTester tester}) async {
    final artImage = (await tester.runAsync(
      () => createTestImage(width: 8, height: 8),
    ))!;
    addTearDown(artImage.dispose);
    return artImage;
  }

  group('カードに元の写真を描かない', () {
    for (final format in ShareCardFormat.values) {
      testWidgets('図鑑のカード (${format.name})', (tester) async {
        final artImage = await createArtImage(tester: tester);
        await pumpCard(
          tester: tester,
          card: MonsterShareCard(
            monster: monsterWithArt,
            artImagesByPath: {artPath: artImage},
            definitions: sampleData.definitions,
            format: format,
          ),
          format: format,
        );
        expectOnlyArtImage(tester: tester, artImage: artImage);
        expect(find.textContaining(sourcePhotoReference), findsNothing);
      });

      testWidgets('バトルの結果のカード (${format.name})', (tester) async {
        final artImage = await createArtImage(tester: tester);
        await pumpCard(
          tester: tester,
          card: BattleResultShareCard(
            winner: BattleSideId.player,
            playerParty: [monsterWithArt],
            appliedLevels: {monsterWithArt.definition.id: 8},
            opponentParty: [
              sampleData.monsterById(monsterId: 'sample-ringora'),
            ],
            artImagesByPath: {artPath: artImage},
            definitions: sampleData.definitions,
            format: format,
          ),
          format: format,
        );
        expectOnlyArtImage(tester: tester, artImage: artImage);
        expect(find.textContaining(sourcePhotoReference), findsNothing);
        expect(find.text('Lv. 7 → 8'), findsOneWidget);
      });
    }
  });

  group('カードを PNG にする', () {
    setUpAll(() async {
      for (final entry in _bundledFontPaths.entries) {
        final fontLoader = FontLoader(entry.key);
        for (final path in entry.value) {
          fontLoader.addFont(
            Future.value(ByteData.sublistView(File(path).readAsBytesSync())),
          );
        }
        await fontLoader.load();
      }
    });

    /// 見本のモンスターのうち名前の長い 3 体 (はみ出しやすい手持ち)。
    List<OwnedMonster> longestNamedMonsters() =>
        ([...sampleData.monsters]..sort(
              (first, second) => second.definition.name.length.compareTo(
                first.definition.name.length,
              ),
            ))
            .take(3)
            .toList();

    for (final format in ShareCardFormat.values) {
      final expectedSize = (
        (format.logicalSize.width * format.pixelRatio).round(),
        (format.logicalSize.height * format.pixelRatio).round(),
      );

      testWidgets(
        '図鑑のカードが ${expectedSize.$1}×${expectedSize.$2} の PNG になり、はみ出さない',
        (tester) async {
          final pngBytes = await tester.runAsync(
            () => renderWidgetToPng(
              view: tester.view,
              card: MonsterShareCard(
                monster: longestNamedMonsters().first,
                artImagesByPath: const {},
                definitions: sampleData.definitions,
                format: format,
              ),
              format: format,
            ),
          );
          expect(_pngSize(pngBytes: pngBytes!), expectedSize);
          // はみ出しは RenderFlex のエラーとして報告されるため、例外が無いことで確かめる
          expect(tester.takeException(), isNull);
        },
      );

      for (final winner in BattleSideId.values) {
        testWidgets(
          'バトルの結果のカード (${winner.name}) が ${expectedSize.$1}×${expectedSize.$2} の PNG になり、はみ出さない',
          (tester) async {
            final playerParty = longestNamedMonsters();
            final pngBytes = await tester.runAsync(
              () => renderWidgetToPng(
                view: tester.view,
                card: BattleResultShareCard(
                  winner: winner,
                  playerParty: playerParty,
                  appliedLevels: {
                    for (final monster in playerParty)
                      monster.definition.id: monster.level + 1,
                  },
                  opponentParty: playerParty,
                  artImagesByPath: const {},
                  definitions: sampleData.definitions,
                  format: format,
                ),
                format: format,
              ),
            );
            expect(_pngSize(pngBytes: pngBytes!), expectedSize);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}
