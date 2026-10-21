import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/snapmon_game.dart';

void main() {
  testWithGame<SnapmonGame>('タイトルの文字を画面中央に描く', SnapmonGame.new, (game) async {
    final title = game.children.whereType<TextComponent>().single;
    expect(title.text, 'snapmon');
    expect(title.position, game.size / 2);
  });
}
