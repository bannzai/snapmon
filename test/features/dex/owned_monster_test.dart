import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/monster/monster_decoration.dart';
import 'package:snapmon/features/dex/owned_monster.dart';

/// functions の `MonsterDecoration` の形の装飾。割合の端の値は Firestore に整数として入るため、[eyeCenterX] を整数の 1 にした。
const Map<String, dynamic> decorationJson = {
  'eyeStyle': 'sparkle',
  'mouthStyle': 'fang',
  'limbStyle': 'wings',
  'auraStyle': 'flame',
  'eyeCenterX': 1,
  'eyeCenterY': 0.35,
  'eyeScale': 0.2,
  'outlineColorHex': '#1A2B3C',
};

void main() {
  test(
    'Firestore の users/{uid}/monsters のドキュメント (MonsterDocument) から 1 体を読む',
    () {
      final monster = OwnedMonster.fromJson(
        json: {
          'definition': {
            'id': 'm1',
            'sourcePhotoReference': 'users/uid-1/photos/request-1',
            'name': 'マグモン',
            'encyclopediaText': '朝のコーヒーの熱をためこむ',
            'elementTypeIds': ['metal', 'dynamic-wax'],
            'learnset': [
              {'moveId': 'metal_1', 'unlockLevel': 1},
            ],
            'baseStats': {
              'hitPoints': 80,
              'attack': 80,
              'defense': 80,
              'speed': 80,
            },
            'individualValues': {
              'hitPoints': 1,
              'attack': 2,
              'defense': 3,
              'speed': 4,
            },
            'statCalculationVersion': 1,
            'masterVersion': 1,
          },
          'level': 7,
          'experience': 6,
          'artPath': 'monsters/m1/art.png',
          'decoration': decorationJson,
          'decorationVersion': 1,
          'definitionIds': ['definition-wax'],
          'generationRequestId': 'request-1',
        },
      );
      expect(monster.definition.id, 'm1');
      expect(
        monster.definition.sourcePhotoReference,
        'users/uid-1/photos/request-1',
      );
      expect(monster.level, 7);
      expect(monster.artPath, 'monsters/m1/art.png');
      expect(monster.definitionIds, ['definition-wax']);
      final decoration = monster.decoration!;
      expect(monster.decorationVersion, 1);
      expect(decoration.eyeStyle, MonsterEyeStyle.sparkle);
      expect(decoration.mouthStyle, MonsterMouthStyle.fang);
      expect(decoration.limbStyle, MonsterLimbStyle.wings);
      expect(decoration.auraStyle, MonsterAuraStyle.flame);
      expect(decoration.eyeCenterX, 1.0);
      expect(decoration.eyeCenterY, 0.35);
      expect(decoration.eyeScale, 0.2);
      expect(decoration.outlineColorHex, '#1A2B3C');
    },
  );

  group('装飾を読まない', () {
    Map<String, dynamic> monsterJson({
      required Map<String, dynamic>? decoration,
      required int? decorationVersion,
    }) => {
      'definition': {
        'id': 'm1',
        'name': 'マグモン',
        'encyclopediaText': '朝のコーヒーの熱をためこむ',
        'elementTypeIds': ['metal'],
        'learnset': [
          {'moveId': 'metal_1', 'unlockLevel': 1},
        ],
        'baseStats': {
          'hitPoints': 80,
          'attack': 80,
          'defense': 80,
          'speed': 80,
        },
        'individualValues': {
          'hitPoints': 1,
          'attack': 2,
          'defense': 3,
          'speed': 4,
        },
        'statCalculationVersion': 1,
        'masterVersion': 1,
      },
      'level': 1,
      'artPath': 'monsters/m1/art.png',
      'definitionIds': <String>[],
      'decoration': ?decoration,
      'decorationVersion': ?decorationVersion,
    };

    test('このクライアントが描けない版 (新しい版) の装飾は、形が違っても読まない', () {
      final monster = OwnedMonster.fromJson(
        json: monsterJson(
          decoration: {'eyeStyle': 'unknown-style'},
          decorationVersion: 2,
        ),
      );
      expect(monster.decoration, isNull);
      expect(monster.decorationVersion, 2);
    });

    test('描ける版でも形の違う装飾は、モンスターごと読めなくせず装飾無しで読む', () {
      final monster = OwnedMonster.fromJson(
        json: monsterJson(
          decoration: {'eyeStyle': 'unknown-style'},
          decorationVersion: 1,
        ),
      );
      expect(monster.decoration, isNull);
      expect(monster.decorationVersion, 1);
      expect(monster.artPath, 'monsters/m1/art.png');
    });

    test('装飾を持たないドキュメントは装飾無しで読む', () {
      final monster = OwnedMonster.fromJson(
        json: monsterJson(decoration: null, decorationVersion: null),
      );
      expect(monster.decoration, isNull);
      expect(monster.decorationVersion, isNull);
    });
  });
}
