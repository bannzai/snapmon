import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/master/move_effect.dart';
import 'package:snapmon/features/battle/battle_field_game.dart';

import '../../card_sharer_fixture.dart';
import '../../decorated_monster_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// 自分の場のモンスターの切り出した被写体の画像のパス。相手 (見本のモンスター) は画像を持たない。
  const playerArtPath = 'monsters/player-monster/art.png';

  BattleFieldGame createGame() => BattleFieldGame(
    playerMonster: ownedMonsterWithArt(
      monster: sampleData.monsters[0],
      artPath: playerArtPath,
      sourcePhotoReference: 'users/uid-1/photos/request-1',
    ),
    opponentMonster: sampleData.monsters[1],
  );

  /// 横 [width] × 縦 [height] の画像。切り出した被写体の画像の代わりに使う。
  Future<Image> createArtImage({required int width, required int height}) {
    final recorder = PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..color = const Color(0xFFC6F432),
    );
    return recorder.endRecording().toImage(width, height);
  }

  /// [component] を描いた時の Canvas の呼び出しを記録して返す。
  List<Invocation> renderInvocations({required MonsterComponent component}) {
    final canvas = _RecordingCanvas();
    component.render(canvas);
    return canvas.invocations;
  }

  testWithGame<BattleFieldGame>('相手のモンスターを右上、自分のモンスターを左下に置く', createGame, (
    game,
  ) async {
    game.onGameResize(Vector2(390, 500));
    final opponent = game.opponentMonsterComponent;
    final player = game.playerMonsterComponent;
    expect(
      opponent.monster.definition.id,
      sampleData.monsters[1].definition.id,
    );
    expect(player.monster.definition.id, sampleData.monsters[0].definition.id);
    expect(opponent.center.x, greaterThan(game.size.x / 2));
    expect(opponent.center.y, lessThan(game.size.y / 2));
    expect(player.center.x, lessThan(game.size.x / 2));
    expect(player.center.y, greaterThan(game.size.y / 2));
  });

  /// 横長 (PC のブラウザ・タブレットの横向き) と縦長 (スマホ) の画面。
  /// 1280×350 は 1280×656 の画面から技のパネルを除いた、実際のフィールドに近い高さ。
  for (final fieldSize in [
    Vector2(1280, 656),
    Vector2(1280, 350),
    Vector2(390, 844),
  ]) {
    testWithGame<BattleFieldGame>(
      '${fieldSize.x.toInt()}×${fieldSize.y.toInt()} の画面でも 2 体がフィールドに収まり重ならない',
      createGame,
      (game) async {
        game.onGameResize(fieldSize);
        final field = Rect.fromLTWH(0, 0, fieldSize.x, fieldSize.y);
        final opponentRect = game.opponentMonsterComponent.toRect();
        final playerRect = game.playerMonsterComponent.toRect();
        for (final monsterRect in [opponentRect, playerRect]) {
          expect(field.intersect(monsterRect), monsterRect);
        }
        expect(opponentRect.overlaps(playerRect), isFalse);
        expect(opponentRect.center.dx, greaterThan(fieldSize.x / 2));
        expect(playerRect.center.dx, lessThan(fieldSize.x / 2));
      },
    );
  }

  /// 1280×263 は、初回の導線の決着の後に勝敗のパネルと生まれたカードが並んだ時のフィールドの高さ (QA の実測)。
  /// 181 は相手の情報カードの下端 (上から 96 + カードの高さ約 85)。
  testWithGame<BattleFieldGame>(
    '低いフィールドでは自分の絵の上端を相手の情報カードの下端より下に置く',
    createGame,
    (game) async {
      game.onGameResize(Vector2(1280, 263));
      game.updateOpponentStatusCardBottom(bottom: 181);
      expect(
        game.playerMonsterComponent.toRect().top,
        greaterThanOrEqualTo(181 - 0.001),
      );
      expect(
        game.opponentMonsterComponent.toRect().overlaps(
          game.playerMonsterComponent.toRect(),
        ),
        isFalse,
      );
    },
  );

  testWithGame<BattleFieldGame>('相手の情報カードより低いフィールドでもモンスターの絵を消さない', createGame, (
    game,
  ) async {
    game.onGameResize(Vector2(1280, 180));
    game.updateOpponentStatusCardBottom(bottom: 181);
    expect(game.opponentMonsterComponent.size.x, greaterThan(0));
    expect(game.playerMonsterComponent.size.x, greaterThan(0));
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

    final nextMonster = sampleData.monsters[2];
    game.switchIn(side: BattleSideId.opponent, monster: nextMonster);
    await game.ready();
    expect(
      game.opponentMonsterComponent.monster.definition.id,
      nextMonster.definition.id,
    );
    expect(game.opponentMonsterComponent.isVisible, isTrue);
    expect(game.opponentMonsterComponent.position, positionBefore);
    expect(game.children.whereType<MonsterComponent>(), hasLength(2));
  });

  testWithGame<BattleFieldGame>(
    '切り出した画像が届くまでは四角の仮の絵で描き、届いたらそのパスのモンスターだけを Sprite で描く',
    createGame,
    (game) async {
      final player = game.playerMonsterComponent;
      final opponent = game.opponentMonsterComponent;
      expect(player.artSprite, isNull);
      expect(
        renderInvocations(component: player).map((call) => call.memberName),
        isNot(contains(#drawImageRect)),
      );

      final artImage = await createArtImage(width: 8, height: 8);
      addTearDown(artImage.dispose);
      game.applyArtImage(artPath: playerArtPath, artImage: artImage);

      expect(player.artSprite?.image, artImage);
      expect(
        renderInvocations(component: player).map((call) => call.memberName),
        contains(#drawImageRect),
      );
      // 画像を持たない相手は仮の絵のまま
      expect(opponent.artSprite, isNull);
      expect(
        renderInvocations(component: opponent).map((call) => call.memberName),
        isNot(contains(#drawImageRect)),
      );
    },
  );

  testWithGame<BattleFieldGame>('縦長の画像は引き伸ばさず、枠の中央に縦横比を保って描く', createGame, (
    game,
  ) async {
    final player = game.playerMonsterComponent..size = Vector2(100, 100);
    final artImage = await createArtImage(width: 10, height: 20);
    addTearDown(artImage.dispose);
    game.applyArtImage(artPath: playerArtPath, artImage: artImage);

    expect(
      renderInvocations(component: player)
          .singleWhere((call) => call.memberName == #drawImageRect)
          .positionalArguments[2],
      const Rect.fromLTWH(25, 0, 50, 100),
    );
  });

  testWithGame<BattleFieldGame>('装飾を持つモンスターは、画像に輪郭線・目などの装飾を重ねて描く', createGame, (
    game,
  ) async {
    final artImage = await createArtImage(width: 8, height: 8);
    addTearDown(artImage.dispose);
    game.applyArtImage(artPath: playerArtPath, artImage: artImage);
    game.switchIn(
      side: BattleSideId.player,
      monster: decoratedMonster(
        monster: sampleData.monsters[0],
        artPath: playerArtPath,
        decoration: testDecoration(),
        decorationVersion: 1,
      ),
    );
    final memberNames = renderInvocations(
      component: game.playerMonsterComponent..size = Vector2(100, 100),
    ).map((call) => call.memberName);
    // 輪郭線は画像を周りにずらして重ねて描くため、画像を描く呼び出しが 1 回より多い
    expect(
      memberNames.where((name) => name == #drawImageRect).length,
      greaterThan(1),
    );
    expect(memberNames, contains(#drawCircle));
  });

  testWithGame<BattleFieldGame>('画像が届いた後に交代で出たモンスターも、同じパスなら画像で描く', createGame, (
    game,
  ) async {
    final artImage = await createArtImage(width: 8, height: 8);
    addTearDown(artImage.dispose);
    game.applyArtImage(artPath: playerArtPath, artImage: artImage);

    game.switchIn(
      side: BattleSideId.player,
      monster: ownedMonsterWithArt(
        monster: sampleData.monsters[2],
        artPath: playerArtPath,
        sourcePhotoReference: 'users/uid-1/photos/request-2',
      ),
    );
    expect(game.playerMonsterComponent.artSprite?.image, artImage);

    game.switchIn(
      side: BattleSideId.player,
      monster: ownedMonsterWithArt(
        monster: sampleData.monsters[3],
        artPath: 'monsters/not-loaded/art.png',
        sourcePhotoReference: 'users/uid-1/photos/request-3',
      ),
    );
    expect(game.playerMonsterComponent.artSprite, isNull);
  });
}

/// 受け取った描画の呼び出しを [invocations] に残す Canvas。部品がどちらの描き方 (画像・仮の絵) をしたかを確かめるため。
class _RecordingCanvas implements Canvas {
  /// 受け取った呼び出し (呼ばれた順)。
  final List<Invocation> invocations = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    invocations.add(invocation);
    return null;
  }
}
