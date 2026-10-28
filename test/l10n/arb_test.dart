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
  final englishMessages = _readMessages(path: 'lib/l10n/app_en.arb');

  test('英語の arb は原文 (日本語) のすべてのキーを持ち、原文に無いキーを持たない', () {
    expect(englishMessages.keys.toSet(), japaneseMessages.keys.toSet());
  });

  test('英語の文言は原文と同じプレースホルダーを使い、空でない', () {
    for (final entry in japaneseMessages.entries) {
      final englishMessage = englishMessages[entry.key]!;
      expect(englishMessage.trim(), isNotEmpty, reason: entry.key);
      expect(
        _placeholders(message: englishMessage),
        _placeholders(message: entry.value),
        reason: entry.key,
      );
    }
  });
}
