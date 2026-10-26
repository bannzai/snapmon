import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../dex/owned_monster.dart';
import '../settings/settings_screen.dart';
import 'pvp_client.dart';
import 'pvp_opponent.dart';
import 'report_sheet.dart';

// 他のユーザーの相手への通報・ブロック (ストアの UGC 要件) の操作。対戦相手の画面と、初回の導線のバトルの画面から使う。

/// [message] を [context] の画面の下に出す。
void _showMessage({required BuildContext context, required String message}) =>
    _showMessageWithMessenger(
      messenger: ScaffoldMessenger.of(context),
      message: message,
    );

/// [message] を [messenger] の画面の下に出す。送っている間にメニューのボタン (相手のカード) が画面から外れても出せるよう、
/// 送る前に取った [messenger] を使う。
void _showMessageWithMessenger({
  required ScaffoldMessengerState messenger,
  required String message,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// お問い合わせ ([contactUri]) を [openUrl] で開く。開けなかった時はそのことを、失敗した時はエラーをそのまま出す。
Future<void> openContact({
  required BuildContext context,
  required OpenUrl openUrl,
}) async {
  try {
    if (!await openUrl(uri: contactUri) && context.mounted) {
      _showMessage(
        context: context,
        message: context.l10n.commonCouldNotOpenUrl(contactUri.toString()),
      );
    }
  } on Exception catch (error) {
    if (context.mounted) {
      _showMessage(context: context, message: error.toString());
    }
  }
}

/// [opponent] のモンスター [monster] を通報するシートを開き、送れたら [onReported] を呼んで「通報しました」を出す。
/// [sendsToServer] が false の時 (ログインが無く見本の相手を出している時) は送らずに送れた扱いにする (送り先のサーバーが無いため)。
/// 送っている間にシートを閉じられても通報は届くため、[onReported] はシートの結果ではなく送れた時に呼ぶ。
/// 送っている間に [context] (相手のカード) が画面から外れても (候補の読み直し等) 呼ぶため、[onReported] の側で画面が閉じていないかを確かめる。
Future<void> reportOpponentMonster({
  required BuildContext context,
  required PvpClient pvpClient,
  required PvpOpponent opponent,
  required OwnedMonster monster,
  required bool sendsToServer,
  required OpenUrl openUrl,
  required VoidCallback? onReported,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // 送れた時の文言は、シートを閉じた後 (context が画面から外れた後) にも出すため、先に取っておく
  final reportedMessage = context.l10n.opponentReported;
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SnapmonColors.surface,
    builder: (sheetContext) => ReportSheet(
      monsterName: monster.definition.name,
      onSubmit: ({required reason}) async {
        if (sendsToServer) {
          await pvpClient.reportMonster(
            monsterOwnerUid: opponent.opponentUid,
            monsterId: monster.definition.id,
            reason: reason,
          );
        }
        onReported?.call();
        _showMessageWithMessenger(
          messenger: messenger,
          message: reportedMessage,
        );
      },
      onOpenContact: () => openContact(context: context, openUrl: openUrl),
    ),
  );
}

/// [opponent] をブロックするかを確かめ、ブロックしたら [onBlocked] を呼んで「ブロックしました」を出す。失敗した時はエラーをそのまま出す。
/// [sendsToServer] と、[context] が外れた時の [onBlocked] の扱いは [reportOpponentMonster] と同じ。
Future<void> blockOpponent({
  required BuildContext context,
  required PvpClient pvpClient,
  required PvpOpponent opponent,
  required bool sendsToServer,
  required VoidCallback? onBlocked,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // ブロックできた時の文言は、ダイアログを閉じた後 (context が画面から外れた後) にも出すため、先に取っておく
  final blockedMessage = context.l10n.opponentBlocked;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // 表示名は最大 12 文字で、タイトルの大きな文字に入れると 1 行に収まらないため本文に置く
      title: Text(dialogContext.l10n.blockDialogTitle),
      content: Text(
        dialogContext.l10n.blockDialogMessage(opponent.displayName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(dialogContext.l10n.commonCancel),
        ),
        TextButton(
          key: const Key('block-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(dialogContext.l10n.blockDialogConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    return;
  }
  try {
    if (sendsToServer) {
      await pvpClient.blockUser(blockedUid: opponent.opponentUid);
    }
    onBlocked?.call();
    _showMessageWithMessenger(messenger: messenger, message: blockedMessage);
  } catch (error) {
    _showMessageWithMessenger(messenger: messenger, message: error.toString());
  }
}

/// [opponent] の各モンスターの通報と、トレーナーのブロックを選ぶメニューのボタン。
/// 通報・ブロックできた時は [onOpponentRemoved] を呼ぶ (対戦相手の画面は候補から消す。null なら何もしない)。
class OpponentSafetyMenuButton extends StatelessWidget {
  /// [opponent] の通報・ブロックのメニューのボタンを作る。
  const OpponentSafetyMenuButton({
    super.key,
    required this.opponent,
    required this.pvpClient,
    required this.sendsToServer,
    required this.openUrl,
    required this.onOpponentRemoved,
  });

  /// 通報・ブロックする相手。
  final PvpOpponent opponent;

  /// 通報・ブロックの送り先。
  final PvpClient pvpClient;

  /// 通報・ブロックをサーバーに送るか ([reportOpponentMonster])。
  final bool sendsToServer;

  /// お問い合わせを開く。
  final OpenUrl openUrl;

  /// 通報・ブロックできた時に呼ぶ。
  final VoidCallback? onOpponentRemoved;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    key: Key('opponent-menu-${opponent.opponentUid}'),
    tooltip: context.l10n.opponentSafetyMenuTooltip,
    icon: const Icon(Icons.more_horiz, color: SnapmonColors.textMuted),
    onSelected: (action) => action(),
    itemBuilder: (menuContext) => [
      for (final monster in opponent.monsters)
        PopupMenuItem(
          value: () => reportOpponentMonster(
            context: context,
            pvpClient: pvpClient,
            opponent: opponent,
            monster: monster,
            sendsToServer: sendsToServer,
            openUrl: openUrl,
            onReported: onOpponentRemoved,
          ),
          child: Text(context.l10n.reportSheetTitle(monster.definition.name)),
        ),
      PopupMenuItem(
        key: Key('block-${opponent.opponentUid}'),
        value: () => blockOpponent(
          context: context,
          pvpClient: pvpClient,
          opponent: opponent,
          sendsToServer: sendsToServer,
          onBlocked: onOpponentRemoved,
        ),
        child: Text(context.l10n.opponentBlockTrainer),
      ),
    ],
  );
}
