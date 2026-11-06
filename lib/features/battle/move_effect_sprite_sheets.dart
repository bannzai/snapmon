import 'dart:convert';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show decodeImageFromList;
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
  'fire_particle': (
    assetName: 'hit-spark',
    visibleCenterAnchor: Anchor(0.581, 0.5),
  ),
  'steel_particle': (
    assetName: 'sword-slash',
    visibleCenterAnchor: Anchor(0.482, 0.466),
  ),
  'thunder_particle': (
    assetName: 'zap-hit',
    visibleCenterAnchor: Anchor(0.413, 0.5),
  ),
};

/// [spriteSheetsByEffectId] のシートを読み、[game] がエフェクトを描けるようにする。
/// 読めないシートはログに残して飛ばし、そのエフェクトはパーティクルのままにする (絵のためにバトルを止めないため)。
/// 読めた画像は Flame の全体のキャッシュ ([BattleFieldGame.images]) に残り、次のバトルでは読み直さない。読めなかった画像は残さず、次のバトルで読み直す。
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
          spriteSheetJson:
              jsonDecode(
                    await assetBundle.loadString(
                      'assets/images/move_effects/${spriteSheet.assetName}.json',
                    ),
                  )
                  as Map<String, dynamic>,
          spriteSheetImage: await _loadSpriteSheetImage(
            game: game,
            assetName: spriteSheet.assetName,
            assetBundle: assetBundle,
          ),
          visibleCenterAnchor: spriteSheet.visibleCenterAnchor,
        );
      } catch (error) {
        debugPrint('${spriteSheet.assetName}: $error');
      }
    }(),
]);

/// `assets/images/move_effects/[assetName].png` の画像を返す。キャッシュに無ければ [assetBundle] から読んでキャッシュに足す。
/// 読み込みか decode に失敗すると throw し、キャッシュには何も足さない。
/// Flame の images.load を使わないのは、失敗した読み込みをキャッシュに残し、catch してもゾーンの未処理のエラーとしても報告するため。
Future<Image> _loadSpriteSheetImage({
  required BattleFieldGame game,
  required String assetName,
  required AssetBundle assetBundle,
}) async {
  final cacheKey = 'move_effects/$assetName.png';
  if (game.images.containsKey(cacheKey)) {
    return game.images.fromCache(cacheKey);
  }
  final image = await decodeImageFromList(
    (await assetBundle.load(
      'assets/images/move_effects/$assetName.png',
    )).buffer.asUint8List(),
  );
  // decode の間に別のバトルの読み込みが同じ画像を足していたら、そちらを使う (add は前の画像を dispose し、使っている画像が壊れるため)
  if (game.images.containsKey(cacheKey)) {
    image.dispose();
    return game.images.fromCache(cacheKey);
  }
  game.images.add(cacheKey, image);
  return image;
}
