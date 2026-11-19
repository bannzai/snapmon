import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// HTML の `<head>` にある、SNS がカードを作る時に読むタグ (`og:` と `twitter:`) の名前と値の組を返す。
/// [htmlPath] はリポジトリのルートからの HTML のパス。`<head>` が無い HTML では throw する。
Map<String, String> socialCardMetaTags({required String htmlPath}) => {
  for (final match
      in RegExp(
        r'<meta\s+(?:property|name)="((?:og|twitter):[^"]+)"\s+content="([^"]*)"\s*/?>',
      ).allMatches(
        RegExp(
          r'<head>(.*?)</head>',
          dotAll: true,
        ).firstMatch(File(htmlPath).readAsStringSync())![1]!,
      ))
    match[1]!: match[2]!,
};

void main() {
  // Web 版の URL (https://play.snapmonster.app/) を X などに貼った投稿にカードが出るかは、配信する HTML の <head> のタグで決まる。
  // Flutter の描画は JavaScript が動いてから始まるため、JavaScript を動かさないクローラーが読めるよう web/index.html に直に書く。
  group('web/index.html の SNS のカードのタグ', () {
    test('LP と同じ種類のタグを、Web 版の URL と LP と同じ文・画像で持つ', () {
      final landingPageTags = socialCardMetaTags(htmlPath: 'docs/index.html');

      // 形の確認: LP のタグを読めていなければ、下の比較は空どうしで通ってしまう
      expect(landingPageTags['og:title'], startsWith('SnapMonster'));
      expect(landingPageTags['og:description'], isNotEmpty);
      expect(socialCardMetaTags(htmlPath: 'web/index.html'), {
        ...landingPageTags,
        'og:url': 'https://play.snapmonster.app/',
      });
    });

    test('大きな画像のカードになる値を持つ', () {
      final webTags = socialCardMetaTags(htmlPath: 'web/index.html');

      expect(webTags['og:type'], 'website');
      expect(webTags['og:site_name'], 'SnapMonster');
      expect(webTags['og:locale'], 'ja_JP');
      expect(webTags['twitter:card'], 'summary_large_image');
      // 画像は LP が配信しているものを絶対 URL で指す (web/ に複製すると、絵柄を変える時に 2 か所を直すことになるため)
      expect(webTags['og:image'], 'https://snapmonster.app/og.png');
      expect(webTags['twitter:image'], 'https://snapmonster.app/og.png');
      expect(webTags['og:image:width'], '1200');
      expect(webTags['og:image:height'], '630');
      expect(webTags['twitter:title'], webTags['og:title']);
      expect(webTags['twitter:description'], webTags['og:description']);
    });

    test('<title>・description・Flutter が置き換える <base> は変えない', () {
      final webIndexHTML = File('web/index.html').readAsStringSync();

      expect(webIndexHTML, contains('<base href="\$FLUTTER_BASE_HREF">'));
      expect(webIndexHTML, contains('<title>SnapMonster</title>'));
      expect(
        webIndexHTML,
        contains(
          '<meta name="description" content="撮った写真の被写体がモンスターになってバトルするゲーム">',
        ),
      );
    });
  });
}
