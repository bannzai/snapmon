import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/settings/settings_screen.dart';

void main() {
  // GitHub Pages が docs/ を公開する独自ドメイン。GitHub Pages は docs/CNAME の中身のドメインで配信する
  final publicPageHost = File('docs/CNAME').readAsStringSync().trim();

  test('紹介ページの URL は、docs/ を公開する独自ドメインの直下を指す', () {
    expect(landingPageUri, Uri.parse('https://$publicPageHost/'));
  });

  test('利用規約・プライバシーポリシー・アカウントの削除の案内の URL は、独自ドメインの、docs/ にファイルがあるパスを指す', () {
    for (final uri in [termsUri, privacyPolicyUri, accountDeletionUri]) {
      expect(uri.scheme, 'https', reason: '$uri');
      expect(uri.host, publicPageHost, reason: '$uri');
      expect(File('docs${uri.path}.md').existsSync(), isTrue, reason: '$uri');
    }
  });
}
