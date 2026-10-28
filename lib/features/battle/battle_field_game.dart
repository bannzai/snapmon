import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
// 技のエフェクトの定義 (MoveEffect) と名前が重なるため、Flame の effects には接頭辞を付ける
import 'package:flame/effects.dart' as flame_effects;
import 'package:flame/game.dart';
import 'package:flame/particles.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/master/move_effect.dart';
import '../../domain/monster/monster_definition.dart';
import '../../theme/snapmon_colors.dart';
import '../../widgets/placeholder_monster_painting.dart';

/// 攻撃の前進にかける時間 (秒)。往復でこの 2 倍になる。技の演出 1 回を 1 秒前後に収め、ターンの待ちを短くするため。
const double attackLungeSeconds = 0.15;

/// 被弾の点滅とパーティクルを出している時間 (秒)。HP バーが減りきる時間 (battle_screen.dart) と揃える。
const double hitReactionSeconds = 0.5;

/// 1 回の被弾で出すパーティクルの数。属性の色が見分けられる量で、低い性能の端末でも重くならない数にした。
const int _hitParticleCount = 24;

/// パーティクルが飛び散る速さの上限 (論理 px / 秒)。モンスターの絵 (縦長の画面で幅の約 4 割) の外に少しはみ出す程度にした。
const double _hitParticleMaximumSpeed = 180;

/// パーティクルが落ちる加速度 (論理 px / 秒²)。飛び散った後に下へ流れて消える見え方にするため。
const double _hitParticleGravity = 240;

/// 点滅の速さ (1 秒あたりの表示と非表示の切り替えの回数)。被弾の間に 5 回ほど点滅させるため。
const double _blinkTogglesPerSecond = 20;

/// [effect] の主色 (`#RRGGBB`) を返す。
Color moveEffectColor({required MoveEffect effect}) =>
    Color(0xFF000000 | int.parse(effect.colorHex.substring(1), radix: 16));

/// バトルのフィールド。相手のモンスターを右上、自分のモンスターを左下に描き (DIRECTION.md「デザインの方向」の「相手が上・自分が下」)、
/// 攻撃の前進・被弾の点滅・技のエフェクト (属性ごとのパーティクル)・倒れる・交代を見せる。
/// いつ何を見せるかはバトル画面 (battle_screen.dart) がバトルのログから決め、このゲームはバトルの計算を持たない。
class BattleFieldGame extends FlameGame {
  /// [playerMonster] と [opponentMonster] を場に出したフィールドを作る。
  /// [playerArtPath]・[opponentArtPath] はそれぞれの切り出した被写体の画像の Storage のパス (見本のモンスターは null)。
  BattleFieldGame({
    required MonsterDefinition playerMonster,
    required String? playerArtPath,
    required MonsterDefinition opponentMonster,
    required String? opponentArtPath,
  }) : playerMonsterComponent = MonsterComponent(
         definition: playerMonster,
         artPath: playerArtPath,
         artSprite: null,
       ),
       opponentMonsterComponent = MonsterComponent(
         definition: opponentMonster,
         artPath: opponentArtPath,
         artSprite: null,
       );

  /// 自分の場のモンスター。交代 ([switchIn]) で入れ替わる。
  MonsterComponent playerMonsterComponent;

  /// 相手の場のモンスター。交代 ([switchIn]) で入れ替わる。
  MonsterComponent opponentMonsterComponent;

  /// 読み込めた切り出した被写体の画像の Sprite (Storage のパスごと)。後から場に出るモンスター ([switchIn]) にも使う。
  /// 画像の持ち主 (dispose する側) はバトル画面で、このゲームは参照するだけ。
  final Map<String, Sprite> _artSpritesByPath = {};

  /// パーティクルの飛ぶ向きと速さの乱数。見た目だけに使い、バトルの結果に効かないため seed を固定しない。
  final math.Random _particleRandom = math.Random();

  /// フィールドの上端から相手の情報カード (バトル画面が Flutter で重ねる) の下端までの高さ。
  /// 自分のモンスターの絵の上端をこれより下に置く。バトル画面が測って渡すまでは 0 (カードを考えない)
  double _opponentStatusCardBottom = 0;

