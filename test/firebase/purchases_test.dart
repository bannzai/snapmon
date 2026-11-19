import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:snapmon/firebase/purchases.dart';

/// `generation_tickets` の offering に入っている [identifier] の package の見本。
Package offeringPackage({required String identifier}) => Package(
  identifier,
  PackageType.custom,
  StoreProduct('snapmon_$identifier', '', identifier, 100, '¥100', 'JPY'),
  const PresentedOfferingContext('generation_tickets', null, null),
);

/// RevenueCat の SDK (`Purchases`) がネイティブ・Web の実装を呼ぶ method channel。
const MethodChannel purchasesChannel = MethodChannel('purchases_flutter');

/// [purchasesChannel] を、まだ初期化していない SDK として答える偽物に差し替え、受けた呼び出しを順に足していく list を返す。
/// テストの終わりに元へ戻す。
List<MethodCall> recordCallsToUnconfiguredPurchases() {
  final calls = <MethodCall>[];
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(purchasesChannel, (call) async {
        calls.add(call);
        return call.method == 'isConfigured' ? false : null;
      });
  addTearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(purchasesChannel, null),
  );
  return calls;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('生成チケットの購入画面には生成チケットの package だけを並びを保って出す', () {
    expect(
      generationTicketPackages(
        packages: [
          offeringPackage(identifier: 'ticket10'),
          offeringPackage(identifier: 'ticket30'),
          offeringPackage(identifier: 'actioncard_rank1'),
          offeringPackage(identifier: 'actioncard_rank2'),
          offeringPackage(identifier: 'actioncard_rank3'),
        ],
      ).map((package) => package.identifier),
      ['ticket10', 'ticket30'],
    );
  });

  test('Action Card の package だけの時は空になる', () {
    expect(
      generationTicketPackages(
        packages: [offeringPackage(identifier: 'actioncard_rank1')],
      ),
      isEmpty,
    );
  });

  group('このビルドが使う RevenueCat の鍵', () {
    test('Web のビルドは Web の鍵を使い、iOS・Android の鍵を使わない', () {
      for (final platform in TargetPlatform.values) {
        expect(
          revenueCatPublicApiKeyOf(
            isWeb: true,
            platform: platform,
            iosKey: 'ios-key',
            androidKey: 'android-key',
            webKey: 'web-key',
          ),
          'web-key',
          reason: 'Web のビルドを $platform の端末のブラウザで開いた時',
        );
      }
    });

    test('Web の鍵を渡していない Web のビルドは、iOS・Android の鍵があっても空になる', () {
      for (final platform in TargetPlatform.values) {
        expect(
          revenueCatPublicApiKeyOf(
            isWeb: true,
            platform: platform,
            iosKey: 'ios-key',
            androidKey: 'android-key',
            webKey: '',
          ),
          isEmpty,
          reason: 'Web のビルドを $platform の端末のブラウザで開いた時',
        );
      }
    });

    test('アプリのビルドは Web の鍵を使わず、iOS は iOS の鍵、Android は Android の鍵を使う', () {
      /// Web の鍵も渡したアプリのビルドが、[platform] の端末で使う鍵。
      String appKeyOf({required TargetPlatform platform}) =>
          revenueCatPublicApiKeyOf(
            isWeb: false,
            platform: platform,
            iosKey: 'ios-key',
            androidKey: 'android-key',
            webKey: 'web-key',
          );
      expect(appKeyOf(platform: TargetPlatform.iOS), 'ios-key');
      expect(appKeyOf(platform: TargetPlatform.android), 'android-key');
      expect(appKeyOf(platform: TargetPlatform.macOS), isEmpty);
    });

    test('鍵を渡していないビルド (--dart-define 無しのこのテスト) では課金を使えない', () {
      expect(isPurchasesEnabled(), isFalse);
    });
  });

  group('SDK のユーザーを uid に揃える', () {
    test('Web の鍵を渡した Web のビルドでログインしている時、SDK を Web の鍵と uid で初期化する', () async {
      final calls = recordCallsToUnconfiguredPurchases();
      await applyPurchasesUser(
        uid: 'alice',
        publicApiKey: revenueCatPublicApiKeyOf(
          isWeb: true,
          platform: TargetPlatform.android,
          iosKey: 'ios-key',
          androidKey: 'android-key',
          webKey: 'web-key',
        ),
      );
      expect(calls.map((call) => call.method), [
        'isConfigured',
        'setupPurchases',
      ]);
      expect(
        calls.last.arguments,
        allOf(
          containsPair('apiKey', 'web-key'),
          containsPair('appUserId', 'alice'),
        ),
      );
    });

    test('Web の鍵を渡していない Web のビルドでは、ログインしていても SDK を 1 度も呼ばない', () async {
      final calls = recordCallsToUnconfiguredPurchases();
      await applyPurchasesUser(
        uid: 'alice',
        publicApiKey: revenueCatPublicApiKeyOf(
          isWeb: true,
          platform: TargetPlatform.android,
          iosKey: 'ios-key',
          androidKey: 'android-key',
          webKey: '',
        ),
      );
      expect(calls, isEmpty);
    });

    test('鍵があってもログインしていない間は SDK を初期化しない', () async {
      final calls = recordCallsToUnconfiguredPurchases();
      await applyPurchasesUser(uid: null, publicApiKey: 'web-key');
      expect(calls.map((call) => call.method), ['isConfigured']);
    });
  });
}
