import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/domain/master/master_data.dart';
import 'package:snapmon/domain/master/move.dart';

void main() {
  final master = MasterData.fromJson(
    json:
        jsonDecode(File('assets/master/master.json').readAsStringSync())
            as Map<String, dynamic>,
  );

  /// 威力 [power]・命中率 [accuracy] の特殊効果の無い攻撃技を作る。
  Move attackMove({required int power, int accuracy = 100}) => Move(
    id: 'power_$power',
    displayName: 'テスト',
    elementTypeId: 'fire',
    power: power,
    powerPoints: 10,
    category: MoveCategory.attack,
    effectId: 'none',
    learnableLevelMinimum: 1,
    learnableLevelMaximum: 999,
    specialEffect: null,
    accuracy: accuracy,
  );

  group('moveAccuracyPercent (#279)', () {
    test('威力 50 以下は master の命中率のまま、50 を超えると威力 5 ごとに 1 下がる', () {
      expect(moveAccuracyPercent(move: attackMove(power: 40)), 100);
      expect(moveAccuracyPercent(move: attackMove(power: 50)), 100);
      expect(moveAccuracyPercent(move: attackMove(power: 55)), 99);
      expect(moveAccuracyPercent(move: attackMove(power: 75)), 95);
      expect(moveAccuracyPercent(move: attackMove(power: 110)), 88);
    });

    test('威力の割合は 70% より下がらない', () {
      expect(moveAccuracyPercent(move: attackMove(power: 200)), 70);
      expect(moveAccuracyPercent(move: attackMove(power: 300)), 70);
    });

    test('master の命中率に威力の割合を掛ける', () {
      expect(
        moveAccuracyPercent(move: attackMove(power: 110, accuracy: 50)),
        44,
      );
    });

    test('master の必中の技は威力に関係なく 100、一撃必殺は master の命中率のまま', () {
      final sureHitMoves = master.moves.where(
        (move) => move.specialEffect?.isSureHit ?? false,
      );
      expect(sureHitMoves, isNotEmpty);
      for (final move in sureHitMoves) {
        expect(moveAccuracyPercent(move: move), 100, reason: move.id);
      }
      final oneHitKnockoutMoves = master.moves.where(
        (move) => move.specialEffect?.isOneHitKnockout ?? false,
      );
      expect(oneHitKnockoutMoves, isNotEmpty);
      for (final move in oneHitKnockoutMoves) {
        expect(moveAccuracyPercent(move: move), move.accuracy, reason: move.id);
      }
    });
  });
}
