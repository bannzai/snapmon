import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_text_styles.dart';
import 'report_reason.dart';

/// 相手のモンスターを通報する下からのシート (ストアの UGC 要件の通報)。理由を選んで送り、送れたら true で閉じる。
/// 送れなかった時はエラーをそのまま出して閉じない。
class ReportSheet extends StatefulWidget {
  /// [monsterName] を通報するシートを作る。
  const ReportSheet({
    super.key,
    required this.monsterName,
    required this.onSubmit,
  });

  /// 通報するモンスターの名前。
  final String monsterName;

  /// [reason] で通報を送る。失敗した時は例外を投げる。
  final Future<void> Function({required ReportReason reason}) onSubmit;

  @override
  State<ReportSheet> createState() => _ReportSheetState();
}

/// [ReportSheet] の状態。選んでいる理由と、送っている途中か・送れなかった時のエラーを持つ。
class _ReportSheetState extends State<ReportSheet> {
  /// 選んでいる理由。選ぶまでは null で、送るボタンを押せない。
  ReportReason? _selectedReason;

  /// 通報を送っているか。送っている間は理由を変えられず、送るボタンを押せない。
  bool _isSubmitting = false;

  /// 送れなかった時のエラー。
  String? _errorText;

  /// [reason] で通報を送り、送れたらシートを true で閉じる。送れなかった時はエラーを出してシートを残す。
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
    // 横向きの端末・高さの低い Web のウィンドウ・大きな文字では、理由と送るボタンが画面の高さを超えるためスクロールさせる
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.reportSheetTitle(widget.monsterName),
              style: SnapmonTextStyles.cardTitle.copyWith(
                color: SnapmonColors.textOnBackground,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.reportSheetDescription,
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
                      title: Text(
                        reportReasonLabel(l10n: context.l10n, reason: reason),
                        style: SnapmonTextStyles.body,
                      ),
                    ),
                ],
              ),
            ),
            if (_errorText case final errorText?) ...[
              Text(
                errorText,
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
              child: Text(
                _isSubmitting
                    ? context.l10n.reportSheetSubmitting
                    : context.l10n.reportSheetSubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
