import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../analytics/analytics_events.dart';
import '../../l10n/l10n.dart';
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
    // 形を選ぶシートが開くまでの間に 2 回押されて共有が 2 本走らないよう、押した時点で押せなくする
    setState(() => _isSharing = true);
    // iPad の共有シートの起点は、共有シートを開く時に閉じているダイアログではなく、押したこのボタンにする
    final buttonBox = context.findRenderObject()! as RenderBox;
    final sharePositionOrigin =
        buttonBox.localToGlobal(Offset.zero) & buttonBox.size;
    final format = await showModalBottomSheet<ShareCardFormat>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                context.l10n.shareChooseFormat,
                style: SnapmonTextStyles.label,
              ),
            ),
            for (final format in ShareCardFormat.values)
              ListTile(
                key: Key('share-format-${format.analyticsValue}'),
                title: Text(switch (format) {
                  ShareCardFormat.portrait => context.l10n.shareFormatPortrait,
                  ShareCardFormat.landscape =>
                    context.l10n.shareFormatLandscape,
                }, style: SnapmonTextStyles.label),
                subtitle: Text(switch (format) {
                  ShareCardFormat.portrait =>
                    context.l10n.shareFormatPortraitDescription,
                  ShareCardFormat.landscape =>
                    context.l10n.shareFormatLandscapeDescription,
                }, style: SnapmonTextStyles.caption),
                onTap: () => Navigator.of(context).pop(format),
              ),
          ],
        ),
      ),
    );
    if (!mounted) {
      return;
    }
    if (format == null) {
      setState(() => _isSharing = false);
      return;
    }
    final view = View.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // カードは画面の木の外 (Localizations が無い描画の木) で描くため、画面と同じ言語の文言を渡す
    final locale = Localizations.localeOf(context);
    final artImagesByPath = <String, ui.Image>{};
    try {
      for (final artPath in widget.artPaths.toSet()) {
        artImagesByPath[artPath] = await widget.cardSharer.loadArtImage(
          storagePath: artPath,
        );
      }
      final pngBytes = await widget.cardSharer.renderPng(
        view: view,
        // AppLocalizations の読み込みは同期で済む (gen-l10n の load は SynchronousFuture を返す) ため、1 回きりの描画でも文言が入る
        card: Localizations(
          locale: locale,
          delegates: const [AppLocalizations.delegate],
          child: widget.buildCard(
            format: format,
            artImagesByPath: artImagesByPath,
          ),
        ),
        format: format,
      );
      if (!mounted) {
        return;
      }
      // 描いた画像を見せ、共有シートは「共有する」を押した操作から開く。
      // Web の Web Share API は直前のユーザー操作 (transient activation) からしか呼べず、
      // 形を選んだ操作から画像の読み込み・描画を待つと失効してダウンロードに落ちるため
      final previewImage = MemoryImage(pngBytes);
      final shouldShare = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: Image(image: previewImage, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.l10n.commonCancel),
            ),
            FilledButton(
              key: const Key('share-confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.l10n.shareConfirm),
            ),
          ],
        ),
      );
      // 見せ終えたカード画像 (1080×1920 をデコードしたもの) を ImageCache に残さない
      unawaited(previewImage.evict());
      if (shouldShare != true) {
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
