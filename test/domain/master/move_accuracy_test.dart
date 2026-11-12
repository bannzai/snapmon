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
    elementTypeID: 'fire',
    power: power,
    powerPoints: 10,
    category: MoveCategory.attack,
    effectID: 'none',
    learnableLevelMinimum: 1,
    learnableLevelMaximum: 999,
    specialEffect: null,
    accuracy: accuracy,
  );

  group('moveAccuracyPercent (#279)', () {
    test('威力 75 以下は master の命中率のまま、75 を超えると威力 5 ごとに 1 下がる', () {
      expect(moveAccuracyPercent(move: attackMove(power: 40)), 100);
      expect(moveAccuracyPercent(move: attackMove(power: 75)), 100);
      expect(moveAccuracyPercent(move: attackMove(power: 80)), 99);
      expect(moveAccuracyPercent(move: attackMove(power: 110)), 93);
      expect(moveAccuracyPercent(move: attackMove(power: 200)), 75);
    });

    test('威力の割合は 70% より下がらない', () {
      expect(moveAccuracyPercent(move: attackMove(power: 225)), 70);
      expect(moveAccuracyPercent(move: attackMove(power: 300)), 70);
    });

    test('master の命中率に威力の割合を掛ける', () {
      expect(
        moveAccuracyPercent(move: attackMove(power: 110, accuracy: 50)),
        46,
      );
    });

    test('master の技は、段階 3・自爆・一撃必殺だけが命中率 100 未満で、それ以外は 100', () {
      final belowHundredMoves = master.moves
          .where((move) => moveAccuracyPercent(move: move) < 100)
          .toList();
      expect(
        belowHundredMoves.every(
          (move) =>
              move.power > accuracyPenaltyPowerThreshold ||
              (move.specialEffect?.isOneHitKnockout ?? false),
        ),
        isTrue,
        reason: belowHundredMoves.map((move) => move.id).join(','),
      );
      // 段階 3 (110)・自爆 (200)・一撃必殺の 3 種類 × 23 属性
      expect(belowHundredMoves.length, 69);
      expect(master.moves.length - belowHundredMoves.length, 533);
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