  /// 相手の情報カードの下端の高さ [bottom] を受け取り、変わっていれば 2 体を置き直す。同じ値なら何もしない。
  void updateOpponentStatusCardBottom({required double bottom}) {
    if (bottom == _opponentStatusCardBottom) {
      return;
    }
    _opponentStatusCardBottom = bottom;
    if (isLoaded) {
      _layout();
    }
  }

  @override
  Color backgroundColor() => SnapmonColors.surfaceRaised;

  @override
  Future<void> onLoad() async {
    add(_GroundComponent());
    add(opponentMonsterComponent);
    add(playerMonsterComponent);
    _layout();
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    if (isLoaded) {
      _layout();
    }
  }

  /// [artPath] の切り出した被写体の画像 [artImage] を受け取り、そのパスのモンスターを画像で描くようにする。
  /// 読み込みはバトル画面が非同期に行うため、届くまでと読めなかった時は仮の絵のまま描く。
  void applyArtImage({required String artPath, required Image artImage}) {
    final artSprite = _artSpritesByPath[artPath] = Sprite(artImage);
    for (final component in [
      playerMonsterComponent,
      opponentMonsterComponent,
    ]) {
      if (component.artPath == artPath) {
        component.artSprite = artSprite;
      }
    }
  }

  /// [side] の場のモンスター。
  MonsterComponent monsterComponentOf({required BattleSideId side}) =>
      switch (side) {
        BattleSideId.player => playerMonsterComponent,
        BattleSideId.opponent => opponentMonsterComponent,
      };

  /// [attackerSide] のモンスターを相手の方へ前進させて戻す ([attackLungeSeconds] の往復)。
  void lunge({required BattleSideId attackerSide}) {
    final attacker = monsterComponentOf(side: attackerSide);
    final defender = monsterComponentOf(side: _otherSide(side: attackerSide));
    attacker.add(
      flame_effects.MoveEffect.by(
        (defender.center - attacker.center)..scale(0.15),
        flame_effects.EffectController(
          duration: attackLungeSeconds,
          reverseDuration: attackLungeSeconds,
        ),
      ),
    );
  }

  /// [defenderSide] のモンスターを [hitReactionSeconds] の間点滅させ、[effect] があればその色のパーティクルを散らす。
  /// わるあがき (属性の無い攻撃) は [effect] を null にして点滅だけにする。
  void hit({required BattleSideId defenderSide, required MoveEffect? effect}) {
    final defender = monsterComponentOf(side: defenderSide)
      ..blink(seconds: hitReactionSeconds);
    if (effect == null) {
      return;
    }
    final paint = Paint()..color = moveEffectColor(effect: effect);
    add(
      ParticleSystemComponent(
        position: defender.center,
        particle: Particle.generate(
          count: _hitParticleCount,
          lifespan: hitReactionSeconds,
          generator: (_) => AcceleratedParticle(
            speed: Vector2(
              _particleRandom.nextDouble() * 2 - 1,
              _particleRandom.nextDouble() * 2 - 1,
            )..scale(_hitParticleMaximumSpeed),
            acceleration: Vector2(0, _hitParticleGravity),
            child: CircleParticle(
              radius: 3 + _particleRandom.nextDouble() * 3,
              paint: paint,
            ),
          ),
        ),
      ),
    );
  }

  /// [side] のモンスターを倒れた (描かない) 状態にする。
  void faint({required BattleSideId side}) {
    monsterComponentOf(side: side).isVisible = false;
  }

  /// [side] の場のモンスターを [definition] (切り出した被写体の画像は [artPath]。見本のモンスターは null) に入れ替える。
  void switchIn({
    required BattleSideId side,
    required MonsterDefinition definition,
    required String? artPath,
  }) {
    final replacement = MonsterComponent(
      definition: definition,
      artPath: artPath,
      artSprite: _artSpritesByPath[artPath],
    );
    monsterComponentOf(side: side).removeFromParent();
    switch (side) {
      case BattleSideId.player:
        playerMonsterComponent = replacement;
      case BattleSideId.opponent:
        opponentMonsterComponent = replacement;
    }
    add(replacement);
    _layout();
  }

