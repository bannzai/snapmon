import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/master/master_repository.dart';

import '../monster_generator_fixture.dart';

void main() {
  final masterJson =
      jsonDecode(File('assets/master/master.json').readAsStringSync())
          as Map<String, dynamic>;

  test('master にその場で作った定義の属性と技を足す', () {
    final definitions = buildDexDefinitions(
      latestMasterJson: masterJson,
      definitionJsons: [waxDefinitionJson],
    );
    expect(
      definitions.elementTypes.map((elementType) => elementType.id),
      contains('dynamic-wax'),
    );
    expect(definitions.moveById(moveId: 'dynamic-wax-1').displayName, 'ろうアタック');
    expect(definitions.moveById(moveId: 'steel_1').displayName, isNotEmpty);
  });

  test('同じ ID の定義は master を優先する', () {
    final masterSteelMove = buildDexDefinitions(
      latestMasterJson: masterJson,
      definitionJsons: const [],
    ).moveById(moveId: 'steel_1');
    final definitions = buildDexDefinitions(
      latestMasterJson: masterJson,
      definitionJsons: [
        {
          'version': 1,
          'elementTypes': const [],
          'moves': [
            {
              ...(waxDefinitionJson['moves'] as List).first
                  as Map<String, dynamic>,
              'id': 'steel_1',
              'displayName': '上書きしようとした技',
            },
          ],
        },
      ],
    );
    expect(
      definitions.moveById(moveId: 'steel_1').displayName,
      masterSteelMove.displayName,
    );
  });

  test('まだ読んでいない時と、読んだ版より新しい版で生まれたモンスターがいる時だけ master を読み直す', () {
    // generatedWaxMonster は master の版 1 で生まれたモンスター
    final monsters = [generatedWaxMonster(monsterId: 'm1')];
    expect(
      needsLatestMasterFetch(cachedMasterJson: null, monsters: monsters),
      isTrue,
    );
    expect(
      needsLatestMasterFetch(
        cachedMasterJson: const {'version': 1},
        monsters: monsters,
      ),
      isFalse,
    );
    expect(
      needsLatestMasterFetch(
        cachedMasterJson: const {'version': 0},
        monsters: monsters,
      ),
      isTrue,
    );
  });

  test('読んだ版に無い技を Action Card で覚えさせたモンスターがいる時は master を読み直す', () {
    final monster = generatedWaxMonster(monsterId: 'm1');
    final taughtMonster = OwnedMonster(
      definition: monster.definition,
      level: monster.level,
      actionCardMoveIds: const ['water_3'],
      artPath: monster.artPath,
      definitionIds: monster.definitionIds,
      decoration: monster.decoration,
      decorationVersion: monster.decorationVersion,
    );
    expect(
      needsLatestMasterFetch(
        cachedMasterJson: const {
          'version': 1,
          'moves': [
            {'id': 'fire_1'},
          ],
        },
        monsters: [taughtMonster],
      ),
      isTrue,
    );
    expect(
      needsLatestMasterFetch(
        cachedMasterJson: const {
          'version': 1,
          'moves': [
            {'id': 'water_3'},
          ],
        },
        monsters: [taughtMonster],
      ),
      isFalse,
    );
  });

  test('master が投入されていない時は StateError を投げる (空の定義で続けない)', () {
    expect(
      () => buildDexDefinitions(
        latestMasterJson: null,
        definitionJsons: [waxDefinitionJson],
      ),
      throwsStateError,
    );
  });
}
