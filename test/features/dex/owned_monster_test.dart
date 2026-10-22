import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/dex/owned_monster.dart';

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
          'decoration': {'eyes': 'round'},
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
    },
  );
}
