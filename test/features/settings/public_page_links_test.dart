import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/settings/settings_screen.dart';

void main() {
  // GitHub Pages が docs/ を公開する独自ドメイン。GitHub Pages は docs/CNAME の中身のドメインで配信する
  final publicPageHost = File('docs/CNAME').readAsStringSync().trim();

  test('紹介ページの URL は、docs/ を公開する独自ドメインの直下を指す', () {
    expect(landingPageUri, Uri.parse('https://$publicPageHost/'));
  });

  test(
    '利用規約・プライバシーポリシー・アカウントの削除の案内・特定商取引法に基づく表記の URL は、独自ドメインの、docs/ にファイルがあるパスを指す',
    () {
      for (final uri in [
        termsUri,
        privacyPolicyUri,
        accountDeletionUri,
        specifiedCommercialTransactionsUri,
      ]) {
        expect(uri.scheme, 'https', reason: '$uri');
        expect(uri.host, publicPageHost, reason: '$uri');
        expect(File('docs${uri.path}.md').existsSync(), isTrue, reason: '$uri');
      }
    },
  );

  test('各ページのファイルは、アプリが開く URL のパスで公開する (permalink がパスと同じ)', () {
    for (final uri in [
      termsUri,
      privacyPolicyUri,
      accountDeletionUri,
      specifiedCommercialTransactionsUri,
    ]) {
      expect(
        File('docs${uri.path}.md').readAsStringSync(),
        startsWith('---\npermalink: ${uri.path}\n---\n'),
        reason: '$uri',
      );
    }
  });

  test('利用規約は、Web 版の販売条件を定める特定商取引法に基づく表記へリンクする', () {
    expect(
      File('docs${termsUri.path}.md').readAsStringSync(),
      contains(
        '[特定商取引法に基づく表記](${specifiedCommercialTransactionsUri.pathSegments.single})',
      ),
    );
  });

  test('特定商取引法に基づく表記は、請求があれば販売事業者の氏名・住所・電話番号を開示することと請求先を書く', () {
    final page = File(
      'docs${specifiedCommercialTransactionsUri.path}.md',
    ).readAsStringSync();
    expect(page, contains('ご請求をいただいた場合に、遅滞なく電子メールで開示します'));
    expect(page, contains(contactUri.path));
  });
}
