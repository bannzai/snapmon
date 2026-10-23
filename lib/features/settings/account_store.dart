import 'package:flutter/foundation.dart';

import '../session/session_store.dart';

/// 設定画面の「データを引き継ぐ」(匿名アカウントへの Apple / Google の連携) と「アカウントを削除」の状態と操作。
/// Firebase の実体 (lib/firebase/account.dart) は引数で受け取る (Firebase と切り離して単体テストするため)。
class AccountStore extends ChangeNotifier {
  /// 連携と削除の状態を作る。
  AccountStore({
    required this.sessionStore,
    required this.linkProviderName,
    required this.readLinkedProviderNames,
    required this.linkAccount,
    required this.discardCurrentAccount,
    required this.deleteAccount,
  });

  /// ログイン。切り替え・削除の後に uid を差し替える・ログインを終える。
  final SessionStore sessionStore;

  /// このプラットフォームで連携に使うサインインの名前 (`accountLinkProviderNameForPlatform`)。
  final String linkProviderName;

  /// いまのユーザーが連携済みのサインインの名前を返す (`linkedProviderNamesWithFirebase`)。
  final List<String> Function() readLinkedProviderNames;

  /// いまの匿名アカウントに連携する。連携できたら null、別の端末で連携済みなら連携済みのアカウントにサインインして uid を返す関数を返す
  /// (`linkAccountWithFirebase`)。
  final Future<Future<String> Function()?> Function() linkAccount;

  /// いまのアカウントのサーバーのデータと Auth のユーザーを消す (`deleteCurrentAccountOnServerWithFirebase`)。
  /// 連携済みのアカウントに切り替える前に、いまの匿名アカウントを捨てるのに使う。
  final Future<void> Function() discardCurrentAccount;

  /// いまのアカウントを消す。連携の取り消しを含む (`deleteAccountWithFirebase`)。
  final Future<void> Function() deleteAccount;

  bool _isWorking = false;

  /// 連携・切り替え・削除の途中か。途中は次の操作を受け付けない (二重に呼ばないため)。
  bool get isWorking => _isWorking;

  /// いまのユーザーが連携済みのサインインの名前。匿名のままなら空。
  List<String> get linkedProviderNames => readLinkedProviderNames();

  /// ログインしていて (DEBUG でログインを飛ばしていない)、連携も削除もできるか。
  bool get isSignedIn => sessionStore.uid != null;

  Future<T> _work<T>(Future<T> Function() operation) async {
    if (_isWorking) {
      throw StateError('ほかの操作が終わるまで待ってください');
    }
    _isWorking = true;
    notifyListeners();
    try {
      return await operation();
    } finally {
      _isWorking = false;
      notifyListeners();
    }
  }

  /// いまの匿名アカウントに連携する。連携できたら null を返す (uid は変わらず、図鑑はそのまま残る)。
  /// 別の端末で連携済みの時は、[switchToLinkedAccount] に渡す関数を返す。
  Future<Future<String> Function()?> link() => _work(linkAccount);

  /// いまの匿名アカウントを捨てて、[signInToLinkedAccount] で連携済みのアカウントに切り替える
  /// (端末の匿名の図鑑を連携済みのアカウントに合流させない。documents/adr/0003-account-link-and-deletion.md)。
  /// 捨てた後のサインインに失敗した時は、ログインを終えて新しい匿名アカウントから始め直させてから投げる
  /// (連携済みのアカウントはサーバーに残るため、もう一度「データを引き継ぐ」を選べば切り替えられる)。
  Future<void> switchToLinkedAccount({
    required Future<String> Function() signInToLinkedAccount,
  }) => _work(() async {
    await discardCurrentAccount();
    final String uid;
    try {
      uid = await signInToLinkedAccount();
    } catch (_) {
      await sessionStore.reset();
      rethrow;
    }
    sessionStore.switchUid(uid: uid);
  });

  /// いまのアカウントを消し、ログインを終える (アプリのルートがタイトル画面に戻り、裏で新しい匿名アカウントにログインする。docs/AccountDeletion.md)。
  /// 削除に失敗した時は、ログインを続けたまま投げる (もう一度削除を選べば続きから消せる)。
  Future<void> delete() => _work(() async {
    await deleteAccount();
    await sessionStore.reset();
  });
}
