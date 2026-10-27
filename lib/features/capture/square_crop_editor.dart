import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import 'monster_generator.dart';
import 'subject_mask.dart';

/// 写真の上で正方形の枠を動かして、モンスターにする範囲を決める部品。枠はドラッグで動かし、2 本の指 (ピンチ) か下のスライダーで
/// 大きさを変える (マウスでも大きさを変えられるようにスライダーを置いた)。枠が変わるたびに [onCropChanged] を呼ぶ。
class SquareCropEditor extends StatefulWidget {
  /// 範囲を決める部品を作る。
  const SquareCropEditor({
    super.key,
    required this.photo,
    required this.photoWidth,
    required this.photoHeight,
    required this.crop,
    required this.onCropChanged,
  });

  /// 範囲を決める写真 (生成に送る写真)。
  final Uint8List photo;

  /// [photo] の画素の幅。
  final int photoWidth;

  /// [photo] の画素の高さ。
  final int photoHeight;

  /// 今の枠 (写真の画素の座標)。
  final SquareCrop crop;

  /// 枠が変わった時に、新しい枠を受け取る。
  final void Function({required SquareCrop crop}) onCropChanged;

  @override
  State<SquareCropEditor> createState() => _SquareCropEditorState();
}

/// 写真を表示する枠の高さの上限。生成の画面で写真の下に説明とボタンを置ける高さとして置いた。
const double _maximumEditorHeight = 360;

/// [SquareCropEditor] の状態。ピンチの途中の倍率を持つ。
class _SquareCropEditorState extends State<SquareCropEditor> {
  /// ピンチの始まりからの倍率のうち、前の更新までに枠へ反映した分 (ScaleUpdateDetails.scale は始まりからの累計のため)。
  double _appliedScale = 1;

  /// 今の枠を [centerDelta] (写真の画素) 動かし [scaleChange] 倍にした枠を、[SquareCropEditor.onCropChanged] に渡す。
  void _update({
    required ({double dx, double dy}) centerDelta,
    required double scaleChange,
  }) => widget.onCropChanged(
    crop: updateSquareCrop(
      crop: widget.crop,
      centerDelta: centerDelta,
      scaleChange: scaleChange,
      photoWidth: widget.photoWidth,
      photoHeight: widget.photoHeight,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sideRange = squareCropSideRange(
      photoWidth: widget.photoWidth,
      photoHeight: widget.photoHeight,
    );
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // 写真を縦横比のまま枠に収め、表示の 1px が写真の何画素かを決める
            final displayScale = math.min(
              constraints.maxWidth / widget.photoWidth,
              _maximumEditorHeight / widget.photoHeight,
            );
            final crop = widget.crop;
            return Center(
              child: ClipRRect(
                borderRadius: SnapmonRadii.card,
                child: SizedBox(
                  width: widget.photoWidth * displayScale,
                  height: widget.photoHeight * displayScale,
                  // 写真の上の操作は、外側の画面のスクロールより先に枠の操作として受け取る (写真の外ではスクロールできる)
                  child: RawGestureDetector(
                    key: const Key('square-crop-area'),
                    gestures: {
                      _EagerScaleGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            _EagerScaleGestureRecognizer
                          >(
                            _EagerScaleGestureRecognizer.new,
                            (recognizer) => recognizer
                              ..onStart = (_) {
                                _appliedScale = 1;
                              }
                              ..onUpdate = (details) {
                                _update(
                                  centerDelta: (
                                    dx:
                                        details.focalPointDelta.dx /
                                        displayScale,
                                    dy:
                                        details.focalPointDelta.dy /
                                        displayScale,
                                  ),
                                  scaleChange: details.scale / _appliedScale,
                                );
                                _appliedScale = details.scale;
                              },
                          ),
                    },
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          widget.photo,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        ),
                        CustomPaint(
                          painter: _SquareCropPainter(
                            frame: Rect.fromLTWH(
                              crop.left * displayScale,
                              crop.top * displayScale,
                              crop.side * displayScale,
                              crop.side * displayScale,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Slider(
          key: const Key('square-crop-size'),
          value: widget.crop.side,
          min: sideRange.minimum,
          max: sideRange.maximum,
          label: '枠の大きさ',
          onChanged: (side) => _update(
            centerDelta: (dx: 0, dy: 0),
            scaleChange: side / widget.crop.side,
          ),
        ),
      ],
    );
  }
}

/// 指が触れた時点で操作を自分のものにする [ScaleGestureRecognizer]。外側の ListView の縦のスクロールに、枠を縦に動かす操作を取られないため。
class _EagerScaleGestureRecognizer extends ScaleGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// 枠の外を暗くし、枠の線を描く。
class _SquareCropPainter extends CustomPainter {
  const _SquareCropPainter({required this.frame});

  /// 枠 (表示の座標)。
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(Offset.zero & size),
          Path()..addRect(frame),
        ),
        Paint()..color = SnapmonColors.background.withValues(alpha: 0.6),
      )
      ..drawRect(
        frame.deflate(1.5),
        Paint()
          ..color = SnapmonColors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3,
      );
  }

  @override
  bool shouldRepaint(_SquareCropPainter oldDelegate) =>
      oldDelegate.frame != frame;
}
