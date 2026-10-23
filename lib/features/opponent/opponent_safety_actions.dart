import 'package:flutter/material.dart';

import '../../theme/snapmon_colors.dart';
import '../dex/owned_monster.dart';
import '../settings/settings_screen.dart';
import 'pvp_client.dart';
import 'pvp_opponent.dart';
import 'report_sheet.dart';

// 他のユーザーの相手への通報・ブロック (ストアの UGC 要件) の操作。対戦相手の画面と、初回の導線のバトルの画面から使う。

/// [message] を [context] の画面の下に出す。
void _showMessage({required BuildContext context, required String message}) {
  ScaffoldMessenger.of(context)
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
      _showMessage(context: context, message: '$contactUri を開けませんでした');
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
Future<void> reportOpponentMonster({
  required BuildContext context,
  required PvpClient pvpClient,
  required PvpOpponent opponent,
  required OwnedMonster monster,
  required bool sendsToServer,
  required OpenUrl openUrl,
  required VoidCallback? onReported,
}) async {
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
        if (context.mounted) {
          onReported?.call();
          _showMessage(context: context, message: '通報しました');
        }
      },
      onOpenContact: () => openContact(context: context, openUrl: openUrl),
    ),
  );
}

/// [opponent] をブロックするかを確かめ、ブロックしたら [onBlocked] を呼んで「ブロックしました」を出す。失敗した時はエラーをそのまま出す。
/// [sendsToServer] の扱いは [reportOpponentMonster] と同じ。
Future<void> blockOpponent({
  required BuildContext context,
  required PvpClient pvpClient,
  required PvpOpponent opponent,
  required bool sendsToServer,
  required VoidCallback? onBlocked,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      // 表示名は最大 12 文字で、タイトルの大きな文字に入れると 1 行に収まらないため本文に置く
      title: const Text('ブロック'),
      content: Text('${opponent.displayName} と互いに対戦の相手に出なくなります'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('やめる'),
        ),
        TextButton(
          key: const Key('block-confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('ブロックする'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  try {
    if (sendsToServer) {
      await pvpClient.blockUser(blockedUid: opponent.opponentUid);
    }
    if (context.mounted) {
      onBlocked?.call();
      _showMessage(context: context, message: 'ブロックしました');
    }
  } catch (error) {
    if (context.mounted) {
      _showMessage(context: context, message: error.toString());
    }
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
    tooltip: '通報 · ブロック',
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
          child: Text('${monster.definition.name} を通報'),
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
        child: const Text('このトレーナーをブロック'),
      ),
    ],
  );
}
