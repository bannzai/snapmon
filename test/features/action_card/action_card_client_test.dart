import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/features/action_card/action_card_client.dart';

import '../../action_card_client_fixture.dart';
import '../../monster_generator_fixture.dart';

void main() {
  test('Action Card の package はランクを返し 生成チケットの package は null を返す', () {
    expect(actionCardRankOfPackage(package: testActionCardPackage(rank: 2)), 2);
    // 生成チケットの package (生成チケットの購入画面に並べる側)
    expect(actionCardRankOfPackage(package: testTicketPackage), isNull);
  });
}
