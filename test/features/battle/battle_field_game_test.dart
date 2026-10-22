import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/master/move_effect.dart';
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

  test('エフェクトの主色を #RRGGBB から読む', () {
    expect(
      moveEffectColor(
        effect: const MoveEffect(
          id: 'water_particle',
          displayName: '水のパーティクル',
          kind: 'particle',
          colorHex: '#2196F3',
        ),
      ),
      const Color(0xFF2196F3),
    );
  });

  testWithGame<BattleFieldGame>(
    '被弾すると点滅し、エフェクトがあればパーティクルを出し、時間が経つと点滅が終わる',
    createGame,
    (game) async {
      game.hit(
        defenderSide: BattleSideId.opponent,
        effect: sampleData.definitions.effects.first,
      );
      await game.ready();
      expect(game.children.whereType<ParticleSystemComponent>(), hasLength(1));
      expect(game.opponentMonsterComponent.isBlinking, isTrue);
      expect(game.playerMonsterComponent.isBlinking, isFalse);

      game.update(hitReactionSeconds + 0.1);
      expect(game.opponentMonsterComponent.isBlinking, isFalse);
      expect(game.opponentMonsterComponent.isVisible, isTrue);
    },
  );

  testWithGame<BattleFieldGame>('わるあがき (エフェクト無し) はパーティクルを出さない', createGame, (
    game,
  ) async {
    game.hit(defenderSide: BattleSideId.player, effect: null);
    await game.ready();
    expect(game.children.whereType<ParticleSystemComponent>(), isEmpty);
    expect(game.playerMonsterComponent.isBlinking, isTrue);
  });

  testWithGame<BattleFieldGame>('倒れると描かなくなり、交代すると次のモンスターを同じ場所に置く', createGame, (
    game,
  ) async {
    game.onGameResize(Vector2(390, 500));
    final positionBefore = game.opponentMonsterComponent.position.clone();
    game.faint(side: BattleSideId.opponent);
    expect(game.opponentMonsterComponent.isVisible, isFalse);

    final nextMonster = sampleData.monsters[2].definition;
    game.switchIn(side: BattleSideId.opponent, definition: nextMonster);
    await game.ready();
    expect(game.opponentMonsterComponent.definition.id, nextMonster.id);
    expect(game.opponentMonsterComponent.isVisible, isTrue);
    expect(game.opponentMonsterComponent.position, positionBefore);
    expect(
      game.children.whereType<PlaceholderMonsterComponent>(),
      hasLength(2),
    );
  });
}
