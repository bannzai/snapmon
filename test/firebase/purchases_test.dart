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

void main() {
  test('生成チケットの購入画面には生成チケットの package だけを並びを保って出す', () {
    final packages = generationTicketPackages(
      packages: [
        offeringPackage(identifier: 'ticket10'),
        offeringPackage(identifier: 'ticket30'),
        offeringPackage(identifier: 'actioncard_rank1'),
        offeringPackage(identifier: 'actioncard_rank2'),
        offeringPackage(identifier: 'actioncard_rank3'),
      ],
    );

    expect(packages.map((package) => package.identifier), [
      'ticket10',
      'ticket30',
    ]);
  });

  test('Action Card の package だけの時は空になる', () {
    expect(
      generationTicketPackages(
        packages: [offeringPackage(identifier: 'actioncard_rank1')],
      ),
      isEmpty,
    );
  });
}
