import 'dart:convert';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show decodeImageFromList;
import 'package:flutter/services.dart';

import '../../domain/master/move_effect.dart';
import 'battle_field_game.dart';

/// [effects] のうちスプライトシートで描くエフェクト (`spriteSheet` を持つ定義。master の版 9 から。#224) のシートを読み、
/// [game] がエフェクトを描けるようにする。パーティクルで描くエフェクトとその場で作った定義は読まない。
/// 読めないシートはログに残して飛ばし、そのエフェクトはパーティクルのままにする (絵のためにバトルを止めないため)。
/// 読めた画像は Flame の全体のキャッシュ ([BattleFieldGame.images]) に残り、次のバトルでは読み直さない。読めなかった画像は残さず、次のバトルで読み直す。
/// シートの JSON の `meta.snapmon.visibleCenter` (scripts/move_effects/postprocess_sprite_sheets.py が書く、見える範囲の中心) を
/// 被弾したモンスターの中心に合わせる点にし、無ければコマの中心にする。
Future<void> loadMoveEffectSpriteSheets({
  required BattleFieldGame game,
  required Iterable<MoveEffect> effects,
  required AssetBundle assetBundle,
}) => Future.wait([
  for (final effect in effects)
    if (effect.spriteSheet case final assetName?)
      () async {
        try {
          final spriteSheetJson =
              jsonDecode(
                    await assetBundle.loadString(
                      'assets/images/move_effects/$assetName.json',
                    ),
                  )
                  as Map<String, dynamic>;
          game.applyMoveEffectSpriteSheet(
            effectID: effect.id,
            spriteSheetJson: spriteSheetJson,
            spriteSheetImage: await _loadSpriteSheetImage(
              game: game,
              assetName: assetName,
              assetBundle: assetBundle,
            ),
            visibleCenterAnchor: visibleCenterAnchorOf(
              spriteSheetJson: spriteSheetJson,
            ),
          );
        } catch (error) {
          debugPrint('$assetName: $error');
        }
      }(),
]);

/// シートの JSON [spriteSheetJson] の `meta.snapmon.visibleCenter` を Anchor にして返す。無ければコマの中心。
Anchor visibleCenterAnchorOf({required Map<String, dynamic> spriteSheetJson}) {
  if ((spriteSheetJson['meta'] as Map<String, dynamic>?)?['snapmon'] case {
    'visibleCenter': [final num x, final num y],
  }) {
    return Anchor(x.toDouble(), y.toDouble());
  }
  return Anchor.center;
}

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
