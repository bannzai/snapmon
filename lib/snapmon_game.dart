import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

/// snapmon のゲーム本体。立ち上げ時点ではタイトルの文字だけを描く土台で、
/// 撮影・モンスター生成・バトルの画面はロードマップの子 issue で足す。
class SnapmonGame extends FlameGame {
  /// 画面中央に置くタイトルの文字。画面サイズが変わるたびに中央へ置き直す。
  final TextComponent title = TextComponent(
    text: 'snapmon',
    anchor: Anchor.center,
    textRenderer: TextPaint(
      style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 48),
    ),
  );

  @override
  Color backgroundColor() => const Color(0xFF101820);

  @override
  Future<void> onLoad() async {
    title.position = size / 2;
    add(title);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    title.position = size / 2;
  }
}
