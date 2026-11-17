import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snapmon/l10n/l10n.dart';

/// [preferredLocales] の端末で画面に使う言語。
Locale _resolve({required List<Locale>? preferredLocales}) => resolveAppLocale(
  preferredLocales: preferredLocales,
  supportedLocales: AppLocalizations.supportedLocales,
);

void main() {
  const traditionalChinese = Locale.fromSubtags(
    languageCode: 'zh',
    scriptCode: 'Hant',
  );

  for (final countryCode in ['TW', 'HK', 'MO']) {
    test('文字の種類が無い zh-$countryCode は繁体字で出す', () {
      expect(
        _resolve(preferredLocales: [Locale('zh', countryCode)]),
        traditionalChinese,
      );
    });
  }

  test('文字の種類が無い zh-CN と地域の無い zh は簡体字で出す', () {
    expect(
      _resolve(preferredLocales: [const Locale('zh', 'CN')]),
      const Locale('zh'),
    );
    expect(_resolve(preferredLocales: [const Locale('zh')]), const Locale('zh'));
  });

  test('文字の種類が付いた中国語は、地域より文字の種類で選ぶ', () {
    expect(
      _resolve(
        preferredLocales: [
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hans',
            countryCode: 'TW',
          ),
        ],
      ),
      const Locale('zh'),
    );
    expect(
      _resolve(
        preferredLocales: [
          const Locale.fromSubtags(
            languageCode: 'zh',
            scriptCode: 'Hant',
            countryCode: 'CN',
          ),
        ],
      ),
      traditionalChinese,
    );
  });

  test('地域の付いたほかの言語は同じ言語の arb で出す', () {
    expect(
      _resolve(preferredLocales: [const Locale('fr', 'CA')]),
      const Locale('fr'),
    );
    expect(
      _resolve(preferredLocales: [const Locale('pt', 'PT')]),
      const Locale('pt', 'PT'),
    );
    expect(
      _resolve(preferredLocales: [const Locale('pt', 'BR')]),
      const Locale('pt'),
    );
  });

  test('対応していない言語と優先言語が無い時は英語で出す', () {
    expect(_resolve(preferredLocales: [const Locale('sw')]), const Locale('en'));
    expect(_resolve(preferredLocales: null), const Locale('en'));
  });
}
