/// 他のユーザーのモンスターを通報する理由。値は Functions の reportMonster が受け付ける理由
/// (functions/src/pvp_rules.ts の REPORT_REASONS) と同じ。
enum ReportReason {
  /// 絵が不適切。
  inappropriatePicture('inappropriate_picture', '絵が不適切'),

  /// 名前・図鑑の文章が不適切。
  inappropriateText('inappropriate_text', '名前や文章が不適切'),

  /// 人が写っている。
  personInPicture('person_in_picture', '人が写っている'),

  /// その他。
  other('other', 'その他');

  const ReportReason(this.value, this.label);

  /// Functions に送る値。
  final String value;

  /// 通報の画面に出す選択肢の文言。
  final String label;
}
