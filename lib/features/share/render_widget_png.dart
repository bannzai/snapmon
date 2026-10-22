import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_text_styles.dart';
import 'card_sharer.dart';

/// [card] を [format] の論理の大きさで、画面の木とは別の描画の木に描いて PNG を返す ([CardSharer.renderPng] の実体)。
/// [view] は描画の木を結びつける端末の画面。描画の木は画面に合成しない (RenderView.compositeFrame を呼ばない) ため、画面には出ない。
/// [card] の画像は描く前にデコードを済ませておく (この描画は 1 回きりで、非同期の読み込みの終わりを待たないため)。
Future<Uint8List> renderWidgetToPng({
  required ui.FlutterView view,
  required Widget card,
  required ShareCardFormat format,
}) async {
  final repaintBoundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(format.logicalSize),
      physicalConstraints: BoxConstraints.tight(format.logicalSize),
    ),
    child: RenderPositionedBox(child: repaintBoundary),
  );
  final pipelineOwner = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final buildOwner = BuildOwner(focusManager: FocusManager());
  final adapter = RenderObjectToWidgetAdapter<RenderBox>(
    container: repaintBoundary,
    child: MediaQuery(
      data: MediaQueryData(
        size: format.logicalSize,
        // カードの大きさは固定のため、端末の文字の大きさの設定で文字がはみ出さないようにする
        textScaler: TextScaler.noScaling,
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        // 画面の木の外のため Material の DefaultTextStyle が無い。色を指定しない Text の基準の色と書体を明示する
        child: DefaultTextStyle(
          style: SnapmonTextStyles.body.copyWith(
            color: SnapmonColors.textOnBackground,
            decoration: TextDecoration.none,
          ),
          child: card,
        ),
      ),
    ),
  );
  final rootElement = adapter.attachToRenderTree(buildOwner);
  try {
    buildOwner
      ..buildScope(rootElement)
      ..finalizeTree();
    pipelineOwner
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();
    final image = await repaintBoundary.toImage(pixelRatio: format.pixelRatio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('カード画像を PNG にできませんでした');
      }
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  } finally {
    // カードの木を外して破棄する (同じ描画の木は使い回さない)
    RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
    ).attachToRenderTree(buildOwner, rootElement);
    buildOwner
      ..buildScope(rootElement)
      ..finalizeTree();
    pipelineOwner.rootNode = null;
    pipelineOwner.dispose();
  }
}
