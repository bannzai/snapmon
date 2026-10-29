import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/widgets/monster_parts.dart';

import '../card_sharer_fixture.dart';
import '../sample_data_fixture.dart';

void main() {
  testWidgets(
    'MonsterArtImageLoaderScope の下では、その関数で読んだ切り出した画像を描く (Firebase を呼ばない)',
    (tester) async {
      final sampleData = loadSampleDataFixture();
      const artPath = 'monsters/sample-mugmon/art.png';
      final artImage = (await tester.runAsync(
        () => createTestImage(width: 8, height: 8),
      ))!;
      addTearDown(artImage.dispose);
      final requestedArtPaths = <String>[];
      await tester.pumpWidget(
        MonsterArtImageLoaderScope(
          // MonsterArt は受け取った画像を外す時に dispose するため、複製を返す
          loadArtImage: ({required artPath}) async {
            requestedArtPaths.add(artPath);
            return artImage.clone();
          },
          child: MaterialApp(
            home: MonsterArt(
              monster: ownedMonsterWithArt(
                monster: sampleData.monsterById(monsterId: 'sample-mugmon'),
                artPath: artPath,
                sourcePhotoReference: 'users/uid-1/photos/original-photo',
              ),
              backgroundColor: Colors.black,
            ),
          ),
        ),
      );
      await tester.pump();
      expect(requestedArtPaths, [artPath]);
      expect(
        tester
            .widget<MonsterArtImage>(find.byType(MonsterArtImage))
            .artImage
            .isCloneOf(artImage),
        isTrue,
      );
    },
  );
}
