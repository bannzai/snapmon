import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import 'account_store.dart';
import 'settings_screen.dart';

/// ストアを通さず提供者が直接売るビルド (Web 版。RevenueCat Billing で売り、決済は Stripe) の購入の画面が使うもの。
/// このスコープがあることが直接売るビルドであることを表し、lib/app.dart が Web 版でだけ置く。ストアで売るアプリ (iOS・Android) には置かない。
/// 購入の画面は、これがある時だけ購入の前に連携を確かめ ([accountStoreToLinkBeforePurchase])、特定商取引法に基づく表記へのリンクを出す
/// ([SpecifiedCommercialTransactionsLink])。
class DirectSalesScope extends InheritedWidget {
  /// [accountStore] と [openURL] を [child] の配下に渡す。
  const DirectSalesScope({
    super.key,
    required this.accountStore,
    required this.openURL,
    required super.child,
  });

  /// 購入の前に連携済みかを確かめ、匿名のままならその場で連携するのに使う。
  final AccountStore accountStore;

  /// 特定商取引法に基づく表記を開く。
  final OpenURL openURL;

  /// 直接売るビルドなら配下に置いたスコープ。ストアで売るアプリと、スコープを置いていない widget test では null。
  static DirectSalesScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DirectSalesScope>();

  @override
  bool updateShouldNotify(DirectSalesScope oldWidget) =>
      accountStore != oldWidget.accountStore || openURL != oldWidget.openURL;
}

/// 購入の前に連携が要る時の、連携に使う [AccountStore]。要らない時は null。
/// 要るのは、直接売るビルド ([DirectSalesScope] がある) で匿名のままの時。Web 版の匿名アカウントはブラウザのデータを消すと戻せず、
/// 買ったものも引き継げなくなるため、連携済みのアカウントにだけ売る (documents/DIRECTION.md「決めたこと」の #371 の行)。
/// ストアで売るアプリ、連携済みのアカウント、DEBUG ビルドでログインを飛ばした間 (連携するアカウントが無く、購入は見本だけ) は null。
/// 購入の画面は、null なら待たずに購入を始め、null でなければ [linkBeforePurchase] が true を返した時だけ購入を始める。
AccountStore? accountStoreToLinkBeforePurchase({
  required BuildContext context,
}) {
  // 購入のボタンを押した処理から呼ぶため、build の依存に登録する maybeOf は使わない
  final accountStore = context
      .getInheritedWidgetOfExactType<DirectSalesScope>()
      ?.accountStore;
  return accountStore == null ||
          !accountStore.isSignedIn ||
          accountStore.linkedProviderNames.isNotEmpty
      ? accountStore
      : accountStore;
}

/// 購入を始める代わりに連携の案内を出し、その場で [accountStore] の連携ができた時だけ true を返す。やめた時は false。
Future<bool> linkBeforePurchase({
  required BuildContext context,
  required AccountStore accountStore,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) =>
          _LinkBeforePurchaseDialog(accountStore: accountStore),
    ) ??
    false;

/// 購入の前に出す連携の案内。「データを引き継ぐ」を押すとその場で連携し、連携できたら true で閉じる。
/// 別のデータと連携済みのアカウントを選んだ時は切り替えず (切り替えは図鑑が消えるため、設定画面の確認を通す)、その案内を出して開いたままにする。
class _LinkBeforePurchaseDialog extends StatefulWidget {
  const _LinkBeforePurchaseDialog({required this.accountStore});

  /// 連携に使う。
  final AccountStore accountStore;

  @override
  State<_LinkBeforePurchaseDialog> createState() =>
      _LinkBeforePurchaseDialogState();
}

/// [_LinkBeforePurchaseDialog] の連携の結果。
class _LinkBeforePurchaseDialogState extends State<_LinkBeforePurchaseDialog> {
  /// 連携できなかった理由 (別のデータと連携済みの案内か、失敗の内容)。試す前と試している間は null。
  String? _failureMessage;

  /// 連携し、連携できたら true で閉じる。連携できなかった時は理由を出す。
  /// ボタンを押した処理の中で連携を始めるのは、Web のサインインのポップアップを利用者の操作として開くため。
  Future<void> _link() async {
    setState(() => _failureMessage = null);
    final providerName = await chooseLinkProviderName(
      context: context,
      accountStore: widget.accountStore,
    );
    if (providerName == null || !mounted) {
      return;
    }
    try {
      if (await widget.accountStore.link(providerName: providerName) != null) {
        if (mounted) {
          setState(
            () => _failureMessage = context.l10n.purchaseLinkAlreadyUsed(
              providerName,
            ),
          );
        }
        return;
      }
    } catch (error) {
      if (mounted) {
        setState(() => _failureMessage = error.toString());
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.accountStore,
    builder: (context, _) => AlertDialog(
      key: const Key('link-before-purchase-dialog'),
      title: Text(context.l10n.purchaseLinkRequiredTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            // 選べるサインインが 2 つの時は、設定画面の「データを引き継ぐ」の説明と同じく「Apple / Google」と並べる
            context.l10n.purchaseLinkRequiredMessage(
              widget.accountStore.linkProviderNames.join(' / '),
            ),
          ),
          if (_failureMessage case final failureMessage?)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                failureMessage,
                key: const Key('link-before-purchase-failure'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: widget.accountStore.isWorking
              ? null
              : () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          key: const Key('link-before-purchase-link'),
          onPressed: widget.accountStore.isWorking ? null : _link,
          child: Text(context.l10n.settingsTransferData),
        ),
      ],
    ),
  );
}

/// 特定商取引法に基づく表記 ([specifiedCommercialTransactionsUri]) へのリンク。直接売るビルド ([DirectSalesScope] がある) の
/// 購入の画面にだけ出し、ストアで売るアプリでは何も出さない。
class SpecifiedCommercialTransactionsLink extends StatefulWidget {
  /// リンクを作る。
  const SpecifiedCommercialTransactionsLink({super.key});

  @override
  State<SpecifiedCommercialTransactionsLink> createState() =>
      _SpecifiedCommercialTransactionsLinkState();
}

/// [SpecifiedCommercialTransactionsLink] のページを開けたか。
class _SpecifiedCommercialTransactionsLinkState
    extends State<SpecifiedCommercialTransactionsLink> {
  /// ページを開けなかった時に出す文言。開く前と開けた後は null。
  /// 購入の画面はシートで、裏の画面の SnackBar が隠れるため、リンクの下に出す。
  String? _openFailureMessage;

  /// ページを [openURL] で開き、開けなかった時はそのことを出す。
  Future<void> _open({required OpenURL openURL}) async {
    final openFailureMessage = await openAndDescribeFailure(
      openURL: openURL,
      uri: specifiedCommercialTransactionsUri,
      couldNotOpenMessage: context.l10n.commonCouldNotOpenURL(
        specifiedCommercialTransactionsUri.toString(),
      ),
    );
    if (mounted) {
      setState(() => _openFailureMessage = openFailureMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final openURL = DirectSalesScope.maybeOf(context)?.openURL;
    if (openURL == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            key: const Key('specified-commercial-transactions-link'),
            onPressed: () => _open(openURL: openURL),
            child: Text(context.l10n.purchaseSpecifiedCommercialTransactions),
          ),
          if (_openFailureMessage case final openFailureMessage?)
            Text(
              openFailureMessage,
              key: const Key('specified-commercial-transactions-failure'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
