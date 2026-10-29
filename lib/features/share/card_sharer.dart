import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

import '../../analytics/analytics_events.dart';

/// 共有するカード画像の形。[logicalSize] の大きさで描き、[pixelRatio] 倍の画素の PNG にする。
/// 画素の大きさは issue #18 の 2 種 (1080×1920 と 1200×630) で、論理の大きさは画面の文字の大きさ (SnapmonTextStyles) のまま収まるように選んだ。
enum ShareCardFormat {
  /// 縦長 (ストーリーズ向け)。1080×1920。
  portrait(
    analyticsValue: 'portrait',
    logicalSize: Size(360, 640),
    pixelRatio: 3,
  ),

  /// 横長 (投稿のリンクのプレビュー (OGP) の推奨の大きさ)。1200×630。
  landscape(
    analyticsValue: 'landscape',
    logicalSize: Size(600, 315),
    pixelRatio: 2,
  );

  const ShareCardFormat({
    required this.analyticsValue,
    required this.logicalSize,
    required this.pixelRatio,
  });

  /// 共有イベントの `format` に送る値。
  final String analyticsValue;

  /// カードを描く論理の大きさ。
  final Size logicalSize;

  /// 論理の大きさから PNG の画素の大きさへの倍率。
  final double pixelRatio;
}

/// どの画面から共有したか。共有イベントの `screen` に送る。
enum ShareScreen {
  /// 撮った写真から新しく生まれた時の生まれた画面。
  resultNewlyBorn('result_newly_born'),

  /// 撮った写真の被写体がもう図鑑にいた時の生まれた画面。
  resultAlreadyInDex('result_already_in_dex'),

  /// 図鑑から開いた詳細 (生まれた画面と同じ画面)。
  dexDetail('dex_detail'),

  /// バトルの勝敗の画面。
  battleResult('battle_result');

  const ShareScreen(this.analyticsValue);

  /// 共有イベントの `screen` に送る値。
  final String analyticsValue;
}

/// カード画像の共有に使う関数の組。
/// 画面を Firebase・OS の共有シートと切り離してテストするため、実体は main.dart から渡す
/// (lib/firebase/share_art.dart・render_widget_png.dart・share_image.dart と logAnalyticsEvent)。
class CardSharer {
  /// 関数の組を作る。
  const CardSharer({
    required this.loadArtImage,
    required this.renderPng,
    required this.shareImage,
    required this.logEvent,
  });

  /// 写真から切り出した被写体の画像 ([artPath]。`OwnedMonster.artPath`) を読んでデコードする。
  /// 読めない時は throw する。元の写真のパスは渡さない (カードの絵は装飾を重ねる切り出した画像で描くため)。
  /// バトル画面もフィールドのモンスターを描くために使う。
  final Future<ui.Image> Function({required String artPath}) loadArtImage;

  /// [card] を [format] の大きさで画面に出さずに描き、PNG を返す。[view] は描画に使う端末の画面。
  final Future<Uint8List> Function({
    required ui.FlutterView view,
    required Widget card,
    required ShareCardFormat format,
  })
  renderPng;

  /// PNG [pngBytes] を [fileName] として [text] と一緒に OS の共有シート (Web は Web Share かダウンロード) に渡し、結果を返す。
  /// [sharePositionOrigin] は iPad で共有シートを出す起点 (押したボタンの画面上の位置)。
  final Future<ShareResultStatus> Function({
    required Uint8List pngBytes,
    required String fileName,
    required String text,
    required Rect sharePositionOrigin,
  })
  shareImage;

  /// Analytics にイベントを送る ([logAnalyticsEvent] と同じ形)。
  final Future<void> Function({
    required AnalyticsEvent event,
    required Map<String, Object>? parameters,
  })
  logEvent;
}
