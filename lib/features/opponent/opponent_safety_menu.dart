import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../dex/owned_monster.dart';
import '../settings/settings_screen.dart';
import 'pvp_battle.dart';
import 'pvp_client.dart';
import 'report_sheet.dart';

// 人との対戦の相手への通報・ブロックと、お問い合わせ (ストアの UGC 要件の通報・ブロック・連絡先) の操作。バトルの画面のログの帯から使う。

/// [message] を [messenger] の画面の下に出す。送っている間にメニューのボタンが画面から外れても出せるよう、送る前に取った [messenger] を使う。
void _showMessage({
  required ScaffoldMessengerState messenger,
  required String message,
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// [opponent] のモンスター [monster] を通報するシートを開き、送れたら「通報しました」を出す。
/// 通報した持ち主とは、この後の対戦で組み合わされなくなる (functions/src/pvp_battle.ts の joinPvpMatch)。進行中の対戦は続く。
Future<void> _reportOpponentMonster({
  required BuildContext context,
  required PvpClient pvpClient,
  required PvpTrainer opponent,
  required OwnedMonster monster,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // 送れた時の文言は、シートを閉じた後にも出すため、先に取っておく
  final reportedMessage = context.l10n.opponentReported;
  await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SnapmonColors.surface,
    builder: (sheetContext) => ReportSheet(
      monsterName: monster.definition.name,
      onSubmit: ({required reason}) async {
        await pvpClient.reportMonster(
          monsterOwnerUid: opponent.uid,
          monsterID: monster.definition.id,
          reason: reason,
        );
        _showMessage(messenger: messenger, message: reportedMessage);
      },
    ),
  );
}

/// [opponent] をブロックするかを確かめ、ブロックできたら「ブロックしました」を出す。失敗した時はエラーをそのまま出す。
/// ブロックした相手との進行中の対戦は、Functions が勝敗を付けずに終える (functions/src/pvp.ts の blockUser)。
Future<void> _blockOpponent({
  required BuildContext context,
  required PvpClient pvpClient,
  required PvpTrainer opponent,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // ブロックできた時の文言は、ダイアログを閉じた後にも出すため、先に取っておく
  final blockedMessage = context.l10n.opponentBlocked;
  if (await showDialog<bool>(
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
      ) !=
      true) {
    return;
  }
  try {
    await pvpClient.blockUser(blockedUid: opponent.uid);
    _showMessage(messenger: messenger, message: blockedMessage);
  } catch (error) {
    _showMessage(messenger: messenger, message: error.toString());
  }
}

/// お問い合わせの宛先を [pvpClient] で開く。開けなかった時はそのことを、失敗した時はエラーをそのまま出す。
Future<void> _openContact({
  required BuildContext context,
  required PvpClient pvpClient,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // 開けなかった時の文言は、外部のアプリから戻った後にも出すため、先に取っておく
  final couldNotOpenMessage = context.l10n.commonCouldNotOpenURL(
    contactUri.toString(),
  );
  try {
    if (!await pvpClient.openContact()) {
      _showMessage(messenger: messenger, message: couldNotOpenMessage);
    }
  } catch (error) {
    _showMessage(messenger: messenger, message: error.toString());
  }
}

/// 人との対戦の相手 [opponent] の、モンスター ([reportableMonsters]) ごとの通報・相手のブロック・お問い合わせを選ぶメニューのボタン。
class OpponentSafetyMenuButton extends StatelessWidget {
  /// [opponent] の通報・ブロックのメニューのボタンを作る。
  const OpponentSafetyMenuButton({
    super.key,
    required this.opponent,
    required this.reportableMonsters,
    required this.pvpClient,
  });

  /// 通報・ブロックする相手。
  final PvpTrainer opponent;

  /// 通報できるモンスター (相手の手持ちのうち、場に出たことがあるモンスター)。
  final List<OwnedMonster> reportableMonsters;

  /// 通報・ブロックの送り先と、お問い合わせを開く関数。
  final PvpClient pvpClient;

  @override
  Widget build(BuildContext context) => PopupMenuButton<VoidCallback>(
    key: const Key('opponent-safety-menu'),
    tooltip: context.l10n.opponentSafetyMenuTooltip,
    onSelected: (action) => action(),
    itemBuilder: (menuContext) => [
      for (final monster in reportableMonsters)
        PopupMenuItem(
          key: Key('report-${monster.definition.id}'),
          value: () => _reportOpponentMonster(
            context: context,
            pvpClient: pvpClient,
            opponent: opponent,
            monster: monster,
          ),
          child: Text(context.l10n.reportSheetTitle(monster.definition.name)),
        ),
      PopupMenuItem(
        key: const Key('block-opponent'),
        value: () => _blockOpponent(
          context: context,
          pvpClient: pvpClient,
          opponent: opponent,
        ),
        child: Text(context.l10n.opponentBlockTrainer),
      ),
      PopupMenuItem(
        key: const Key('contact-support'),
        value: () => _openContact(context: context, pvpClient: pvpClient),
        child: Text(context.l10n.commonContact),
      ),
    ],
    // 押せる範囲を 44 (Apple の Human Interface Guidelines の最小のタップ領域) にし、ログの帯の高さを抑えるため、
    // 既定の IconButton (48 と周りの余白) ではなく余白を付けたアイコンを置く
    child: const Padding(
      padding: EdgeInsets.all(10),
      child: Icon(Icons.more_horiz, size: 24, color: SnapmonColors.textMuted),
    ),
  );
}
