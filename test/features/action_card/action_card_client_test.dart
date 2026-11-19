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

  test('Web の商品の ID は 末尾の _web を 1 つだけ外してアプリの商品の ID に直す', () {
    expect(
      appProductIDOfStoreProductID(
        storeProductID: 'snapmon_actioncardrank1_100yen_web',
      ),
      'snapmon_actioncardrank1_100yen',
    );
    // アプリの商品と アプリと同じ ID で作った Web の商品はそのまま
    expect(
      appProductIDOfStoreProductID(
        storeProductID: 'snapmon_actioncardrank1_100yen',
      ),
      'snapmon_actioncardrank1_100yen',
    );
    // 2 つ付いていても 1 つしか外さない
    expect(
      appProductIDOfStoreProductID(
        storeProductID: 'snapmon_actioncardrank1_100yen_web_web',
      ),
      'snapmon_actioncardrank1_100yen_web',
    );
    // _web で終わらない 似た末尾は外さない
    for (final storeProductID in [
      'snapmon_actioncardrank1_100yen_website',
      'snapmon_actioncardrank1_100yenweb',
      'snapmon_actioncardrank1_100yen_WEB',
      'snapmon_actioncardrank1_100yen_web_',
      'snapmon_web_actioncardrank1_100yen',
    ]) {
      expect(
        appProductIDOfStoreProductID(storeProductID: storeProductID),
        storeProductID,
      );
    }
  });

  test('Web の package は 末尾の _web を外した商品の ID で引け 別の商品の ID では引けない', () {
    final packages = [
      testWebActionCardPackage(productID: testCheapActionCardProductID),
      testWebActionCardPackage(productID: testExpensiveActionCardProductID),
    ];
    expect(
      actionCardPackageOfProductID(
        packages: packages,
        productID: testExpensiveActionCardProductID,
      )?.storeProduct.identifier,
      '${testExpensiveActionCardProductID}_web',
    );
    expect(
      actionCardPackageOfProductID(
        packages: packages,
        productID: testModerateActionCardProductID,
      ),
      isNull,
    );
    // 技の商品の表は アプリの商品の ID で持つため Web の商品の ID そのものでは引けない
    expect(
      actionCardPackageOfProductID(
        packages: packages,
        productID: '${testExpensiveActionCardProductID}_web',
      ),
      isNull,
    );
  });
}
