import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // iOS の Google の連携 (firebase_auth の linkWithProvider) は、ブラウザの画面からアプリに戻る URL scheme が Info.plist に
  // 登録されていないと、firebase-ios-sdk が fatalError でアプリを落とす (OAuthProvider.swift の "Please register custom URL scheme")。
  // scheme は Firebase の iOS アプリの ID から決まるため、ID を変えた時に Info.plist を直し忘れると、Google を選んだ時だけ落ちる。
  test('Info.plist の URL scheme に、Firebase の iOS アプリの ID から決まる戻り先がある', () {
    final firebaseIOSAppID =
        (((((jsonDecode(File('firebase.json').readAsStringSync())
                                as Map<String, Object?>)['flutter']
                            as Map<String, Object?>)['platforms']
                        as Map<String, Object?>)['ios']
                    as Map<String, Object?>)['default']
                as Map<String, Object?>)['appId']
            as String;

    // 形の確認: 「1:<プロジェクト番号>:ios:<16 進>」(Firebase の iOS アプリの ID)。別の値を読んでいたら落ちる
    expect(firebaseIOSAppID, matches(RegExp(r'^1:\d+:ios:[0-9a-f]+$')));
    expect([
      for (final match in RegExp(r'<string>([^<]*)</string>').allMatches(
        RegExp(
          r'<key>CFBundleURLSchemes</key>\s*<array>(.*?)</array>',
          dotAll: true,
        ).firstMatch(File('ios/Runner/Info.plist').readAsStringSync())![1]!,
      ))
        match[1],
    ], contains('app-${firebaseIOSAppID.replaceAll(':', '-')}'));
  });
}
