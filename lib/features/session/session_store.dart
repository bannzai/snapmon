import 'package:flutter/foundation.dart';

/// Firebase へのログイン (App Check・匿名ログイン・計測の開始) の状態。
/// ログインが済むまでアプリに入れない (Firestore・Storage の Rules と Functions がログインを必須にしているため)。
class SessionStore extends ChangeNotifier {
  /// [startSession] でログインする。前回の起動で済ませたログインを再開できた時は、その uid を [resumedUid] に渡す。
  SessionStore({
    required this.startSession,
    required this.endSession,
    required String? resumedUid,
  }) : _uid = resumedUid;

  /// 収集を止めてサインアウトする (lib/firebase/session.dart の `endSessionWithFirebase` と同じ形。テストで差し替える)。
  final Future<void> Function() endSession;

  /// ログインし、uid を返す (lib/firebase/session.dart の `startSessionWithFirebase` と同じ形。テストで差し替える)。
  final Future<String> Function() startSession;

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

  /// ログインする。済んでいる時と途中の時は何もしない (二重にログインしないため)。
  /// 失敗は [error] に残し、例外として投げない。
  Future<void> start() async {
    if (_uid != null || _isStarting) {
      return;
    }
    _isStarting = true;
    _error = null;
    notifyListeners();
    try {
      _uid = await startSession();
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

  /// 連携済みのアカウントに切り替えた後に、ログインした uid を [uid] にする (設定画面の「データを引き継ぐ」)。
  void switchUid({required String uid}) {
    _uid = uid;
    notifyListeners();
  }

  /// ログインを終えて、ログインしていない状態に戻す。アカウントを削除した後と、連携済みのアカウントへの切り替えに失敗した後と、
  /// 開発者メニューの「新しいアカウントで始め直す」が使う (アプリのルートがログインの画面に戻り、新しい匿名アカウントで始まる)。
  /// 何度呼んでも同じ (冪等)。
  Future<void> reset() async {
    await endSession();
    _uid = null;
    _error = null;
    _isSkippedForDebug = false;
    notifyListeners();
  }
}
