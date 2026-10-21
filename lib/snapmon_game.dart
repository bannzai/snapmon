import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/painting.dart';

/// snapmon のゲーム本体。立ち上げ時点ではタイトルの文字だけを描く土台で、
/// 撮影・モンスター生成・バトルの画面はロードマップの子 issue で足す。
class SnapmonGame extends FlameGame {
  @override
  Color backgroundColor() => const Color(0xFF101820);

  @override
  Future<void> onLoad() async {
    add(
      TextComponent(
        text: 'snapmon',
        anchor: Anchor.center,
        position: size / 2,
        textRenderer: TextPaint(
          style: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 48),
        ),
      ),
    );
  }
}
