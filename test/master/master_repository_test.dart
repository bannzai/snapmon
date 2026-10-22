import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    expect(
      definitions.moveById(moveId: 'dynamic-wax-1').displayName,
      'ろうアタック',
    );
    expect(definitions.moveById(moveId: 'metal_1').displayName, isNotEmpty);
  });

  test('同じ ID の定義は master を優先する', () {
    final masterMetalMove = buildDexDefinitions(
      latestMasterJson: masterJson,
      definitionJsons: const [],
    ).moveById(moveId: 'metal_1');
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
              'id': 'metal_1',
              'displayName': '上書きしようとした技',
            },
          ],
        },
      ],
    );
    expect(
      definitions.moveById(moveId: 'metal_1').displayName,
      masterMetalMove.displayName,
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
