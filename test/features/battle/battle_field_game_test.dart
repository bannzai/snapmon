import 'dart:convert';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_test/flame_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/domain/master/move_effect.dart';
import 'package:snapmon/features/battle/battle_field_game.dart';
import 'package:snapmon/features/battle/move_effect_sprite_sheets.dart';

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

  /// 600×103 は横向きのスマホ (844×390、下のセーフエリア 21) のフィールド。
  /// 218〜382・16〜102 は、左右に上げた 2 枚の情報カード (幅 190・高さ 86) の間 (battle_screen.dart の _monsterArtAreaMinimumWidthBetweenCards)。
  testWithGame<BattleFieldGame>(
    '絵を収める矩形を受け取ると、相手を左上・自分を右下にして 2 体をその中に重ねずに置き、null に戻すと比率の配置に戻す',
    createGame,
    (game) async {
      game.onGameResize(Vector2(600, 103));
      final opponentRectBefore = game.opponentMonsterComponent.toRect();
      const area = Rect.fromLTRB(218, 16, 382, 102);
      game.updateMonsterArtArea(area: area);
      final opponentRect = game.opponentMonsterComponent.toRect();
      final playerRect = game.playerMonsterComponent.toRect();
      // 自分の絵は矩形の右下の角に接するため、浮動小数の誤差の分だけ広げた矩形に収まるかを見る
      for (final monsterRect in [opponentRect, playerRect]) {
        expect(area.inflate(0.001).intersect(monsterRect), monsterRect);
      }
      expect(opponentRect.overlaps(playerRect), isFalse);
      expect(opponentRect.topLeft, area.topLeft);
      expect(playerRect.right, closeTo(area.right, 0.001));
      expect(playerRect.bottom, closeTo(area.bottom, 0.001));
      expect(playerRect.width, closeTo(opponentRect.width * 1.15, 0.001));

      game.updateMonsterArtArea(area: null);
      expect(game.opponentMonsterComponent.toRect(), opponentRectBefore);
    },
  );

  testWithGame<BattleFieldGame>(
    '高さが 0 以下の矩形を受け取った時は、比率の配置のままにして絵の大きさを負にしない',
    createGame,
    (game) async {
      game.onGameResize(Vector2(600, 10));
      final opponentRectBefore = game.opponentMonsterComponent.toRect();
      game.updateMonsterArtArea(area: const Rect.fromLTRB(218, 16, 382, 10));

      expect(game.opponentMonsterComponent.toRect(), opponentRectBefore);
      expect(game.playerMonsterComponent.size.x, greaterThan(0));
    },
  );

  testWithGame<BattleFieldGame>(
    '横向きの絵の領域では自分を左下・相手を右上に置き、同じ指定では位置を変えない',
    createGame,
    (game) async {
      game.onGameResize(Vector2(300, 390));
      const area = Rect.fromLTRB(8, 102, 292, 288);
      game.updateMonsterArtArea(area: area, placesPlayerOnLeft: true);
      final playerRect = game.playerMonsterComponent.toRect();
      final opponentRect = game.opponentMonsterComponent.toRect();
      expect(playerRect.center.dx, lessThan(opponentRect.center.dx));
      expect(playerRect.center.dy, greaterThan(opponentRect.center.dy));
      expect(playerRect.overlaps(opponentRect), isFalse);
      for (final rect in [playerRect, opponentRect]) {
        expect(area.inflate(0.001).intersect(rect), rect);
      }
      game.updateMonsterArtArea(area: area, placesPlayerOnLeft: true);
      expect(game.playerMonsterComponent.toRect(), playerRect);
      expect(game.opponentMonsterComponent.toRect(), opponentRect);
      game.updateMonsterArtArea(area: area);
      expect(
        game.playerMonsterComponent.center.x,
        greaterThan(game.opponentMonsterComponent.center.x),
      );
    },
  );

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

  group('スプライトシートのエフェクト', () {
    const steelEffect = MoveEffect(
      id: 'steel_particle',
      displayName: '鋼のパーティクル',
      kind: 'particle',
      colorHex: '#9AA5B1',
    );

    /// [steelEffect] を 4 コマ (横 2 × 縦 2、1 コマ 10 × 8) の合成した画像で描くようにする。
    Future<void> applyMetalSpriteSheet({required BattleFieldGame game}) async {
      final spriteSheetImage = await createArtImage(width: 20, height: 16);
      addTearDown(spriteSheetImage.dispose);
      game.applyMoveEffectSpriteSheet(
        effectId: steelEffect.id,
        spriteSheetImage: spriteSheetImage,
        spriteSheetJson: const {
          'meta': {
            'pixelfx': {
              'frames': 4,
              'frameSize': [10, 8],
              'columns': 2,
            },
          },
        },
        visibleCenterAnchor: const Anchor(0.25, 0.5),
      );
    }

    testWithGame<BattleFieldGame>('シートを読み込む前の被弾はパーティクルで描く', createGame, (
      game,
    ) async {
      game.hit(defenderSide: BattleSideId.opponent, effect: steelEffect);
      await game.ready();
      expect(game.children.whereType<ParticleSystemComponent>(), hasLength(1));
      expect(game.children.whereType<SpriteAnimationComponent>(), isEmpty);
    });

    testWithGame<BattleFieldGame>(
      '被弾すると、被弾した絵の中心に合わせて単発で再生し、被弾の時間で消える',
      createGame,
      (game) async {
        game.onGameResize(Vector2(390, 500));
        await applyMetalSpriteSheet(game: game);
        game.hit(defenderSide: BattleSideId.opponent, effect: steelEffect);
        await game.ready();
        expect(game.children.whereType<ParticleSystemComponent>(), isEmpty);
        final component = game.children
            .whereType<SpriteAnimationComponent>()
            .single;
        expect(component.position, game.opponentMonsterComponent.center);
        expect(component.anchor, const Anchor(0.25, 0.5));
        expect(component.animation!.loop, isFalse);
        expect(component.animation!.frames, hasLength(4));
        expect(
          component.animation!.frames.last.sprite.srcPosition,
          Vector2(10, 8),
        );
        expect(
          component.size.x,
          closeTo(game.opponentMonsterComponent.size.x * 1.3, 0.001),
        );
        expect(component.size.y / component.size.x, closeTo(0.8, 0.001));

        // 再生の途中では残り、被弾の時間が過ぎると消える
        game.update(hitReactionSeconds * 0.9);
        await game.ready();
        expect(
          game.children.whereType<SpriteAnimationComponent>(),
          hasLength(1),
        );
        game.update(hitReactionSeconds * 0.2);
        await game.ready();
        game.update(0);
        await game.ready();
        expect(game.children.whereType<SpriteAnimationComponent>(), isEmpty);
      },
    );

    testWithGame<BattleFieldGame>(
      '素材は左から右へ描かれているため、攻撃する側が被弾する側より右にいる時だけ左右を反転する',
      createGame,
      (game) async {
        game.onGameResize(Vector2(390, 500));
        await applyMetalSpriteSheet(game: game);

        /// [defenderSide] の側に [steelEffect] の被弾を発行し、新しく出たエフェクトの水平方向の scale を返す。
        /// 1 なら素材の向きのまま、-1 なら左右を反転して描く。
        /// 呼ぶたびにエフェクトが [game] に 1 つ足される。
        Future<double> horizontalScaleOfNewEffect({
          required BattleSideId defenderSide,
        }) async {
          game.hit(defenderSide: defenderSide, effect: steelEffect);
          await game.ready();
          return game.children
              .whereType<SpriteAnimationComponent>()
              .last
              .scale
              .x;
        }

        // 比率の配置: 自分が左、相手が右
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideId.opponent),
          1,
        );
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideId.player),
          -1,
        );

        // 低くて幅の狭い画面の配置: 相手が左、自分が右
        game.onGameResize(Vector2(600, 103));
        game.updateMonsterArtArea(area: const Rect.fromLTRB(218, 16, 382, 102));
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideId.opponent),
          -1,
        );
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideId.player),
          1,
        );

        // 左右配置のバトル: 自分が左、相手が右
        game.updateMonsterArtArea(
          area: const Rect.fromLTRB(16, 16, 500, 102),
          placesPlayerOnLeft: true,
        );
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideId.opponent),
          1,
        );
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideId.player),
          -1,
        );
      },
    );

    testWithGame<BattleFieldGame>(
      '対応の無いエフェクトとわるあがきは、シートがあっても今までどおり描く',
      createGame,
      (game) async {
        await applyMetalSpriteSheet(game: game);
        game.hit(
          defenderSide: BattleSideId.opponent,
          effect: const MoveEffect(
            id: 'generated_effect',
            displayName: 'その場で作ったエフェクト',
            kind: 'particle',
            colorHex: '#2196F3',
          ),
        );
        game.hit(defenderSide: BattleSideId.player, effect: null);
        await game.ready();
        expect(
          game.children.whereType<ParticleSystemComponent>(),
          hasLength(1),
        );
        expect(game.children.whereType<SpriteAnimationComponent>(), isEmpty);
        expect(game.playerMonsterComponent.isBlinking, isTrue);
      },
    );

    testWithGame<BattleFieldGame>(
      '同梱のシートをすべて読み、読めないシートは飛ばして残りを描く',
      createGame,
      (game) async {
        // testWithGame は binding を初期化せず、rootBundle からアセットを読むのに要るため
        TestWidgetsFlutterBinding.ensureInitialized();
        await loadMoveEffectSpriteSheets(
          game: game,
          spriteSheetsByEffectId: {
            ...moveEffectSpriteSheetsByEffectId,
            'water_particle': (
              assetName: 'not-bundled',
              visibleCenterAnchor: Anchor.center,
            ),
          },
          assetBundle: rootBundle,
        );
        for (final MapEntry(key: effectId, value: spriteSheet)
            in moveEffectSpriteSheetsByEffectId.entries) {
          game.hit(
            defenderSide: BattleSideId.opponent,
            effect: MoveEffect(
              id: effectId,
              displayName: spriteSheet.assetName,
              kind: 'particle',
              colorHex: '#FFFFFF',
            ),
          );
        }
        game.hit(
          defenderSide: BattleSideId.opponent,
          effect: const MoveEffect(
            id: 'water_particle',
            displayName: '水のパーティクル',
            kind: 'particle',
            colorHex: '#2196F3',
          ),
        );
        await game.ready();
        final components = game.children.whereType<SpriteAnimationComponent>();
        expect(components, hasLength(moveEffectSpriteSheetsByEffectId.length));
        // JSON のコマの矩形が PNG の中に収まる (JSON と PNG が別の書き出しで食い違っていない)
        for (final component in components) {
          final image = component.animation!.frames.last.sprite.image;
          final lastFrame = component.animation!.frames.last.sprite;
          expect(
            lastFrame.srcPosition.x + lastFrame.srcSize.x,
            lessThanOrEqualTo(image.width),
          );
          expect(
            lastFrame.srcPosition.y + lastFrame.srcSize.y,
            lessThanOrEqualTo(image.height),
          );
        }
        expect(
          game.children.whereType<ParticleSystemComponent>(),
          hasLength(1),
        );
      },
    );

    testWithGame<BattleFieldGame>(
      'JSON は読めて PNG を decode できないシートは、未処理のエラーを出さずキャッシュにも残さずパーティクルのままにする',
      createGame,
      (game) async {
        // testWithGame は binding を初期化せず、画像の decode に要るため
        TestWidgetsFlutterBinding.ensureInitialized();
        await loadMoveEffectSpriteSheets(
          game: game,
          spriteSheetsByEffectId: const {
            'water_particle': (
              assetName: 'broken-png',
              visibleCenterAnchor: Anchor.center,
            ),
          },
          assetBundle: _BrokenPngAssetBundle(),
        );
        expect(game.images.containsKey('move_effects/broken-png.png'), isFalse);
        game.hit(
          defenderSide: BattleSideId.opponent,
          effect: const MoveEffect(
            id: 'water_particle',
            displayName: '水のパーティクル',
            kind: 'particle',
            colorHex: '#2196F3',
          ),
        );
        await game.ready();
        expect(game.children.whereType<SpriteAnimationComponent>(), isEmpty);
        expect(
          game.children.whereType<ParticleSystemComponent>(),
          hasLength(1),
        );
      },
    );

    test('同梱の素材は MIT の許諾文と由来の記載を持つ', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      expect(
        await rootBundle.loadString('assets/images/move_effects/LICENSE'),
        contains('MIT License'),
      );
      expect(
        await rootBundle.loadString('assets/images/move_effects/NOTICE.md'),
        contains('Hugo Duprez'),
      );
    });
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

  testWithGame<BattleFieldGame>('装飾を保存しているモンスターも、装飾を重ねず画像だけを描く', createGame, (
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
    final invocations = renderInvocations(
      component: game.playerMonsterComponent..size = Vector2(100, 100),
    );
    expect(invocations.map((call) => call.memberName), [#drawImageRect]);
    expect(
      invocations.single.positionalArguments[2],
      const Rect.fromLTWH(0, 0, 100, 100),
    );
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

/// JSON は正しく読めて、PNG は画像として decode できない中身を返すアセットの読み先。
class _BrokenPngAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    utf8.encode(
      key.endsWith('.json')
          ? '{"meta":{"pixelfx":{"frames":1,"frameSize":[1,1],"columns":1}}}'
          : 'not a png',
    ),
  );
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
