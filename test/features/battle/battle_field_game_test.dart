import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/features/battle/battle_field_game.dart';

import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();
  BattleFieldGame createGame() => BattleFieldGame(
    playerMonster: sampleData.monsters[0].definition,
    opponentMonster: sampleData.monsters[1].definition,
  );

  testWithGame<BattleFieldGame>('相手のモンスターを右上、自分のモンスターを左下に置く', createGame, (
    game,
  ) async {
    game.onGameResize(Vector2(390, 500));
    final opponent = game.opponentMonsterComponent;
    final player = game.playerMonsterComponent;
    expect(opponent.definition.id, sampleData.monsters[1].definition.id);
    expect(player.definition.id, sampleData.monsters[0].definition.id);
    expect(opponent.center.x, greaterThan(game.size.x / 2));
    expect(opponent.center.y, lessThan(game.size.y / 2));
    expect(player.center.x, lessThan(game.size.x / 2));
    expect(player.center.y, greaterThan(game.size.y / 2));
  });

  testWithGame<BattleFieldGame>('画面の大きさが変わると 2 体を置き直す', createGame, (
    game,
  ) async {
    game.onGameResize(Vector2(390, 500));
    final playerPositionBefore = game.playerMonsterComponent.position.clone();
    game.onGameResize(Vector2(800, 900));
    expect(game.playerMonsterComponent.position, isNot(playerPositionBefore));
    expect(
      game.playerMonsterComponent.y + game.playerMonsterComponent.height,
      lessThanOrEqualTo(900),
    );
  });
}
