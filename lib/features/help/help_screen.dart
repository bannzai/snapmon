import 'package:flutter/material.dart';

import '../../domain/battle/battle_state.dart';
import '../../domain/battle/status_condition.dart';
import '../../l10n/l10n.dart';
import '../../monster_ui/move_card.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';

/// 遊び方の画面。設定の画面の「遊び方」から開く。中身は [HelpSections] で、負けた後の勝敗の画面の案内が
/// [showHelpSheet] で同じ中身をポップアップに出す (https://github.com/bannzai/castle/issues/2861 )。
class HelpScreen extends StatelessWidget {
  /// 遊び方の画面を作る。
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.helpTitle)),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: const [HelpSections()],
    ),
  );
}

/// 遊び方 ([HelpSections]) をスクロールできるポップアップで開き、閉じるまで待つ。
Future<void> showHelpSheet({required BuildContext context}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: SnapmonColors.background,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        // 開いた時に勝敗の画面の上の方が少し見え、ポップアップだと分かる高さにした
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ListView(
          key: const Key('help-sheet'),
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.helpTitle,
                    style: SnapmonTextStyles.screenTitle,
                  ),
                ),
                IconButton(
                  key: const Key('help-sheet-close'),
                  tooltip: context.l10n.commonClose,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const HelpSections(),
          ],
        ),
      ),
    );

/// 遊び方の節 (手持ち・レベル・属性の相性・状態異常) を縦に並べた中身。バトルで使う相性のアイコンと状態の名前を
/// そのまま埋め込み、説明とバトルの画面の見た目を結びつける。
class HelpSections extends StatelessWidget {
  /// 遊び方の節を作る。
  const HelpSections({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HelpSection(
          heading: l10n.helpPartyHeading(maximumPartySize),
          body: l10n.helpPartyBody,
          children: const [],
        ),
        _HelpSection(
          heading: l10n.helpLevelHeading,
          body: l10n.helpLevelBody,
          children: const [],
        ),
        _HelpSection(
          heading: l10n.helpTypeHeading,
          body: l10n.helpTypeBody,
          children: [
            // 倍率は documents/game-rules.md「相性表」の有利 (2 倍)・不利 (0.5 倍)
            _HelpRow(
              leading: const TypeEffectivenessIcon(typeMultiplier: 2),
              text: l10n.helpTypeSuperEffective,
            ),
            _HelpRow(
              leading: const TypeEffectivenessIcon(typeMultiplier: 0.5),
              text: l10n.helpTypeNotVeryEffective,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.helpTypeDualNote,
              style: SnapmonTextStyles.small.copyWith(
                color: SnapmonColors.textOnCardMuted,
              ),
            ),
          ],
        ),
        _HelpSection(
          heading: l10n.helpStatusHeading,
          body: l10n.helpStatusBody,
          children: [
            for (final kind in StatusConditionKind.values)
              _HelpRow(
                key: Key('help-status-${kind.name}'),
                leading: SizedBox(
                  // 状態の名前でいちばん長い「こうたいふか」が 1 行に収まる幅にした
                  width: 88,
                  child: Text(
                    statusConditionLabel(l10n: l10n, kind: kind),
                    style: SnapmonTextStyles.label.copyWith(
                      color: SnapmonColors.textOnCard,
                    ),
                  ),
                ),
                text: statusConditionHelpDescription(l10n: l10n, kind: kind),
              ),
          ],
        ),
      ],
    );
  }
}

/// 遊び方の 1 つの節。見出しと本文のカードに、[children] (見本のアイコン・一覧) を続ける。
class _HelpSection extends StatelessWidget {
  const _HelpSection({
    required this.heading,
    required this.body,
    required this.children,
  });

  /// 節の見出し。
  final String heading;

  /// 節の本文。
  final String body;

  /// 本文の後に並べる見本。
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        color: SnapmonColors.card,
        borderRadius: SnapmonRadii.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              heading,
              style: SnapmonTextStyles.cardTitle.copyWith(
                color: SnapmonColors.textOnCard,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: SnapmonTextStyles.body.copyWith(
                color: SnapmonColors.textOnCardBody,
              ),
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...children,
            ],
          ],
        ),
      ),
    ),
  );
}

/// 遊び方の節の 1 行。左に見本 ([leading])、右に説明を出す。
class _HelpRow extends StatelessWidget {
  const _HelpRow({super.key, required this.leading, required this.text});

  /// 左に出す見本 (相性のアイコン・状態の名前)。
  final Widget leading;

  /// 見本の説明。
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: SnapmonTextStyles.small.copyWith(
              color: SnapmonColors.textOnCardBody,
            ),
          ),
        ),
      ],
    ),
  );
}