  /// 画面の大きさに合わせて 2 体の位置と大きさを決める。比率はモック (Battle.dc.html) の配置から取った。
  void _layout() {
    // 高さの 0.3 は、相手の下端 (0.28h + m) が自分の上端 (0.94h - 1.15m) を越えない上限 m ≤ 0.66h / 2.15 ≈ 0.307h から取った。
    // 縦長のスマホでは幅の 0.4 の方が小さく、モックの大きさのまま描く。
    // 決着の後の勝敗のパネルでフィールドが低くなった時は、自分の上端 (0.94h - 1.15m) が相手の情報カードの下端を越えない大きさに抑える
    final monsterSize = [
      size.x * 0.4,
      size.y * 0.3,
      (size.y * 0.94 - _opponentStatusCardBottom) / 1.15,
    ].reduce(math.min).clamp(0.0, double.infinity);
    opponentMonsterComponent
      ..size = Vector2.all(monsterSize)
      ..position = Vector2(size.x * 0.88 - monsterSize, size.y * 0.28);
    playerMonsterComponent
      ..size = Vector2.all(monsterSize * 1.15)
      ..position = Vector2(
        size.x * 0.08,
        size.y - monsterSize * 1.15 - size.y * 0.06,
      );
  }
}

/// [side] の相手の陣営を返す。
BattleSideId _otherSide({required BattleSideId side}) => switch (side) {
  BattleSideId.player => BattleSideId.opponent,
  BattleSideId.opponent => BattleSideId.player,
};

/// 地面 (フィールドの下 46%)。
class _GroundComponent extends Component with HasGameReference<FlameGame> {
  static final Paint _paint = Paint()..color = SnapmonColors.battleGround;

  @override
  void render(Canvas canvas) {
    final size = game.size;
    canvas.drawRect(
      Rect.fromLTWH(0, size.y * 0.54, size.x, size.y * 0.46),
      _paint,
    );
  }
}

/// 場のモンスターを描く部品。切り出した被写体の画像 ([artImage]) があれば縦横比を保って枠に収めて描き、
/// 無ければ (見本のモンスター・読み込み中・読み込みの失敗) 仮の絵を描く。
/// 装飾 (目・手足・オーラ・輪郭線) は図鑑のカード (MonsterArt) と同じくまだ描かない。
class MonsterComponent extends PositionComponent with HasVisibility {
  /// [definition] のモンスターを描く部品を作る。
  MonsterComponent({
    required this.definition,
    required this.artPath,
    required this.artSprite,
  });

  /// 描くモンスター。
  final MonsterDefinition definition;

  /// 切り出した被写体の画像の Storage のパス。見本のモンスターは null。
  final String? artPath;

  /// [artPath] の画像の Sprite。null の間は仮の絵を描く。
  Sprite? artSprite;

  /// 点滅の残り時間 (秒)。0 なら点滅していない。
  double _blinkRemainingSeconds = 0;

  /// 点滅しているか。
  bool get isBlinking => _blinkRemainingSeconds > 0;

  /// [seconds] の間、表示と非表示を切り替えて点滅させる。倒れて非表示のモンスターは点滅させない。
  void blink({required double seconds}) {
    if (isVisible) {
      _blinkRemainingSeconds = seconds;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isBlinking) {
      return;
    }
    _blinkRemainingSeconds = math.max(0, _blinkRemainingSeconds - dt);
    _isHiddenByBlink =
        isBlinking &&
        (_blinkRemainingSeconds * _blinkTogglesPerSecond).floor().isOdd;
  }

  /// 点滅で今のフレームを描かないか。倒れた時の非表示 ([isVisible]) とは別に持ち、点滅の後に表示へ戻す。
  bool _isHiddenByBlink = false;

  @override
  void render(Canvas canvas) {
    if (_isHiddenByBlink) {
      return;
    }
    final sprite = artSprite;
    if (sprite == null) {
      paintPlaceholderMonster(
        canvas: canvas,
        size: Size(size.x, size.y),
        definition: definition,
      );
      return;
    }
    // 切り出した画像は被写体ごとに縦横比が違うため、引き伸ばさずに枠に収めて中央に置く (図鑑のカードの BoxFit.contain と同じ)
    final drawSize =
        sprite.srcSize *
        math.min(size.x / sprite.srcSize.x, size.y / sprite.srcSize.y);
    sprite.render(canvas, position: (size - drawSize) / 2, size: drawSize);
  }
}
