import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/features/action_card/action_card_client.dart';
import 'package:snapmon/firebase/action_cards.dart';

import '../../action_card_client_fixture.dart';
import '../../monster_generator_fixture.dart';

void main() {
  test('Action Card の package はランクを返し 生成チケットの package は null を返す', () {
    expect(actionCardRankOfPackage(package: testActionCardPackage(rank: 2)), 2);
    // 生成チケットの package (生成チケットの購入画面に並べる側)
    expect(actionCardRankOfPackage(package: testTicketPackage), isNull);
  });

  group('creditRankToRedeem', () {
    test('技のランク以上で残高のあるうち一番安いランクのカードを使う', () {
      expect(
        creditRankToRedeem(moveRank: 1, creditsByRank: {1: 0, 2: 1, 3: 1}),
        2,
      );
      expect(creditRankToRedeem(moveRank: 2, creditsByRank: {2: 1}), 2);
    });

    test('技のランクより安いカードしか無ければ null', () {
      expect(
        creditRankToRedeem(moveRank: 3, creditsByRank: {1: 5, 2: 5}),
        isNull,
      );
    });
  });

  test('actionCardCredits は無いランクを 0 枚として読む', () {
    expect(actionCardCreditsOf(stored: null), {1: 0, 2: 0, 3: 0});
    expect(actionCardCreditsOf(stored: {'rank2': 3}), {1: 0, 2: 3, 3: 0});
  });
}
