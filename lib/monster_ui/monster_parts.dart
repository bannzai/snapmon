import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/master/master_data.dart';
import '../domain/monster/monster_definition.dart';
import '../features/dex/owned_monster.dart';
import '../firebase/share_art.dart';
import '../theme/snapmon_colors.dart';
import '../theme/snapmon_radii.dart';
import '../theme/snapmon_text_styles.dart';
import 'monster_art_painting.dart';
import 'placeholder_monster_painting.dart';

/// 写真から切り出した被写体の画像 [artPath] を読んでデコードする関数。読めない時は throw する。
/// 返した画像の持ち主 (dispose する側) は受け取った側。
typedef LoadMonsterArtImage =
    Future<ui.Image> Function({required String artPath});

/// 子の木の [MonsterArt] が切り出した被写体の画像を読む関数を差し替える。無い時は [loadArtImageWithFirebase] で読む。
/// ストアのスクリーンショットの生成 (store_screenshots/) が、先にデコードした絵を Firebase を通さずに描くために使う
/// (widget test の偽の時間の中では画像のデコードが終わらないため)。
class MonsterArtImageLoaderScope extends InheritedWidget {
  /// [loadArtImage] で読む範囲を作る。
  const MonsterArtImageLoaderScope({
    super.key,
    required this.loadArtImage,
    required super.child,
  });

  /// 切り出した被写体の画像を読む関数。
  final LoadMonsterArtImage loadArtImage;

  @override
  bool updateShouldNotify(MonsterArtImageLoaderScope oldWidget) =>
      loadArtImage != oldWidget.loadArtImage;
}

/// 図鑑の 1 体の絵。写真から切り出した被写体の画像 ([OwnedMonster.artPath]。見本のモンスターは同梱の asset) があれば読み、
/// そのまま ([paintMonsterArt]) [backgroundColor] の地に描く。
/// 画像を読む前と読めなかった時は地だけを描き、画像を持たないモンスターは仮の絵を描く。
class MonsterArt extends StatefulWidget {
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
  State<MonsterArt> createState() => _MonsterArtState();
}

/// [MonsterArt] の、読み込んだ切り出した被写体の画像を持つ状態。
class _MonsterArtState extends State<MonsterArt> {
  /// 読み込めた切り出した被写体の画像。読む前・読めなかった時は null。この State が持ち主で、外す時に dispose する。
  ui.Image? _artImage;

  @override
  void initState() {
    super.initState();
    _loadArtImage();
  }

  @override
  void didUpdateWidget(MonsterArt oldWidget) {
    super.didUpdateWidget(oldWidget);
    // レベルが変わる等でモンスターが作り直されても、画像が同じなら読み直さない
    if (oldWidget.monster.artPath != widget.monster.artPath) {
      _artImage?.dispose();
      _artImage = null;
      _loadArtImage();
    }
  }

  @override
  void dispose() {
    _artImage?.dispose();
    super.dispose();
  }

  /// 今の [MonsterArt.monster] の切り出した被写体の画像を、上に [MonsterArtImageLoaderScope] があればその関数で、
  /// 無ければ [loadArtImageWithFirebase] で読む。読み終わる前に別の画像に変わった時と外された時は捨てる。
  Future<void> _loadArtImage() async {
    final artPath = widget.monster.artPath;
    if (artPath == null) {
      return;
    }
    try {
      // getInheritedWidgetOfExactType は依存を登録しないため initState からも呼べる (scope が変わっても読み直さない)
      final artImage =
          await (context
                  .getInheritedWidgetOfExactType<MonsterArtImageLoaderScope>()
                  ?.loadArtImage ??
              loadArtImageWithFirebase)(artPath: artPath);
      if (!mounted || widget.monster.artPath != artPath) {
        artImage.dispose();
        return;
      }
      setState(() {
        _artImage?.dispose();
        _artImage = artImage;
      });
    } catch (error) {
      debugPrint('$artPath: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final artImage = _artImage;
    return widget.monster.artPath == null
        ? PlaceholderMonsterArt(
            definition: widget.monster.definition,
            backgroundColor: widget.backgroundColor,
          )
        : artImage == null
        ? ClipRRect(
            borderRadius: SnapmonRadii.button,
            child: ColoredBox(
              color: widget.backgroundColor,
              child: const SizedBox.expand(),
            ),
          )
        : MonsterArtImage(
            artImage: artImage,
            backgroundColor: widget.backgroundColor,
          );
  }
}

/// 読み込み済みの切り出した被写体の画像 [artImage] の絵 ([paintMonsterArt])。
/// 図鑑のカード ([MonsterArt]) と共有カードが使う。
class MonsterArtImage extends StatelessWidget {
  /// [artImage] の絵を作る。
  const MonsterArtImage({
    super.key,
    required this.artImage,
    required this.backgroundColor,
  });

  /// [OwnedMonster.artPath] の画像。持ち主 (dispose する側) は呼び出し元。
  final ui.Image artImage;

  /// 絵の地の色。
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: SnapmonRadii.button,
    child: ColoredBox(
      color: backgroundColor,
      child: CustomPaint(
        painter: _MonsterArtImagePainter(artImage: artImage),
        child: const SizedBox.expand(),
      ),
    ),
  );
}

/// [MonsterArtImage] の絵を描く painter。
class _MonsterArtImagePainter extends CustomPainter {
  /// [artImage] を描く painter を作る。
  _MonsterArtImagePainter({required this.artImage});

  /// [OwnedMonster.artPath] の画像。持ち主 (dispose する側) は [MonsterArtImage] の呼び出し元。
  final ui.Image artImage;

  @override
  void paint(Canvas canvas, Size size) =>
      paintMonsterArt(canvas: canvas, size: size, artImage: artImage);

  @override
  bool shouldRepaint(_MonsterArtImagePainter oldDelegate) =>
      oldDelegate.artImage != artImage;
}

/// 切り出した画像 ([OwnedMonster.artPath]) を持たないモンスターの仮の絵。
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
