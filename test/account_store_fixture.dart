import 'package:snapmon/features/session/session_store.dart';
import 'package:snapmon/features/settings/account_store.dart';

/// 購入の前の連携の確認のテストが使う、Firebase を呼ばない連携の代わり。
class FakeAccountLink {
  /// ログインしていて、匿名のまま ([isLinked] が false) か、Google と連携済みのアカウントとして始める。
  FakeAccountLink({required bool isLinked})
    : linkedProviderNames = [if (isLinked) 'Google'],
      _resumedUid = 'uid-anonymous';

  /// DEBUG ビルドでログインを飛ばした間 (uid が無く、連携するアカウントが無い) として始める。
  FakeAccountLink.sessionSkippedForDebug()
    : linkedProviderNames = [],
      _resumedUid = null;

  /// ログインしている uid。ログインを飛ばした間は null。
  final String? _resumedUid;

  /// いまのユーザーが連携済みのサインインの名前。匿名のままなら空。「データを引き継ぐ」が連携できたら Google を足す。
  final List<String> linkedProviderNames;

  /// 「データを引き継ぐ」が呼ばれた回数。
  int linkCallCount = 0;

  /// 「データを引き継ぐ」の結果。連携できたら null、別のデータと連携済みなら切り替える関数を返す ([AccountStore.linkAccount] と同じ)。
  /// 既定は連携できる。
  Future<Future<String> Function()?> Function() linkAccount = () async => null;

  /// この連携の状態を読む [AccountStore]。
  AccountStore accountStore() => AccountStore(
    sessionStore: SessionStore(
      startSession: () async => 'uid-new',
      endSession: () async {},
      resumedUid: _resumedUid,
    ),
    linkProviderName: 'Google',
    readLinkedProviderNames: () => linkedProviderNames,
    linkAccount: () async {
      linkCallCount++;
      final signInToLinkedAccount = await linkAccount();
      if (signInToLinkedAccount == null) {
        linkedProviderNames.add('Google');
      }
      return signInToLinkedAccount;
    },
    discardCurrentAccount: () async {},
    deleteAccount: () async {},
  );
}
