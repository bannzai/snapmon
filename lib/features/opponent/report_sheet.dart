import 'package:flutter/material.dart';

import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_text_styles.dart';
import 'report_reason.dart';

/// 相手のモンスターを通報する下からのシート (ストアの UGC 要件の通報と連絡先)。理由を選んで送り、送れたら true で閉じる。
/// 送れなかった時はエラーをそのまま出して閉じない。お問い合わせ (設定画面と同じ連絡先) もここから開ける。
class ReportSheet extends StatefulWidget {
  /// [monsterName] を通報するシートを作る。
  const ReportSheet({
    super.key,
    required this.monsterName,
    required this.onSubmit,
    required this.onOpenContact,
  });

  /// 通報するモンスターの名前。
  final String monsterName;

  /// [reason] で通報を送る。失敗した時は例外を投げる。
  final Future<void> Function({required ReportReason reason}) onSubmit;

  /// お問い合わせを開く。
  final VoidCallback onOpenContact;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<ReportSheet> {
  ReportReason? _selectedReason;
  bool _isSubmitting = false;
  String? _errorText;

  Future<void> _submit({required ReportReason reason}) async {
    setState(() {
      _isSubmitting = true;
      _errorText = null;
    });
    try {
      await widget.onSubmit(reason: reason);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _errorText = error.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedReason = _selectedReason;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${widget.monsterName} を通報',
              style: SnapmonTextStyles.cardTitle.copyWith(
                color: SnapmonColors.textOnBackground,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '通報したトレーナーは対戦の相手に出なくなります',
              style: SnapmonTextStyles.small,
            ),
            const SizedBox(height: 8),
            RadioGroup<ReportReason>(
              groupValue: selectedReason,
              onChanged: (reason) {
                // 送っている間は理由を変えさせない (送った理由と画面の選択を食い違わせないため)
                if (!_isSubmitting) {
                  setState(() => _selectedReason = reason);
                }
              },
              child: Column(
                children: [
                  for (final reason in ReportReason.values)
                    RadioListTile<ReportReason>(
                      key: Key('report-reason-${reason.value}'),
                      value: reason,
                      contentPadding: EdgeInsets.zero,
                      title: Text(reason.label, style: SnapmonTextStyles.body),
                    ),
                ],
              ),
            ),
            if (_errorText != null) ...[
              Text(
                _errorText!,
                key: const Key('report-error'),
                style: SnapmonTextStyles.small.copyWith(
                  color: SnapmonColors.hitPointsLoss,
                ),
              ),
              const SizedBox(height: 8),
            ],
            FilledButton(
              key: const Key('report-submit'),
              onPressed: selectedReason == null || _isSubmitting
                  ? null
                  : () => _submit(reason: selectedReason),
              child: Text(_isSubmitting ? '送っています' : '通報する'),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Expanded(
                  child: Text('ほかに困ったことがあれば', style: SnapmonTextStyles.small),
                ),
                TextButton(
                  key: const Key('report-contact'),
                  onPressed: widget.onOpenContact,
                  child: const Text('お問い合わせ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
