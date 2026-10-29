import 'package:snapmon/domain/monster/monster_decoration.dart';
import 'package:snapmon/features/dex/owned_monster.dart';

/// [monster] を、切り出した画像 [artPath] と描画の版 [decorationVersion] の装飾 [decoration] を持つ 1 体にしたもの。
/// 見本のモンスターは切り出した画像も装飾も持たないため、装飾を保存しているモンスターでも装飾を描かないことの確認に使う。
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

/// 手足・オーラ・目・口のすべてを持つ装飾のパラメータ。どの部品も描かれないことを確かめるため、形を持たない値 (none) を避けた。
MonsterDecoration testDecoration() => const MonsterDecoration(
  eyeStyle: MonsterEyeStyle.round,
  mouthStyle: MonsterMouthStyle.smile,
  limbStyle: MonsterLimbStyle.stubby,
  auraStyle: MonsterAuraStyle.soft,
  eyeCenterX: 0.5,
  eyeCenterY: 0.4,
  eyeScale: 0.3,
  outlineColorHex: '#FF0000',
);
