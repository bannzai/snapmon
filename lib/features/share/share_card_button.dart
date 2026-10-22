import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../analytics/analytics_events.dart';
import '../../theme/snapmon_text_styles.dart';
import 'card_sharer.dart';

/// 押すとカード画像の形 ([ShareCardFormat]) を選んでもらい、カードを描いて見せ、「共有する」で共有シートに渡すボタン。
/// 共有シートを閉じただけ (dismissed) でなければ、Analytics に共有イベントを送る。
/// 読み込み・描画・共有の途中は押せなくする (Android の share_plus は前の共有が終わる前に次を呼ぶと前の共有を unavailable で返すため)。
class ShareCardButton extends StatefulWidget {
  /// 共有のボタンを作る。
  const ShareCardButton({
    super.key,
    required this.cardSharer,
    required this.screen,
    required this.artPaths,
    required this.buildCard,
    required this.shareText,
    required this.fileNamePrefix,
    required this.buttonBuilder,
  });

  /// カード画像の共有に使う関数の組。
  final CardSharer cardSharer;

  /// どの画面から共有するか (共有イベントの `screen`)。
  final ShareScreen screen;

  /// カードに描く、写真から切り出した被写体の画像の Storage のパス。元の写真のパスは渡さない。
  final List<String> artPaths;

  /// [format] のカードを作る。[artImagesByPath] は [artPaths] を読んでデコードした画像。
  final Widget Function({
    required ShareCardFormat format,
    required Map<String, ui.Image> artImagesByPath,
  })
  buildCard;

  /// 画像と一緒に共有シートに渡す文章。
  final String shareText;

  /// 共有する画像のファイル名の先頭。後ろに形と拡張子を付ける。
  final String fileNamePrefix;

  /// ボタンを作る。共有の途中は [onPressed] が null になる。
  final Widget Function({required VoidCallback? onPressed}) buttonBuilder;

  @override
  State<ShareCardButton> createState() => _ShareCardButtonState();
}

class _ShareCardButtonState extends State<ShareCardButton> {
  /// 読み込み・描画・共有の途中か。
  bool _isSharing = false;

  Future<void> _share() async {
    final format = await showModalBottomSheet<ShareCardFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text('カード画像の形をえらぶ', style: SnapmonTextStyles.label),
            ),
            for (final format in ShareCardFormat.values)
              ListTile(
                key: Key('share-format-${format.analyticsValue}'),
                title: Text(switch (format) {
                  ShareCardFormat.portrait => '縦長',
                  ShareCardFormat.landscape => '横長',
                }, style: SnapmonTextStyles.label),
                subtitle: Text(switch (format) {
                  ShareCardFormat.portrait => 'ストーリーズ向け 1080×1920',
                  ShareCardFormat.landscape => '投稿向け 1200×630',
                }, style: SnapmonTextStyles.caption),
                onTap: () => Navigator.of(context).pop(format),
              ),
          ],
        ),
      ),
    );
    if (format == null || !mounted) {
      return;
    }
    final view = View.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isSharing = true);
    final artImagesByPath = <String, ui.Image>{};
    try {
      for (final artPath in widget.artPaths.toSet()) {
        artImagesByPath[artPath] = await widget.cardSharer.loadArtImage(
          storagePath: artPath,
        );
      }
      final pngBytes = await widget.cardSharer.renderPng(
        view: view,
        card: widget.buildCard(
          format: format,
          artImagesByPath: artImagesByPath,
        ),
        format: format,
      );
      if (!mounted) {
        return;
      }
      // 描いた画像を見せ、共有シートは「共有する」を押した操作から開く。
      // Web の Web Share API は直前のユーザー操作 (transient activation) からしか呼べず、
      // 形を選んだ操作から画像の読み込み・描画を待つと失効してダウンロードに落ちるため
      final sharePositionOrigin = await showDialog<Rect>(
        context: context,
        builder: (context) => AlertDialog(
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: Image.memory(pngBytes, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('やめる'),
            ),
            Builder(
              builder: (buttonContext) => FilledButton(
                key: const Key('share-confirm'),
                onPressed: () {
                  final buttonBox =
                      buttonContext.findRenderObject()! as RenderBox;
                  Navigator.of(
                    context,
                  ).pop(buttonBox.localToGlobal(Offset.zero) & buttonBox.size);
                },
                child: const Text('共有する'),
              ),
            ),
          ],
        ),
      );
      if (sharePositionOrigin == null) {
        return;
      }
      final shareResultStatus = await widget.cardSharer.shareImage(
        pngBytes: pngBytes,
        fileName: '${widget.fileNamePrefix}-${format.analyticsValue}.png',
        text: widget.shareText,
        sharePositionOrigin: sharePositionOrigin,
      );
      // Web は共有しても・ダウンロードしても unavailable が返るため、閉じただけ (dismissed) 以外を共有として数える
      if (shareResultStatus != ShareResultStatus.dismissed) {
        unawaited(
          widget.cardSharer
              .logEvent(
                event: AnalyticsEvent.contentShared,
                parameters: {
                  'screen': widget.screen.analyticsValue,
                  'format': format.analyticsValue,
                },
              )
              // 計測の失敗は共有に影響させない (未処理の非同期の例外として報告させないため)
              .catchError((Object _) {}),
        );
      }
    } catch (error) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      for (final artImage in artImagesByPath.values) {
        artImage.dispose();
      }
      if (mounted) {
        setState(() => _isSharing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.buttonBuilder(onPressed: _isSharing ? null : _share);
}
