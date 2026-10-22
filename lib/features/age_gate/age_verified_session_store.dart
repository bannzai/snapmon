import 'package:flutter/foundation.dart';

/// 年齢の確認を通った後の Firebase へのログイン (匿名ログイン・confirmAge・計測の開始) の状態。
/// ログインが済むまでアプリに入れない (Firestore・Storage の Rules と Functions が ageVerified のクレームを必須にしているため)。
class AgeVerifiedSessionStore extends ChangeNotifier {
  /// [startSession] でログインする。前回の起動で済ませたログインを再開できた時は、その uid を [resumedUid] に渡す。
  AgeVerifiedSessionStore({
    required this.startSession,
    required this.endSession,
    required String? resumedUid,
  }) : _uid = resumedUid;

  /// 収集を止めてサインアウトする (lib/firebase/age_verified_session.dart の
  /// `endAgeVerifiedSessionWithFirebase` と同じ形。テストで差し替える)。
  final Future<void> Function() endSession;

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
  bool _isSkippedForDebug = false;

  /// ログインした uid。ログインが済むまでと、[skipForDebug] で飛ばした時は null。
  String? get uid => _uid;

  /// 下タブの画面に入ってよいか。ログインが済んだ時か、DEBUG ビルドでログインを飛ばした時。
  bool get canEnterApp => _uid != null || _isSkippedForDebug;

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

  /// ログインせずに下タブの画面へ入る。DEBUG ビルドの失敗の画面だけが使う
  /// (Functions のデプロイや App Check の登録が済んでいない検証環境でも、ほかの画面の動作確認を止めないため)。
  void skipForDebug() {
    _isSkippedForDebug = true;
    notifyListeners();
  }

  /// ログインを終えて、ログインしていない状態に戻す。開発者メニューの「年齢の確認をやり直す」だけが使う
  /// (やり直した後に初回起動と同じくログインと confirmAge を通すため)。何度呼んでも同じ (冪等)。
  Future<void> resetForDebug() async {
    await endSession();
    _uid = null;
    _error = null;
    _isSkippedForDebug = false;
    notifyListeners();
  }
}
