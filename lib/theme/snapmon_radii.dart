import 'package:flutter/painting.dart';

/// 角丸の定義。DIRECTION.md「デザインの方向」の「角丸は大きめ (12〜24px)、ボタンは四角に近い角丸」と、
/// モック (documents/design/mock-2026-10-21/) の値から取った。
abstract final class SnapmonRadii {
  /// 属性の札などの小さな部品。
  static const BorderRadius tag = BorderRadius.all(Radius.circular(8));

  /// ボタン・下タブ・小さなカード。
  static const BorderRadius button = BorderRadius.all(Radius.circular(12));

  /// モンスターのカード・技のボタン。
  static const BorderRadius card = BorderRadius.all(Radius.circular(16));

  /// ファインダー・生まれたモンスターの大きなカード。
  static const BorderRadius panel = BorderRadius.all(Radius.circular(24));
}
