import 'package:flutter/painting.dart';

import 'snapmon_colors.dart';

/// 見出しの書体 (pubspec.yaml の fonts の family)。
const String headingFontFamily = 'DelaGothicOne';

/// 本文の書体 (pubspec.yaml の fonts の family)。
const String bodyFontFamily = 'ZenKakuGothicNew';

/// 画面で使う文字の定義。大きさ・太さはモック (documents/design/mock-2026-10-21/) から取った。
/// モックの 500 の太さは同梱していないため 400 で描く (pubspec.yaml の fonts)。
abstract final class SnapmonTextStyles {
  /// 画面の見出し (図鑑・対戦)。
  static const TextStyle screenTitle = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 28,
    height: 1.1,
    color: SnapmonColors.textOnBackground,
  );

  /// アプリ名のロゴ。
  static const TextStyle logo = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 22,
    color: SnapmonColors.textOnBackground,
  );

  /// 撮る画面の大きな呼びかけ。
  static const TextStyle hero = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 26,
    height: 1.3,
    color: SnapmonColors.textOnBackground,
  );

  /// カードの中のモンスターの名前。
  static const TextStyle cardTitle = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 28,
    height: 1.1,
    color: SnapmonColors.textOnCard,
  );

  /// ステータスの数値。
  static const TextStyle statValue = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 18,
    color: SnapmonColors.textOnCard,
  );

  /// 強調した数値 (戦績)。
  static const TextStyle accentNumber = TextStyle(
    fontFamily: headingFontFamily,
    fontSize: 18,
    color: SnapmonColors.accent,
  );

  /// 本文。
  static const TextStyle body = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 13,
    height: 1.5,
    color: SnapmonColors.textOnBackground,
  );

  /// 太字のラベル (ボタン・名前)。
  static const TextStyle label = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    color: SnapmonColors.textOnBackground,
  );

  /// 大きなボタンのラベル。
  static const TextStyle buttonLarge = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: SnapmonColors.textOnCard,
  );

  /// 小さな太字 (節の見出し・札)。
  static const TextStyle caption = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w700,
    color: SnapmonColors.textMuted,
  );

  /// さらに小さな太字 (レベル・技の補足・下タブ)。
  static const TextStyle small = TextStyle(
    fontFamily: bodyFontFamily,
    fontSize: 11,
    fontWeight: FontWeight.w700,
    color: SnapmonColors.textMuted,
  );
}
