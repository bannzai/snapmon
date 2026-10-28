import '../../l10n/l10n.dart';

/// 他のユーザーのモンスターを通報する理由。値は Functions の reportMonster が受け付ける理由
/// (functions/src/pvp_rules.ts の REPORT_REASONS) と同じ。
enum ReportReason {
  /// 絵が不適切。
  inappropriatePicture('inappropriate_picture'),

  /// 名前・図鑑の文章が不適切。
  inappropriateText('inappropriate_text'),

  /// 人が写っている。
  personInPicture('person_in_picture'),

  /// その他。
  other('other');

  const ReportReason(this.value);

  /// Functions に送る値。
  final String value;
}

/// 通報の画面に出す [reason] の選択肢の文言。
String reportReasonLabel({
  required AppLocalizations l10n,
  required ReportReason reason,
}) => switch (reason) {
  ReportReason.inappropriatePicture => l10n.reportReasonInappropriatePicture,
  ReportReason.inappropriateText => l10n.reportReasonInappropriateText,
  ReportReason.personInPicture => l10n.reportReasonPersonInPicture,
  ReportReason.other => l10n.reportReasonOther,
};
