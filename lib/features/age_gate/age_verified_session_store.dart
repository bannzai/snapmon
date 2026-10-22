import 'package:flutter/foundation.dart';

/// 年齢の確認を通った後の Firebase へのログイン (匿名ログイン・confirmAge・計測の開始) の状態。
/// ログインが済むまでアプリに入れない (Firestore・Storage の Rules と Functions が ageVerified のクレームを必須にしているため)。
class AgeVerifiedSessionStore extends ChangeNotifier {
  /// [startSession] でログインする。前回の起動で済ませたログインを再開できた時は、その uid を [resumedUid] に渡す。
  AgeVerifiedSessionStore({
    required this.startSession,
    required String? resumedUid,
  }) : _uid = resumedUid;

  /// 生年月を渡してログインし、uid を返す (lib/firebase/age_verified_session.dart の
  /// `startAgeVerifiedSessionWithFirebase` と同じ形。テストで差し替える)。
  final Future<String> Function({
    required int birthYear,
    required int birthMonth,
  })
  startSession;

  String? _uid;
  bool _isStarting = false;
  Object? _error;

  /// ログインした uid。ログインが済むまでは null。
  String? get uid => _uid;

  /// ログインの途中か。
  bool get isStarting => _isStarting;

  /// 最後のログインの失敗。成功した時と、やり直している間は null。
  Object? get error => _error;

  /// 生年月 [birthYear]・[birthMonth] でログインする。済んでいる時と途中の時は何もしない (二重にログインしないため)。
  /// 失敗は [error] に残し、例外として投げない。
  Future<void> start({required int birthYear, required int birthMonth}) async {
    if (_uid != null || _isStarting) {
      return;
    }
    _isStarting = true;
    _error = null;
    notifyListeners();
    try {
      _uid = await startSession(birthYear: birthYear, birthMonth: birthMonth);
    } catch (error) {
      _error = error;
    } finally {
      _isStarting = false;
      notifyListeners();
    }
  }
}
