import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snapmon/domain/monster/monster_decoration.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/theme/snapmon_colors.dart';
import 'package:snapmon/widgets/monster_art_painting.dart';

import '../decorated_monster_fixture.dart';
import '../sample_data_fixture.dart';

/// 描く枠の 1 辺 (論理 px = 画素)。
const int _canvasSide = 200;

/// 切り出した画像の 1 辺。被写体はこの中央の 60% の四角で、周りは透明 (切り出した画像の余白)。
const int _artSide = 100;

/// 被写体の色。目の黒・輪郭線の色と区別できる色にした。
const Color _subjectColor = Color(0xFFC6F432);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final sampleData = loadSampleDataFixture();
  late ui.Image artImage;

  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(
        _artSide * 0.2,
        _artSide * 0.2,
        _artSide * 0.6,
        _artSide * 0.6,
      ),
      Paint()..color = _subjectColor,
    );
    artImage = await recorder.endRecording().toImage(_artSide, _artSide);
  });

  tearDownAll(() => artImage.dispose());

  /// [decoration] を版 [decorationVersion] で持つ見本のモンスター。
  OwnedMonster monsterWith({
    required MonsterDecoration decoration,
    required int decorationVersion,
  }) => decoratedMonster(
    monster: sampleData.monsters.first,
    artPath: 'monsters/test/art.png',
    decoration: decoration,
    decorationVersion: decorationVersion,
  );

  /// [monster] を描いた画素 (RGBA の並び)。
  Future<Uint8List> paintPixels({required OwnedMonster monster}) async {
    final recorder = ui.PictureRecorder();
    paintMonsterArt(
      canvas: Canvas(recorder),
      size: const Size(_canvasSide + 0.0, _canvasSide + 0.0),
      monster: monster,
      artImage: artImage,
    );
    final image = await recorder.endRecording().toImage(
      _canvasSide,
      _canvasSide,
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    return byteData!.buffer.asUint8List();
  }

  /// [pixels] のうち、[color] と同じ色の画素の位置。
  List<Offset> pixelsOfColor({
    required Uint8List pixels,
    required Color color,
  }) => [
    for (var index = 0; index < _canvasSide * _canvasSide; index++)
      if (pixels[index * 4] == (color.r * 255).round() &&
          pixels[index * 4 + 1] == (color.g * 255).round() &&
          pixels[index * 4 + 2] == (color.b * 255).round() &&
          pixels[index * 4 + 3] == 255)
        Offset(
          (index % _canvasSide).toDouble(),
          (index ~/ _canvasSide).toDouble(),
        ),
  ];

  /// [positions] の重心。
  Offset centroid({required List<Offset> positions}) =>
      positions.reduce((sum, position) => sum + position) /
      positions.length.toDouble();

  test('輪郭線は outlineColorHex の色で描く', () async {
    final redOutlinePixels = await paintPixels(
      monster: monsterWith(
        decoration: testDecoration(outlineColorHex: '#FF0000'),
        decorationVersion: 1,
      ),
    );
    final blueOutlinePixels = await paintPixels(
      monster: monsterWith(
        decoration: testDecoration(outlineColorHex: '#0000FF'),
        decorationVersion: 1,
      ),
    );
    const red = Color(0xFFFF0000);
    const blue = Color(0xFF0000FF);
    expect(pixelsOfColor(pixels: redOutlinePixels, color: red), isNotEmpty);
    expect(pixelsOfColor(pixels: redOutlinePixels, color: blue), isEmpty);
    expect(pixelsOfColor(pixels: blueOutlinePixels, color: blue), isNotEmpty);
    expect(pixelsOfColor(pixels: blueOutlinePixels, color: red), isEmpty);
  });

  test('目は eyeCenterX・eyeCenterY の位置に描く', () async {
    Future<Offset> eyeCentroid({
      required double eyeCenterX,
      required double eyeCenterY,
    }) async => centroid(
      positions: pixelsOfColor(
        pixels: await paintPixels(
          monster: monsterWith(
            decoration: testDecoration(
              eyeCenterX: eyeCenterX,
              eyeCenterY: eyeCenterY,
            ),
            decorationVersion: 1,
          ),
        ),
        color: SnapmonColors.background,
      ),
    );

    final leftUpper = await eyeCentroid(eyeCenterX: 0.35, eyeCenterY: 0.3);
    final rightLower = await eyeCentroid(eyeCenterX: 0.65, eyeCenterY: 0.6);
    expect(leftUpper.dx, lessThan(rightLower.dx - 20));
    expect(leftUpper.dy, lessThan(rightLower.dy - 20));
    // 割合は切り出した画像を描いた範囲 (枠の中央) に対する値なので、0.5 の位置は枠の中央になる
    final centered = await eyeCentroid(eyeCenterX: 0.5, eyeCenterY: 0.5);
    expect(centered.dx, closeTo(_canvasSide / 2, 1));
    expect(centered.dy, closeTo(_canvasSide / 2, 1));
  });

  test('目は eyeScale が大きいほど大きく描く', () async {
    Future<int> eyePixelCount({required double eyeScale}) async =>
        pixelsOfColor(
          pixels: await paintPixels(
            monster: monsterWith(
              decoration: testDecoration(eyeScale: eyeScale),
              decorationVersion: 1,
            ),
          ),
          color: SnapmonColors.background,
        ).length;

    final small = await eyePixelCount(eyeScale: 0.25);
    final large = await eyePixelCount(eyeScale: 0.4);
    expect(small, greaterThan(0));
    // 目の面積は大きさの 2 乗に比例するため、1.6 倍の大きさなら面積は 2.5 倍近くになる
    // (0.25 は目の大きさの下限 (枠の 7%) より大きく、0.4 は両目が被写体の幅に収まる上限より小さい値にした)
    expect(large, greaterThan(small * 2));
  });

  test('黒で塗る目 (sparkle・dot) は、暗い被写体の上でも見えるよう白い縁を付けて描く', () async {
    for (final eyeStyle in [MonsterEyeStyle.sparkle, MonsterEyeStyle.dot]) {
      final eyeWhitePixels = pixelsOfColor(
        pixels: await paintPixels(
          monster: monsterWith(
            decoration: testDecoration(eyeStyle: eyeStyle),
            decorationVersion: 1,
          ),
        ),
        color: SnapmonColors.card,
      );
      expect(eyeWhitePixels, isNotEmpty, reason: eyeStyle.name);
    }
  });

  test('すべての形の組み合わせを描ける', () async {
    for (final eyeStyle in MonsterEyeStyle.values) {
      for (final mouthStyle in MonsterMouthStyle.values) {
        for (final limbStyle in MonsterLimbStyle.values) {
          for (final auraStyle in MonsterAuraStyle.values) {
            final recorder = ui.PictureRecorder();
            paintMonsterArt(
              canvas: Canvas(recorder),
              size: const Size(_canvasSide + 0.0, _canvasSide + 0.0),
              monster: monsterWith(
                decoration: testDecoration(
                  eyeStyle: eyeStyle,
                  mouthStyle: mouthStyle,
                  limbStyle: limbStyle,
                  auraStyle: auraStyle,
                ),
                decorationVersion: 1,
              ),
              artImage: artImage,
            );
            recorder.endRecording().dispose();
          }
        }
      }
    }
  });

  test('細長い被写体でも、目と口は被写体の幅の中に描く', () async {
    // 被写体 22×100 に、切り出しと同じく長い辺の 4% の余白を 4 辺に付けた画像
    const thinWidth = 30;
    const thinHeight = 108;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(4, 4, thinWidth - 8.0, thinHeight - 8.0),
      Paint()..color = _subjectColor,
    );
    final thinImage = await recorder.endRecording().toImage(
      thinWidth,
      thinHeight,
    );
    addTearDown(thinImage.dispose);
    final paintRecorder = ui.PictureRecorder();
    paintMonsterArt(
      canvas: Canvas(paintRecorder),
      size: const Size(_canvasSide + 0.0, _canvasSide + 0.0),
      monster: monsterWith(
        decoration: testDecoration(
          eyeStyle: MonsterEyeStyle.round,
          mouthStyle: MonsterMouthStyle.open,
          eyeCenterY: 0.95,
        ),
        decorationVersion: 1,
      ),
      artImage: thinImage,
    );
    final image = await paintRecorder.endRecording().toImage(
      _canvasSide,
      _canvasSide,
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    final inkPositions = pixelsOfColor(
      pixels: byteData!.buffer.asUint8List(),
      color: SnapmonColors.background,
    );
    expect(inkPositions, isNotEmpty);
    // 画像は枠の余白 (12%) を除いた高さ 152 に合わせて縦横比を保って描くため、幅は 152 × 30 / 108 で中央に置かれる
    const drawnWidth = 152 * thinWidth / thinHeight;
    const drawnLeft = (_canvasSide - drawnWidth) / 2;
    const drawnTop = 24.0;
    for (final position in inkPositions) {
      expect(position.dx, inInclusiveRange(drawnLeft, drawnLeft + drawnWidth));
      expect(position.dy, inInclusiveRange(drawnTop, drawnTop + 152));
    }
  });

  test('このクライアントが描き分けを持たない版は、装飾を重ねず画像だけを枠いっぱいに描く', () async {
    final canvas = _RecordingCanvas();
    paintMonsterArt(
      canvas: canvas,
      size: const Size(_canvasSide + 0.0, _canvasSide + 0.0),
      monster: monsterWith(decoration: testDecoration(), decorationVersion: 2),
      artImage: artImage,
    );
    expect(canvas.invocations.map((call) => call.memberName), [#drawImageRect]);
    expect(
      canvas.invocations.single.positionalArguments[2],
      const Rect.fromLTWH(0, 0, _canvasSide + 0.0, _canvasSide + 0.0),
    );
  });
}

/// 受け取った描画の呼び出しを [invocations] に残す Canvas。装飾を描いたかを確かめるため。
class _RecordingCanvas implements Canvas {
  /// 受け取った呼び出し (呼ばれた順)。
  final List<Invocation> invocations = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    invocations.add(invocation);
    return null;
  }
}
