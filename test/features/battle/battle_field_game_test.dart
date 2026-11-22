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
import 'package:snapmon/features/dex/owned_monster.dart';

import '../../card_sharer_fixture.dart';
import '../../decorated_monster_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  final sampleData = loadSampleDataFixture();

  /// 自分の場のモンスターの切り出した被写体の画像のパス。相手 (見本のモンスター) は同梱の見本の画像のパスを持つ。
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
      game.updateOverlayRects(
        rects: [const Rect.fromLTRB(20, 96, 210, 181)],
        battleLogRect: null,
      );
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
    game.updateOverlayRects(
      rects: [const Rect.fromLTRB(20, 96, 210, 181)],
      battleLogRect: null,
    );
    expect(game.opponentMonsterComponent.size.x, greaterThan(0));
    expect(game.playerMonsterComponent.size.x, greaterThan(0));
  });

  /// 393×532 は iPhone 15 Pro (393×852) の縦向きのバトルのフィールド (#243 のスクリーンショットの実測)。
  /// 矩形は、左上の相手のトレーナーの札と情報カード、右下に積んだ自分のトレーナーの札と情報カード。
  testWithGame<BattleFieldGame>(
    '縦向きのスマホでは、2 体の絵を情報カードとトレーナーの札に重ならない大きさにし、相手を右上・自分を左下に置く',
    createGame,
    (game) async {
      game.onGameResize(Vector2(393, 532));
      const overlayRects = [
        Rect.fromLTRB(20, 155, 130, 195),
        Rect.fromLTRB(20, 201, 210, 284),
        Rect.fromLTRB(183, 380, 373, 508),
      ];
      game.updateOverlayRects(rects: overlayRects, battleLogRect: null);
      final opponentRect = game.opponentMonsterComponent.toRect();
      final playerRect = game.playerMonsterComponent.toRect();
      for (final monsterRect in [opponentRect, playerRect]) {
        for (final overlayRect in overlayRects) {
          expect(monsterRect.overlaps(overlayRect), isFalse);
        }
      }
      expect(opponentRect.overlaps(playerRect), isFalse);
      expect(opponentRect.center.dx, greaterThan(game.size.x / 2));
      expect(playerRect.center.dx, lessThan(game.size.x / 2));
      // 被写体を見分けられる大きさ (battle_screen_test.dart の左右配置の下限 60px) を保つ
      expect(opponentRect.width, greaterThanOrEqualTo(60));
    },
  );

  testWithGame<BattleFieldGame>(
    '絵の広がる向きと逆側にある矩形では絵を縮めず、同じ矩形の並びを受け取っても置き直さない',
    createGame,
    (game) async {
      game.onGameResize(Vector2(393, 532));
      final opponentRectBefore = game.opponentMonsterComponent.toRect();
      final playerRectBefore = game.playerMonsterComponent.toRect();
      // 相手の絵の右上の角 (右端 0.88w) より右の矩形と、自分の絵の左下の角 (下端 0.94h) より下の矩形
      final overlayRects = [
        const Rect.fromLTRB(360, 140, 393, 300),
        const Rect.fromLTRB(0, 510, 200, 532),
      ];
      game.updateOverlayRects(rects: overlayRects, battleLogRect: null);
      expect(game.opponentMonsterComponent.toRect(), opponentRectBefore);
      expect(game.playerMonsterComponent.toRect(), playerRectBefore);

      // 攻撃の前進の途中のように位置を動かしても、同じ並びの矩形 (別のリスト) では元の位置に戻さない
      game.opponentMonsterComponent.position += Vector2(10, 0);
      final movedPosition = game.opponentMonsterComponent.position.clone();
      game.updateOverlayRects(rects: [...overlayRects], battleLogRect: null);
      expect(game.opponentMonsterComponent.position, movedPosition);
    },
  );

  /// 393×394 は iPhone 17 (393×852) の負けた側の勝敗の画面のフィールド (#415 のスクリーンショットの実測)。
  /// 矩形は、上端に左右いっぱいのログの帯 (下端 119)、その下の左の相手の情報カード、右下の自分の情報カード (札は出ない高さ)。
  /// 高さの比率だけでは相手の絵の上端が 394 × 0.28 ≈ 110 で、帯の下端 119 より上に来る
  testWithGame<BattleFieldGame>(
    'ログの帯の下端が高さの 0.28 より下にある低いフィールドでは、相手の絵を帯の下に置き、2 体の絵をカードにも互いにも重ねない',
    createGame,
    (game) async {
      game.onGameResize(Vector2(393, 394));
      // 先頭がログの帯、残りが 2 枚の情報カード
      const coveringRects = [
        Rect.fromLTRB(20, 76, 373, 119),
        Rect.fromLTRB(20, 155, 210, 238),
        Rect.fromLTRB(183, 287, 373, 370),
      ];
      game.updateOverlayRects(
        rects: coveringRects.sublist(1),
        battleLogRect: coveringRects.first,
      );
      final opponentRect = game.opponentMonsterComponent.toRect();
      final playerRect = game.playerMonsterComponent.toRect();
      // 帯と絵の間はカードと絵の間と同じ 8 を空ける
      expect(opponentRect.top, 119 + 8);
      for (final monsterRect in [opponentRect, playerRect]) {
        for (final coveringRect in coveringRects) {
          expect(monsterRect.overlaps(coveringRect), isFalse);
        }
        expect(
          const Rect.fromLTWH(0, 0, 393, 394).intersect(monsterRect),
          monsterRect,
        );
      }
      expect(opponentRect.overlaps(playerRect), isFalse);
      expect(opponentRect.center.dx, greaterThan(game.size.x / 2));
      expect(playerRect.center.dx, lessThan(game.size.x / 2));
      // 被写体を見分けられる大きさ (battle_screen_test.dart の左右配置の下限 60px) を保つ
      expect(opponentRect.width, greaterThanOrEqualTo(60));
    },
  );

  /// 393×532 は勝った側と決着の前のフィールド。高さの 0.28 (約 149) がログの帯の下端 119 + 8 より下にある
  testWithGame<BattleFieldGame>(
    'ログの帯の下端が高さの 0.28 より上にあるフィールドでは、帯を受け取っても 2 体の絵を動かさず、帯だけが変わっても置き直さない',
    createGame,
    (game) async {
      game.onGameResize(Vector2(393, 532));
      const overlayRects = [
        Rect.fromLTRB(20, 201, 210, 284),
        Rect.fromLTRB(183, 425, 373, 508),
      ];
      game.updateOverlayRects(rects: overlayRects, battleLogRect: null);
      final opponentRectBefore = game.opponentMonsterComponent.toRect();
      final playerRectBefore = game.playerMonsterComponent.toRect();
      game.updateOverlayRects(
        rects: overlayRects,
        battleLogRect: const Rect.fromLTRB(20, 76, 373, 119),
      );
      expect(game.opponentMonsterComponent.toRect(), opponentRectBefore);
      expect(game.playerMonsterComponent.toRect(), playerRectBefore);

      // ログの文が 2 行に折り返して帯が伸びても、相手の絵の上端 (高さの 0.28) を越えない間は、攻撃の前進の途中の位置を元に戻さない
      game.opponentMonsterComponent.position += Vector2(10, 0);
      final movedPosition = game.opponentMonsterComponent.position.clone();
      game.updateOverlayRects(
        rects: overlayRects,
        battleLogRect: const Rect.fromLTRB(20, 76, 373, 139),
      );
      expect(game.opponentMonsterComponent.position, movedPosition);

      // 帯が相手の絵の上端を越えて伸びた時は、絵を帯の下へ置き直す
      game.updateOverlayRects(
        rects: overlayRects,
        battleLogRect: const Rect.fromLTRB(20, 76, 373, 159),
      );
      expect(game.opponentMonsterComponent.toRect().top, 159 + 8);
    },
  );

  // バトル画面は、ゲームの読み込みが終わる前のフレームでも矩形を渡す
  test('読み込みの前 (フィールドの大きさが決まる前) にログの帯の矩形を受け取っても失敗しない', () {
    expect(
      () => createGame().updateOverlayRects(
        rects: const [],
        battleLogRect: const Rect.fromLTRB(20, 76, 373, 119),
      ),
      returnsNormally,
    );
  });

  /// 500×200 は、帯を相手のカードの右に寄せた低いフィールド。帯の下端 56 と自分のカードの上端 90 の間に、
  /// 帯の下へ下げる時の下限の大きさの絵 (200 × 0.1 = 20) と間の 8 が入らない (入る限界は上端 92)。下げる前の絵 (上端 56) はカードにも帯にも重ならない
  testWithGame<BattleFieldGame>(
    'ログの帯と自分の情報カードの間に下限の大きさの絵が入らないフィールドでは、相手の絵を帯の下へ下げず、カードに重ねない',
    createGame,
    (game) async {
      game.onGameResize(Vector2(500, 200));
      const playerCardRect = Rect.fromLTRB(290, 90, 480, 176);
      const overlayRects = [Rect.fromLTRB(20, 16, 210, 102), playerCardRect];
      game.updateOverlayRects(rects: overlayRects, battleLogRect: null);
      final opponentRectBefore = game.opponentMonsterComponent.toRect();
      game.updateOverlayRects(
        rects: overlayRects,
        battleLogRect: const Rect.fromLTRB(218, 16, 480, 56),
      );
      expect(game.opponentMonsterComponent.toRect(), opponentRectBefore);
      expect(opponentRectBefore.top, closeTo(200 * 0.28, 0.001));
      expect(opponentRectBefore.overlaps(playerCardRect), isFalse);
    },
  );

  /// 自分のカードの上端ごとの、帯の下 (上端 64) に間の 8 を空けて入る絵の一辺。
  /// 92 は下限 (200 × 0.1 = 20) がちょうど入る境界、96 は下限と高さの 0.15 (30) の間 (#419 の重なっていた低さ)、104 は高さの 0.15 を越える
  for (final (playerCardTop, expectedArtSize) in const [
    (92.0, 20.0),
    (96.0, 24.0),
    (104.0, 32.0),
  ]) {
    testWithGame<BattleFieldGame>(
      'ログの帯と自分の情報カード (上端 $playerCardTop) の間に下限の大きさの絵が入るフィールドでは、相手の絵を帯の下へ下げ、間に入る大きさにする',
      createGame,
      (game) async {
        game.onGameResize(Vector2(500, 200));
        const battleLogRect = Rect.fromLTRB(218, 16, 480, 56);
        game.updateOverlayRects(
          rects: [
            const Rect.fromLTRB(20, 16, 210, 102),
            Rect.fromLTRB(290, playerCardTop, 480, playerCardTop + 86),
          ],
          battleLogRect: battleLogRect,
        );
        final opponentRect = game.opponentMonsterComponent.toRect();
        expect(opponentRect.top, 56 + 8);
        expect(opponentRect.height, closeTo(expectedArtSize, 0.001));
        // 絵とカードの間は 8 を空ける
        expect(
          opponentRect.bottom,
          lessThanOrEqualTo(playerCardTop - 8 + 0.001),
        );
        expect(opponentRect.overlaps(battleLogRect), isFalse);
        expect(
          opponentRect.overlaps(game.playerMonsterComponent.toRect()),
          isFalse,
        );
      },
    );
  }

  /// 360×225 は 360×640 の負けた側の勝敗の画面のフィールド (#419 の Web の画面のスクリーンショットから読んだ値)。
  /// 矩形は、左上の相手の情報カード、その右に寄せたログの帯 (文が 2 行で下端 76)、右下の自分の情報カード (上端 118)。
  /// 帯の下 (上端 84) と自分のカードの間に入る絵は 26 で、高さの 0.15 (33.75) に足りず、絵が高さの 0.28 (63) のまま帯に重なっていた
  testWithGame<BattleFieldGame>(
    '360×640 の負けた側の勝敗の画面のフィールドでは、相手の絵を帯の下に置き、2 体の絵を帯にもカードにも互いにも重ねない',
    createGame,
    (game) async {
      game.onGameResize(Vector2(360, 225));
      // 先頭がログの帯、残りが 2 枚の情報カード
      const coveringRects = [
        Rect.fromLTRB(218, 16, 340, 76),
        Rect.fromLTRB(20, 16, 210, 101),
        Rect.fromLTRB(150, 118, 340, 203),
      ];
      game.updateOverlayRects(
        rects: coveringRects.sublist(1),
        battleLogRect: coveringRects.first,
      );
      final opponentRect = game.opponentMonsterComponent.toRect();
      final playerRect = game.playerMonsterComponent.toRect();
      expect(opponentRect.top, 76 + 8);
      expect(opponentRect.height, closeTo(118 - 8 - 84, 0.001));
      for (final monsterRect in [opponentRect, playerRect]) {
        for (final coveringRect in coveringRects) {
          expect(monsterRect.overlaps(coveringRect), isFalse);
        }
        expect(
          const Rect.fromLTWH(0, 0, 360, 225).intersect(monsterRect),
          monsterRect,
        );
      }
      expect(opponentRect.overlaps(playerRect), isFalse);
    },
  );

  /// 393×308 は、英語の負けた側の勝敗の画面で勝敗のパネルが高く、フィールドがさらに縮んだ時の低さ
  /// (帯の下端 135 と自分のカードの上端 169 は、PR #418 の widget test の 393×852・英語の実測。CI の run 44883453641)。
  /// 帯の下 (上端 143) と自分のカード (間の 8 を空けて 161) の間に入る絵は 18 で、下限 (308 × 0.1 = 30.8) に足りない。
  /// 下げないと、高さの 0.28 (約 86) に置いた絵 (一辺 約 75) が帯 (76〜135) に重なる (#431)
  testWithGame<BattleFieldGame>(
    'ログの帯と自分の情報カードの間に下限の大きさの絵が入らなくても、高さの 0.28 の絵が帯に重なるフィールドでは、相手の絵を帯の下へ下げて間に入る大きさにする',
    createGame,
    (game) async {
      game.onGameResize(Vector2(393, 308));
      const battleLogRect = Rect.fromLTRB(20, 76, 373, 135);
      const playerCardRect = Rect.fromLTRB(183, 169, 373, 284);
      game.updateOverlayRects(rects: [playerCardRect], battleLogRect: null);
      // 帯を渡す前は高さの 0.28 にあり、帯の矩形に重なる位置であること (この前提が崩れると、下の確認は下げなくても通る)
      expect(
        game.opponentMonsterComponent.toRect().overlaps(battleLogRect),
        isTrue,
      );
      game.updateOverlayRects(
        rects: [playerCardRect],
        battleLogRect: battleLogRect,
      );
      final opponentRect = game.opponentMonsterComponent.toRect();
      final playerRect = game.playerMonsterComponent.toRect();
      expect(opponentRect.top, 135 + 8);
      expect(opponentRect.height, closeTo(169 - 8 - 143, 0.001));
      for (final monsterRect in [opponentRect, playerRect]) {
        expect(monsterRect.overlaps(battleLogRect), isFalse);
        expect(monsterRect.overlaps(playerCardRect), isFalse);
        expect(
          const Rect.fromLTWH(0, 0, 393, 308).intersect(monsterRect),
          monsterRect,
        );
      }
      expect(opponentRect.overlaps(playerRect), isFalse);
    },
  );

  /// 高さ 150 のフィールドで帯の下 (135 + 8 = 143) まで下げると、自分の下端 (高さの 0.94 = 141) より下になり、2 体の絵の入る所が無い。
  /// 高さの 0.28 (42) に置いた絵 (一辺 45) は帯 (76〜135) に重なる
  testWithGame<BattleFieldGame>(
    'ログの帯の下に 2 体の絵の入る所が無いほど低いフィールドでは、絵を帯に重ねず、2 体とも描かない',
    createGame,
    (game) async {
      game.onGameResize(Vector2(393, 150));
      const battleLogRect = Rect.fromLTRB(20, 76, 373, 135);
      game.updateOverlayRects(rects: const [], battleLogRect: null);
      expect(
        game.opponentMonsterComponent.toRect().overlaps(battleLogRect),
        isTrue,
      );
      game.updateOverlayRects(rects: const [], battleLogRect: battleLogRect);
      for (final component in [
        game.opponentMonsterComponent,
        game.playerMonsterComponent,
      ]) {
        expect(component.toRect().overlaps(battleLogRect), isFalse);
        expect(component.size.x, 0);
        expect(component.size.y, 0);
      }
    },
  );

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
        defenderSide: BattleSideID.opponent,
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
    game.hit(defenderSide: BattleSideID.player, effect: null);
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
    Future<void> applySteelSpriteSheet({required BattleFieldGame game}) async {
      final spriteSheetImage = await createArtImage(width: 20, height: 16);
      addTearDown(spriteSheetImage.dispose);
      game.applyMoveEffectSpriteSheet(
        effectID: steelEffect.id,
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
      game.hit(defenderSide: BattleSideID.opponent, effect: steelEffect);
      await game.ready();
      expect(game.children.whereType<ParticleSystemComponent>(), hasLength(1));
      expect(game.children.whereType<SpriteAnimationComponent>(), isEmpty);
    });

    testWithGame<BattleFieldGame>(
      '被弾すると、被弾した絵の中心に合わせて単発で再生し、被弾の時間で消える',
      createGame,
      (game) async {
        game.onGameResize(Vector2(390, 500));
        await applySteelSpriteSheet(game: game);
        game.hit(defenderSide: BattleSideID.opponent, effect: steelEffect);
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
        await applySteelSpriteSheet(game: game);

        /// [defenderSide] の側に [steelEffect] の被弾を発行し、新しく出たエフェクトの水平方向の scale を返す。
        /// 1 なら素材の向きのまま、-1 なら左右を反転して描く。
        /// 呼ぶたびにエフェクトが [game] に 1 つ足される。
        Future<double> horizontalScaleOfNewEffect({
          required BattleSideID defenderSide,
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
          await horizontalScaleOfNewEffect(defenderSide: BattleSideID.opponent),
          1,
        );
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideID.player),
          -1,
        );

        // 低くて幅の狭い画面の配置: 相手が左、自分が右
        game.onGameResize(Vector2(600, 103));
        game.updateMonsterArtArea(area: const Rect.fromLTRB(218, 16, 382, 102));
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideID.opponent),
          -1,
        );
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideID.player),
          1,
        );

        // 左右配置のバトル: 自分が左、相手が右
        game.updateMonsterArtArea(
          area: const Rect.fromLTRB(16, 16, 500, 102),
          placesPlayerOnLeft: true,
        );
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideID.opponent),
          1,
        );
        expect(
          await horizontalScaleOfNewEffect(defenderSide: BattleSideID.player),
          -1,
        );
      },
    );

    testWithGame<BattleFieldGame>(
      '対応の無いエフェクトとわるあがきは、シートがあっても今までどおり描く',
      createGame,
      (game) async {
        await applySteelSpriteSheet(game: game);
        game.hit(
          defenderSide: BattleSideID.opponent,
          effect: const MoveEffect(
            id: 'generated_effect',
            displayName: 'その場で作ったエフェクト',
            kind: 'particle',
            colorHex: '#2196F3',
          ),
        );
        game.hit(defenderSide: BattleSideID.player, effect: null);
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
      'master のシートで描くエフェクトをすべて読み、読めないシートとパーティクルのエフェクトは飛ばして残りを描く',
      createGame,
      (game) async {
        // testWithGame は binding を初期化せず、rootBundle からアセットを読むのに要るため
        TestWidgetsFlutterBinding.ensureInitialized();
        final spriteSheetEffects = [
          for (final effect in sampleData.definitions.effects)
            if (effect.spriteSheet != null) effect,
        ];
        expect(spriteSheetEffects, isNotEmpty);
        await loadMoveEffectSpriteSheets(
          game: game,
          effects: [
            ...sampleData.definitions.effects,
            const MoveEffect(
              id: 'not_bundled',
              displayName: '同梱していないシート',
              kind: 'spriteSheet',
              colorHex: '#FFFFFF',
              spriteSheet: 'not-bundled',
            ),
          ],
          assetBundle: rootBundle,
        );
        for (final effect in spriteSheetEffects) {
          game.hit(defenderSide: BattleSideID.opponent, effect: effect);
        }
        game.hit(
          defenderSide: BattleSideID.opponent,
          effect: const MoveEffect(
            id: 'not_bundled',
            displayName: '同梱していないシート',
            kind: 'spriteSheet',
            colorHex: '#FFFFFF',
            spriteSheet: 'not-bundled',
          ),
        );
        game.hit(
          defenderSide: BattleSideID.opponent,
          effect: sampleData.definitions.effectByID(effectID: 'water_particle'),
        );
        await game.ready();
        final components = game.children.whereType<SpriteAnimationComponent>();
        expect(components, hasLength(spriteSheetEffects.length));
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
          // 合わせる点はコマの中 (見える範囲の中心を測って書いた値)
          expect(component.anchor.x, inInclusiveRange(0, 1));
          expect(component.anchor.y, inInclusiveRange(0, 1));
        }
        expect(
          game.children.whereType<ParticleSystemComponent>(),
          hasLength(2),
        );
      },
    );

    test('シートの JSON の見える範囲の中心を Anchor にし、無ければコマの中心にする', () {
      expect(
        visibleCenterAnchorOf(
          spriteSheetJson: {
            'meta': {
              'snapmon': {
                'visibleCenter': [0.25, 0.75],
              },
            },
          },
        ),
        const Anchor(0.25, 0.75),
      );
      expect(
        visibleCenterAnchorOf(spriteSheetJson: {'meta': <String, dynamic>{}}),
        Anchor.center,
      );
    });

    testWithGame<BattleFieldGame>(
      'JSON は読めて PNG を decode できないシートは、未処理のエラーを出さずキャッシュにも残さずパーティクルのままにする',
      createGame,
      (game) async {
        // testWithGame は binding を初期化せず、画像の decode に要るため
        TestWidgetsFlutterBinding.ensureInitialized();
        await loadMoveEffectSpriteSheets(
          game: game,
          effects: const [
            MoveEffect(
              id: 'water_particle',
              displayName: '壊れた PNG',
              kind: 'spriteSheet',
              colorHex: '#2196F3',
              spriteSheet: 'broken-png',
            ),
          ],
          assetBundle: _BrokenPngAssetBundle(),
        );
        expect(game.images.containsKey('move_effects/broken-png.png'), isFalse);
        game.hit(
          defenderSide: BattleSideID.opponent,
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
    game.faint(side: BattleSideID.opponent);
    expect(game.opponentMonsterComponent.isVisible, isFalse);

    final nextMonster = sampleData.monsters[2];
    game.switchIn(side: BattleSideID.opponent, monster: nextMonster);
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
    '切り出した画像が届くまでは画像を持つモンスターを描かず、届いたらそのパスのモンスターだけを Sprite で描く',
    createGame,
    (game) async {
      final player = game.playerMonsterComponent..size = Vector2(100, 100);
      final opponent = game.opponentMonsterComponent..size = Vector2(100, 100);
      expect(player.artSprite, isNull);
      // 画像を持つ自分のモンスターは、届くまで仮の絵も描かない (#211)
      expect(renderInvocations(component: player), isEmpty);

      final artImage = await createArtImage(width: 8, height: 8);
      addTearDown(artImage.dispose);
      game.applyArtImage(artPath: playerArtPath, artImage: artImage);

      expect(player.artSprite?.image, artImage);
      expect(
        renderInvocations(component: player).map((call) => call.memberName),
        contains(#drawImageRect),
      );
      // 画像を持つ相手 (見本の同梱の画像) は、届くまで描かない
      expect(opponent.monster.artPath, isNotNull);
      expect(opponent.artSprite, isNull);
      expect(renderInvocations(component: opponent), isEmpty);

      // 画像を持たないモンスターは仮の絵 (角丸の体) を描く
      final sampleMonster = sampleData.monsters[2];
      game.switchIn(
        side: BattleSideID.opponent,
        monster: OwnedMonster(
          definition: sampleMonster.definition,
          level: sampleMonster.level,
          actionCardMoveIDs: const [],
          selectedMoveIDs: null,
          artPath: null,
          definitionIDs: sampleMonster.definitionIDs,
          decoration: null,
          decorationVersion: null,
        ),
      );
      final placeholderInvocations = renderInvocations(
        component: game.opponentMonsterComponent..size = Vector2(100, 100),
      ).map((call) => call.memberName);
      expect(placeholderInvocations, contains(#drawRRect));
      expect(placeholderInvocations, isNot(contains(#drawImageRect)));
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
      side: BattleSideID.player,
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
      side: BattleSideID.player,
      monster: ownedMonsterWithArt(
        monster: sampleData.monsters[2],
        artPath: playerArtPath,
        sourcePhotoReference: 'users/uid-1/photos/request-2',
      ),
    );
    expect(game.playerMonsterComponent.artSprite?.image, artImage);

    game.switchIn(
      side: BattleSideID.player,
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
