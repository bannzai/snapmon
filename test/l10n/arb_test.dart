import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [path] の arb の文言のキー (`@` で始まるメタデータを除く) と値。
Map<String, String> _readMessages({required String path}) => {
  for (final entry
      in (jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>)
          .entries)
    if (!entry.key.startsWith('@')) entry.key: entry.value as String,
};

/// [message] に含まれるプレースホルダー (`{name}` と、ICU の plural の `{name, plural, ...}`) の名前。
Set<String> _placeholders({required String message}) => {
  for (final match in RegExp(r'\{(\w+)[,}]').allMatches(message)) match[1]!,
};

void main() {
  final japaneseMessages = _readMessages(path: 'lib/l10n/app_ja.arb');
  final translatedArbPaths = [
    for (final file in Directory('lib/l10n').listSync().whereType<File>())
      if (file.path.endsWith('.arb') && !file.path.endsWith('app_ja.arb'))
        file.path,
  ]..sort();

  test('App Store の掲載が対応する言語の arb がある', () {
    // Apple の App Store localizations の 50 言語 (https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/
    // 、2026-11-17 に確認) を、gen-l10n の言語にまとめたもの。地域だけが違う英語・フランス語・スペイン語は 1 つにし、
    // ポルトガル語は pt (ブラジル) と pt_PT、中国語は zh (簡体字) と zh_Hant、ノルウェー語は nb で持つ
    expect(
      [
        for (final path in translatedArbPaths)
          path.split('app_').last.replaceAll('.arb', ''),
      ],
      [
        ...['ar', 'bn', 'ca', 'cs', 'da', 'de', 'el', 'en', 'es', 'fi', 'fr'],
        ...['gu', 'he', 'hi', 'hr', 'hu', 'id', 'it', 'kn', 'ko', 'ml', 'mr'],
        ...['ms', 'nb', 'nl', 'or', 'pa', 'pl', 'pt', 'pt_PT', 'ro', 'ru'],
        ...['sk', 'sl', 'sv', 'ta', 'te', 'th', 'tr', 'uk', 'ur', 'vi', 'zh'],
        'zh_Hant',
      ],
    );
  });

  for (final path in translatedArbPaths) {
    final translatedMessages = _readMessages(path: path);

    test('$path は原文 (日本語) のすべてのキーを持ち、原文に無いキーを持たない', () {
      expect(translatedMessages.keys.toSet(), japaneseMessages.keys.toSet());
    });

    test('$path の文言は原文と同じプレースホルダーを使い、空でない', () {
      for (final entry in japaneseMessages.entries) {
        final translatedMessage = translatedMessages[entry.key]!;
        // 区切りの文言 (settingsProviderSeparator 等) は空白だけの言語があるため、trim せずに確かめる
        expect(translatedMessage, isNotEmpty, reason: entry.key);
        expect(
          _placeholders(message: translatedMessage),
          _placeholders(message: entry.value),
          reason: entry.key,
        );
      }
    });
  }
}
