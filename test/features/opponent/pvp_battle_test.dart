import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/features/opponent/pvp_battle.dart';

/// Functions (functions/src/pvp_rules.ts の publicMonster) が対戦に写す、ID が [monsterID] のモンスター 1 体の JSON。
Map<String, dynamic> _publicMonsterJSON({required String monsterID}) => {
  'definition': {
    'id': monsterID,
    'name': 'マグモン',
    'encyclopediaText': 'まいにち あたたかい のみものを はこぶ',
    'elementTypeIDs': ['fire'],
    'learnset': [
      {'moveID': 'fire_1', 'unlockLevel': 1},
    ],
    'baseStats': {'hitPoints': 50, 'attack': 50, 'defense': 50, 'speed': 50},
    'individualValues': {'hitPoints': 1, 'attack': 2, 'defense': 3, 'speed': 4},
    'statCalculationVersion': 1,
    'masterVersion': 1,
  },
  'level': 7,
  'artPath': 'monsters/$monsterID/art.png',
  'definitionIDs': <String>[],
  'decoration': null,
  'decorationVersion': null,
};

/// joinPvpMatch (functions/src/pvp_battle.ts) が書く `pvpBattles/{battleID}` と同じキーの JSON。
/// [overrides] のキーだけを、その値に置き換える。
Map<String, dynamic> _battleJSON({required Map<String, dynamic> overrides}) => {
  'host': {
    'uid': 'host-uid',
    'displayName': 'トレーナー 1111',
    'iconPath': 'users/host-uid/icons/icon-1.png',
    'monsters': [_publicMonsterJSON(monsterID: 'host-monster')],
  },
  'guest': {
    'uid': 'guest-uid',
    'displayName': 'トレーナー 2222',
    'iconPath': null,
    'monsters': [_publicMonsterJSON(monsterID: 'guest-monster')],
  },
  'randomSeed': 4294967295,
  'battleDate': '2026-11-20',
  'turnNumber': 0,
  'turnSeconds': 60,
  'winnerUID': null,
  'finishReason': null,
  'reportedWinnerUIDs': <String, dynamic>{},
  ...overrides,
};

void main() {
  test('組み合わせた直後の対戦の文書を、2 人の手持ち・乱数の種・対戦日ごと読む', () {
    final battle = PvpBattle.fromJson(
      battleID: 'battle-1',
      json: _battleJSON(overrides: {}),
    );

    expect(battle.battleID, 'battle-1');
    expect(battle.host.uid, 'host-uid');
    expect(battle.host.displayName, 'トレーナー 1111');
    expect(battle.host.iconPath, 'users/host-uid/icons/icon-1.png');
    expect(battle.host.monsters.single.definition.id, 'host-monster');
    expect(battle.host.monsters.single.definition.sourcePhotoReference, isNull);
    expect(battle.guest.uid, 'guest-uid');
    expect(battle.guest.iconPath, isNull);
    expect(battle.guest.monsters.single.level, 7);
    expect(battle.randomSeed, 4294967295);
    expect(battle.battleDate, DateTime(2026, 11, 20));
    expect(battle.turnNumber, 0);
    expect(battle.turnSeconds, 60);
    expect(battle.isFinished, isFalse);
    expect(battle.isNoContest, isFalse);
    expect(battle.winnerUID, isNull);
    expect(battle.finishReason, isNull);
  });

  test('ターンが進んだ対戦の、今のターンの番号を読む', () {
    expect(
      PvpBattle.fromJson(
        battleID: 'battle-1',
        json: _battleJSON(overrides: {'turnNumber': 12}),
      ).turnNumber,
      12,
    );
  });

  test('利用者が出した行動を、技・わるあがき・交代のどれも読む', () {
    expect(
      (battleActionFromJSON(json: {'kind': 'move', 'moveID': 'fire_1'})
              as UseMoveAction)
          .moveID,
      'fire_1',
    );
    expect(
      (battleActionFromJSON(json: {'kind': 'switch', 'memberIndex': 2})
              as SwitchMonsterAction)
          .memberIndex,
      2,
    );
    expect(
      battleActionFromJSON(json: {'kind': 'struggle'}),
      isA<StruggleAction>(),
    );
  });

  test('勝者が決まって終わった対戦の、勝者の uid と終わり方を読む', () {
    for (final (finishReasonJSON, finishReason) in [
      ('result', PvpFinishReason.result),
      ('timeout', PvpFinishReason.timeout),
    ]) {
      final battle = PvpBattle.fromJson(
        battleID: 'battle-1',
        json: _battleJSON(
          overrides: {
            'winnerUID': 'guest-uid',
            'finishReason': finishReasonJSON,
          },
        ),
      );

      expect(battle.isFinished, isTrue);
      expect(battle.isNoContest, isFalse);
      expect(battle.winnerUID, 'guest-uid');
      expect(battle.finishReason, finishReason);
    }
  });

  test('勝者のいない終わりを、勝敗なしとして読む', () {
    for (final (finishReasonJSON, finishReason) in [
      ('timeout', PvpFinishReason.timeout),
      ('mismatch', PvpFinishReason.mismatch),
      ('blocked', PvpFinishReason.blocked),
    ]) {
      final battle = PvpBattle.fromJson(
        battleID: 'battle-1',
        json: _battleJSON(overrides: {'finishReason': finishReasonJSON}),
      );

      expect(battle.isFinished, isTrue);
      expect(battle.isNoContest, isTrue);
      expect(battle.winnerUID, isNull);
      expect(battle.finishReason, finishReason);
    }
  });

  test('知らない終わり方・行動の種類は、別の値として読まずに失敗する', () {
    expect(
      () => PvpBattle.fromJson(
        battleID: 'battle-1',
        json: _battleJSON(overrides: {'finishReason': 'surrendered'}),
      ),
      throwsArgumentError,
    );
    expect(
      () => battleActionFromJSON(json: {'kind': 'item'}),
      throwsFormatException,
    );
  });

  test('技・わるあがき・交代の行動を、Functions の submitPvpAction が受け取る形にする', () {
    expect(battleActionToJSON(action: const UseMoveAction(moveID: 'fire_1')), {
      'kind': 'move',
      'moveID': 'fire_1',
    });
    expect(battleActionToJSON(action: const StruggleAction()), {
      'kind': 'struggle',
    });
    expect(
      battleActionToJSON(action: const SwitchMonsterAction(memberIndex: 1)),
      {'kind': 'switch', 'memberIndex': 1},
    );
  });
}
