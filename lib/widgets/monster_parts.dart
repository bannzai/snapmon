import 'package:flutter/material.dart';

import '../domain/master/master_data.dart';
import '../domain/monster/monster_definition.dart';
import '../features/dex/owned_monster.dart';
import '../theme/snapmon_colors.dart';
import '../theme/snapmon_radii.dart';
import '../theme/snapmon_text_styles.dart';
import 'placeholder_monster_painting.dart';
import 'storage_image.dart';

/// 図鑑の 1 体の絵。写真から切り出した被写体の画像 ([OwnedMonster.artPath]) があればそれを、
/// 無ければ (見本のモンスター) 仮の絵を [backgroundColor] の地に描く。
/// 切り出した画像に重ねる装飾 (目・手足・オーラ・輪郭線。DIRECTION.md「デザインの方向」) はまだ描かない。
class MonsterArt extends StatelessWidget {
  /// [monster] の絵を作る。
  const MonsterArt({
    super.key,
    required this.monster,
    required this.backgroundColor,
  });

  /// 描くモンスター。
  final OwnedMonster monster;

  /// 絵の地の色。
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final artPath = monster.artPath;
    return artPath == null
        ? PlaceholderMonsterArt(
            definition: monster.definition,
            backgroundColor: backgroundColor,
          )
        : ClipRRect(
            borderRadius: SnapmonRadii.button,
            child: ColoredBox(
              color: backgroundColor,
              child: StorageImage(
                storagePath: artPath,
                fit: BoxFit.contain,
                placeholder: const SizedBox.expand(),
              ),
            ),
          );
  }
}

/// 見本のモンスターの仮の絵。
class PlaceholderMonsterArt extends StatelessWidget {
  /// [definition] のモンスターの絵を [backgroundColor] の地に描く。
  const PlaceholderMonsterArt({
    super.key,
    required this.definition,
    required this.backgroundColor,
  });

  /// 描くモンスター。
  final MonsterDefinition definition;

  /// 絵の地の色。
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: SnapmonRadii.button,
    child: ColoredBox(
      color: backgroundColor,
      child: CustomPaint(
        painter: _PlaceholderMonsterPainter(definition: definition),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

class _PlaceholderMonsterPainter extends CustomPainter {
  _PlaceholderMonsterPainter({required this.definition});

  final MonsterDefinition definition;

  @override
  void paint(Canvas canvas, Size size) => paintPlaceholderMonster(
    canvas: canvas,
    size: size,
    definition: definition,
  );

  @override
  bool shouldRepaint(_PlaceholderMonsterPainter oldDelegate) =>
      oldDelegate.definition.id != definition.id;
}

/// 属性の札。[elementTypeId] の名前を [definitions] から引き、属性の色の地に描く。
class ElementTypeTag extends StatelessWidget {
  /// 属性の札を作る。
  const ElementTypeTag({
    super.key,
    required this.elementTypeId,
    required this.definitions,
  });

  /// 描く属性の識別子。
  final String elementTypeId;

  /// 属性の名前を引く定義。
  final MasterData definitions;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: elementTypeColor(elementTypeId: elementTypeId),
      borderRadius: SnapmonRadii.tag,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        definitions.elementTypes
            .firstWhere(
              (elementType) => elementType.id == elementTypeId,
              orElse: () => throw StateError('属性 $elementTypeId が定義に無い'),
            )
            .displayName,
        style: SnapmonTextStyles.small.copyWith(
          color: SnapmonColors.textOnBackground,
        ),
      ),
    ),
  );
}
