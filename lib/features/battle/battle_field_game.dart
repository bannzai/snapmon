import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

import '../../domain/monster/monster_definition.dart';
import '../../theme/snapmon_colors.dart';
import '../../widgets/placeholder_monster_painting.dart';

/// バトルのフィールド。相手のモンスターを右上、自分のモンスターを左下に描く
/// (DIRECTION.md「デザインの方向」の「相手が上・自分が下」)。技のエフェクト (#15) もこのゲームに足す。
class BattleFieldGame extends FlameGame {
  /// [playerMonster] と [opponentMonster] を場に出したフィールドを作る。
  BattleFieldGame({
    required MonsterDefinition playerMonster,
    required MonsterDefinition opponentMonster,
  }) : playerMonsterComponent = PlaceholderMonsterComponent(
         definition: playerMonster,
       ),
       opponentMonsterComponent = PlaceholderMonsterComponent(
         definition: opponentMonster,
       );

  /// 自分の場のモンスター。
  final PlaceholderMonsterComponent playerMonsterComponent;

  /// 相手の場のモンスター。
  final PlaceholderMonsterComponent opponentMonsterComponent;

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

  /// 画面の大きさに合わせて 2 体の位置と大きさを決める。比率はモック (Battle.dc.html) の配置から取った。
  void _layout() {
    final monsterSize = size.x * 0.4;
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

/// モンスターの仮の絵を描く部品。AI 生成のイラスト (#13) が入ったら画像の部品に差し替える。
class PlaceholderMonsterComponent extends PositionComponent {
  /// [definition] のモンスターを描く部品を作る。
  PlaceholderMonsterComponent({required this.definition});

  /// 描くモンスター。
  final MonsterDefinition definition;

  @override
  void render(Canvas canvas) => paintPlaceholderMonster(
    canvas: canvas,
    size: Size(size.x, size.y),
    definition: definition,
  );
}
