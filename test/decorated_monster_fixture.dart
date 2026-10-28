import 'package:snapmon/domain/monster/monster_decoration.dart';
import 'package:snapmon/features/dex/owned_monster.dart';

/// [monster] を、切り出した画像 [artPath] と描画の版 [decorationVersion] の装飾 [decoration] を持つ 1 体にしたもの。
/// 見本のモンスターは切り出した画像も装飾も持たないため、装飾を描く経路の確認に使う。
OwnedMonster decoratedMonster({
  required OwnedMonster monster,
  required String artPath,
  required MonsterDecoration decoration,
  required int decorationVersion,
}) => OwnedMonster(
  definition: monster.definition,
  level: monster.level,
  artPath: artPath,
  definitionIds: monster.definitionIds,
  decoration: decoration,
  decorationVersion: decorationVersion,
);

/// 装飾のパラメータを、指定した項目だけ変えて作る。指定しない項目は、目と口だけが被写体の上に乗る値にした
/// (手足・オーラの重なりで目の画素の数え方が変わらないよう、手足無し・口無しにする)。
MonsterDecoration testDecoration({
  MonsterEyeStyle eyeStyle = MonsterEyeStyle.dot,
  MonsterMouthStyle mouthStyle = MonsterMouthStyle.none,
  MonsterLimbStyle limbStyle = MonsterLimbStyle.none,
  MonsterAuraStyle auraStyle = MonsterAuraStyle.soft,
  double eyeCenterX = 0.5,
  double eyeCenterY = 0.4,
  double eyeScale = 0.15,
  String outlineColorHex = '#FF0000',
}) => MonsterDecoration(
  eyeStyle: eyeStyle,
  mouthStyle: mouthStyle,
  limbStyle: limbStyle,
  auraStyle: auraStyle,
  eyeCenterX: eyeCenterX,
  eyeCenterY: eyeCenterY,
  eyeScale: eyeScale,
  outlineColorHex: outlineColorHex,
);
