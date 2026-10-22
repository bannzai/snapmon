import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 使える年齢の下限 (DIRECTION.md「決めたこと」の対象年齢の行。13 歳未満は使えない)。
const int minimumAge = 13;

/// 生年月 [birthYear]・[birthMonth] の人が、[today] の時点で [minimumAge] 歳以上と確かめられるかを返す。
/// 生まれた日を聞かないため、[minimumAge] 歳の誕生日がある月はまだ満たないものとして扱い、翌月から使えるようにする
/// (月の途中に誕生日がある人を誤って通さないため)。
bool isOldEnough({
  required int birthYear,
  required int birthMonth,
  required DateTime today,
}) =>
    (today.year * 12 + today.month) - (birthYear * 12 + birthMonth) >
    minimumAge * 12;

/// 年齢の確認の状態。
enum AgeConfirmationStatus {
  /// まだ生年月を入力していない。
  unanswered,

  /// [minimumAge] 歳以上と確かめた。
  allowed,

  /// [minimumAge] 歳未満のため使えない。
  restricted,
}

/// 入力した生年月を端末に保存し、年齢の確認の状態を返す。
/// 生年月を保存するのは、一度入力した後に入力をやり直して年齢を変えられないようにするため
/// (FTC の COPPA の FAQ H.3 "using a cookie to prevent children from back-buttoning to enter a different age"。
/// https://www.ftc.gov/business-guidance/resources/complying-coppa-frequently-asked-questions )と、
/// アカウントの接続 (#12) でサーバーの年齢の検査 (ADR 0001 の `confirmAge`) に渡すため。
/// Firebase Auth・Analytics・App Check はこの確認が [AgeConfirmationStatus.allowed] になるまで初期化しない。
class AgeConfirmationStore extends ChangeNotifier {
  /// [preferences] に保存した生年月を読んで作る。[today] は今日の日付を返す (テストで差し替える)。
  AgeConfirmationStore({required this.preferences, required this.today});

  static const String _birthYearKey = 'ageConfirmation.birthYear';
  static const String _birthMonthKey = 'ageConfirmation.birthMonth';

  /// 生年月の保存先。
  final SharedPreferences preferences;

  /// 今日の日付を返す。
  final DateTime Function() today;

  /// 保存した生まれ年。入力していない時は null。
  int? get birthYear => preferences.getInt(_birthYearKey);

  /// 保存した生まれ月。入力していない時は null。
  int? get birthMonth => preferences.getInt(_birthMonthKey);

  /// 年齢の確認の状態。保存した生年月から毎回求めるため、確認の時に満たなかった人も満たした月から使える。
  AgeConfirmationStatus get status {
    final birthYear = this.birthYear;
    final birthMonth = this.birthMonth;
    if (birthYear == null || birthMonth == null) {
      return AgeConfirmationStatus.unanswered;
    }
    return isOldEnough(
          birthYear: birthYear,
          birthMonth: birthMonth,
          today: today(),
        )
        ? AgeConfirmationStatus.allowed
        : AgeConfirmationStatus.restricted;
  }

  /// 入力した生年月を保存する。
  Future<void> answer({required int birthYear, required int birthMonth}) async {
    await preferences.setInt(_birthYearKey, birthYear);
    await preferences.setInt(_birthMonthKey, birthMonth);
    notifyListeners();
  }

  /// 保存した生年月を消して、年齢の確認をやり直せるようにする (アカウントを削除した後と、DEBUG の開発者メニューが使う。
  /// 削除した後に年齢の確認から始めることは docs/AccountDeletion.md に書いている)。
  Future<void> reset() async {
    await preferences.remove(_birthYearKey);
    await preferences.remove(_birthMonthKey);
    notifyListeners();
  }
}
