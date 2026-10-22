import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/opponent/pvp_opponent.dart';

void main() {
  test('fetchOpponents が返す 1 件を読み、元の写真の参照は持たない', () {
    final opponent = PvpOpponent.fromJson(
      json: {
        'opponentUid': 'uid-a',
        'displayName': 'トレーナー 1111',
        'monsters': [
          {
            'definition': {
              'id': 'monster-1',
              'name': 'マグモン',
              'encyclopediaText': 'まいにち あたたかい のみものを はこぶ',
              'elementTypeIds': ['heat'],
              'learnset': [
                {'moveId': 'heat_1', 'unlockLevel': 1},
              ],
              'baseStats': {
                'hitPoints': 50,
                'attack': 50,
                'defense': 50,
                'speed': 50,
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
            'artPath': 'monsters/monster-1/art.png',
            'definitionIds': ['definition-1'],
            'decoration': {'eyes': 'round'},
            'decorationVersion': 1,
          },
        ],
      },
    );
    expect(opponent.opponentUid, 'uid-a');
    expect(opponent.displayName, 'トレーナー 1111');
    final monster = opponent.monsters.single;
    expect(monster.definition.id, 'monster-1');
    expect(monster.definition.sourcePhotoReference, isNull);
    expect(monster.level, 7);
    expect(monster.artPath, 'monsters/monster-1/art.png');
    expect(monster.definitionIds, ['definition-1']);
  });
}
