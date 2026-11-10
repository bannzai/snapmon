import 'package:flutter/painting.dart';

/// 画面で使う色の定義。値は documents/DIRECTION.md「デザインの方向」と
/// documents/design/mock-2026-10-21/ のモックから取った。画面のコードは色をここからだけ参照する。
abstract final class SnapmonColors {
  /// 画面の地 (深い紫がかった黒)。
  static const Color background = Color(0xFF15121C);

  /// 地の上に置くボタン・カードの面。
  static const Color surface = Color(0xFF231E30);

  /// [surface] より一段明るい面 (ファインダー・バトルの空・相手のモンスターの枠)。
  static const Color surfaceRaised = Color(0xFF2D2740);

  /// バトルの地面。
  static const Color battleGround = Color(0xFF241F33);

  /// 図鑑の「すべて」の絵の背景。
  static const Color artBackground = Color(0xFF3A3350);

  /// アクセント 1 色 (電気のような黄緑)。主ボタン・選択中・自分の HP。
  static const Color accent = Color(0xFFC6F432);

  /// 生成りの白のカード。
  static const Color card = Color(0xFFF4F1EA);

  /// カードの中の区切り (ステータスの枠)。
  static const Color cardSubtle = Color(0xFFEFEBE2);

  /// カードの中の HP の減った部分。
  static const Color cardTrack = Color(0xFFE3DFD6);

  /// HP の減り (相手の HP・警告)。
  static const Color hitPointsLoss = Color(0xFFFF6B6B);

  /// 地の上の文字。
  static const Color textOnBackground = Color(0xFFF4F1EA);

  /// 地の上の補足の文字。
  static const Color textMuted = Color(0xFFA9A3B8);

  /// カードの上の文字。
  static const Color textOnCard = Color(0xFF15121C);

  /// カードの上の補足の文字。
  static const Color textOnCardMuted = Color(0xFF4A4556);

  /// カードの上の本文 (図鑑の文章)。
  static const Color textOnCardBody = Color(0xFF2A2534);

  /// 絵や写真の上に重ねる文字の下地 (地の色の 85%)。
  static const Color scrim = Color(0xD915121C);

  /// 属性の札の色。仮の絵の主色にも使う。master の版 8 の 23 属性 (documents/game-rules.md「属性」) で、
  /// master の `effects` の `colorHex` と同じ値。master に無い属性 (その場で作った定義) は [elementFallback] で描く。
  static const Map<String, Color> elementTypes = {
    'fire': Color(0xFFE8734A),
    'water': Color(0xFF4A90D9),
    'grass': Color(0xFF3FA66B),
    'thunder': Color(0xFFD9C531),
    'earth': Color(0xFF8A7F72),
    'steel': Color(0xFF6D7B8A),
    'wood': Color(0xFFB07A4A),
    'light': Color(0xFFEDE3A6),
    'dark': Color(0xFF5E5577),
    'poison': Color(0xFF8E44AD),
    'sound': Color(0xFFB388FF),
    'beast': Color(0xFFC49A6C),
    'bug': Color(0xFF7CB342),
    'bird': Color(0xFF7FB3D5),
    'fish': Color(0xFF3BAFA5),
    'ice': Color(0xFFA8E0F0),
    'wind': Color(0xFFB8C9D9),
    'flower': Color(0xFFF48FB1),
    'machine': Color(0xFFB0BEC5),
    'sweets': Color(0xFFE8A0D8),
    'ghost': Color(0xFF9FA8DA),
    'dragon': Color(0xFFC62828),
    'paper': Color(0xFFC9B79A),
  };

  /// [elementTypes] に無い属性の色。
  static const Color elementFallback = Color(0xFF5B6CC9);
}

/// [elementTypeID] の属性の色を返す。
Color elementTypeColor({required String elementTypeID}) =>
    SnapmonColors.elementTypes[elementTypeID] ?? SnapmonColors.elementFallback;
