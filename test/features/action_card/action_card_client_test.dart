import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/features/action_card/action_card_client.dart';

import '../../action_card_client_fixture.dart';
import '../../monster_generator_fixture.dart';

void main() {
  test('Action Card の package は Action Card と見分け 生成チケットの package は見分けない', () {
    expect(
      isActionCardPackage(
        package: testActionCardPackage(
          productID: testModerateActionCardProductID,
        ),
      ),
      isTrue,
    );
    // 生成チケットの package (生成チケットの購入画面に並べる側)
    expect(isActionCardPackage(package: testTicketPackage), isFalse);
  });

  test('技の商品の ID と同じストアの商品の ID の package を返し 無ければ null を返す', () {
    final packages = [
      testActionCardPackage(productID: testCheapActionCardProductID),
      testActionCardPackage(productID: testExpensiveActionCardProductID),
    ];
    expect(
      actionCardPackageOfProductID(
        packages: packages,
        productID: testExpensiveActionCardProductID,
      )?.storeProduct.identifier,
      testExpensiveActionCardProductID,
    );
    // 売っていない商品 (offering に無い) の技は値段を出せない
    expect(
      actionCardPackageOfProductID(
        packages: packages,
        productID: testModerateActionCardProductID,
      ),
      isNull,
    );
  });
}
