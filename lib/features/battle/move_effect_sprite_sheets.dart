import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'battle_field_game.dart';

/// 技のエフェクトを描くスプライトシート 1 枚。
/// [assetName] は `assets/images/move_effects/` のファイル名 (拡張子なし)。
/// [visibleCenterAnchor] はコマの中で全コマの見える範囲を合わせた矩形の中心で、
/// PixelFX の pivot は足元の原点で発光の位置と一致しないため、被弾したモンスターの中心にこの点を合わせる。
typedef MoveEffectSpriteSheet = ({
  String assetName,
  Anchor visibleCenterAnchor,
});

/// スプライトシートで描く技のエフェクト (master の effects の id ごと)。ここに無いエフェクトとその場で作った定義はパーティクルで描く。
/// 素材は assets/CREDITS.md、割り当ての理由は documents/DIRECTION.md「決めたこと」(2026-11-04)。
/// [MoveEffectSpriteSheet.visibleCenterAnchor] はアルファ 32 以上の画素の範囲を測った値。
const Map<String, MoveEffectSpriteSheet> moveEffectSpriteSheetsByEffectId = {
  'heat_particle': (
    assetName: 'hit-spark',
    visibleCenterAnchor: Anchor(0.581, 0.5),
  ),
  'metal_particle': (
    assetName: 'sword-slash',
    visibleCenterAnchor: Anchor(0.482, 0.466),
  ),
  'electric_particle': (
    assetName: 'zap-hit',
    visibleCenterAnchor: Anchor(0.413, 0.5),
  ),
};

/// [spriteSheetsByEffectId] のシートを読み、[game] がエフェクトを描けるようにする。
/// 読めないシートはログに残して飛ばし、そのエフェクトはパーティクルのままにする (絵のためにバトルを止めないため)。
/// 画像は Flame の全体のキャッシュ ([BattleFieldGame.images]) に残り、次のバトルでは読み直さない。
Future<void> loadMoveEffectSpriteSheets({
  required BattleFieldGame game,
  required Map<String, MoveEffectSpriteSheet> spriteSheetsByEffectId,
  required AssetBundle assetBundle,
}) => Future.wait([
  for (final MapEntry(key: effectId, value: spriteSheet)
      in spriteSheetsByEffectId.entries)
    () async {
      try {
        game.applyMoveEffectSpriteSheet(
          effectId: effectId,
          spriteSheetImage: await game.images.load(
            'move_effects/${spriteSheet.assetName}.png',
          ),
          spriteSheetJson:
              jsonDecode(
                    await assetBundle.loadString(
                      'assets/images/move_effects/${spriteSheet.assetName}.json',
                    ),
                  )
                  as Map<String, dynamic>,
          visibleCenterAnchor: spriteSheet.visibleCenterAnchor,
        );
      } catch (error) {
        debugPrint('${spriteSheet.assetName}: $error');
      }
    }(),
]);
