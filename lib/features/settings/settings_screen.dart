import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../sample/sample_data.dart';
import '../../theme/snapmon_text_styles.dart';
import '../battle/battle_recorder.dart';
import '../capture/monster_generator.dart';
import '../developer_menu/developer_menu_screen.dart';
import '../dex/dex_store.dart';
import '../opponent/pvp_client.dart';
import '../session/session_store.dart';
import '../share/card_sharer.dart';
import 'account_store.dart';

/// [uri] を外部のアプリ (ブラウザ・メール) で開き、開けたかを返す。
typedef OpenUrl = Future<bool> Function({required Uri uri});

/// お問い合わせの宛先 (docs/index.html のサポートの連絡先と同じ)。
final Uri contactUri = Uri.parse('mailto:bannzai.app@gmail.com');

/// 紹介ページ (docs/index.html を GitHub Pages で公開したページ)。共有するカード画像と文章に入れる。
final Uri landingPageUri = Uri.parse('https://bannzai.github.io/snapmon/');

/// 利用規約 (docs/Terms.md を GitHub Pages で公開したページ)。
final Uri termsUri = Uri.parse('https://bannzai.github.io/snapmon/Terms');

/// プライバシーポリシー (docs/PrivacyPolicy.md を GitHub Pages で公開したページ)。
final Uri privacyPolicyUri = Uri.parse(
  'https://bannzai.github.io/snapmon/PrivacyPolicy',
);

/// アカウントの削除の手順 (docs/AccountDeletion.md を GitHub Pages で公開したページ)。
final Uri accountDeletionUri = Uri.parse(
  'https://bannzai.github.io/snapmon/AccountDeletion',
);

/// 設定画面。図鑑・撮る・対戦の各画面の右上の歯車から開く (モックに設定画面は無いため置き場所は agent が決めた)。
class SettingsScreen extends StatelessWidget {
  /// 設定画面を作る。
  const SettingsScreen({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.sessionStore,
    required this.monsterGenerator,
    required this.pvpClient,
    required this.cardSharer,
    required this.openUrl,
    required this.isDeveloperMenuEnabled,
    required this.accountStore,
    required this.battleRecorder,
  });

  /// バトルの記録と計測 (開発者メニューの見本の写真から始めた初回のバトルが使う)。
  final BattleRecorder battleRecorder;

  /// 表示名の読み込みと変更 (開発者メニューの見本の写真から始めた初回のバトルの相手の取得にも使う)。
  final PvpClient pvpClient;

  /// 見本データ (開発者メニューが使う)。
  final SampleData sampleData;

  /// 図鑑と手持ち (開発者メニューと、連携済みのアカウントへの切り替えの確認で消える数の表示が使う)。
  final DexStore dexStore;

  /// ログイン (開発者メニューが使う)。
  final SessionStore sessionStore;

  /// 生成の呼び出しと計測 (開発者メニューが使う)。
  final MonsterGenerator monsterGenerator;

  /// 図鑑のカードの共有に使う関数の組 (開発者メニューが使う)。
  final CardSharer cardSharer;

  /// リンクを開く。
  final OpenUrl openUrl;

  /// 開発者メニューの入口を出すか。release ビルドでは [kDebugMode] が const の false のため、
  /// この値に関係なく入口と開発者メニューのコードがビルドから除かれる。widget test は false を渡して出ないことを確かめる。
  final bool isDeveloperMenuEnabled;

  /// アカウントの連携 (データを引き継ぐ) と削除。
  final AccountStore accountStore;

  void _showMessage({required BuildContext context, required String message}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  /// 「データを引き継ぐ」。いまの匿名アカウントに連携し、別の端末で連携済みなら切り替えてよいかを確かめてから切り替える。
  Future<void> _link({required BuildContext context}) async {
    final Future<String> Function()? signInToLinkedAccount;
    try {
      signInToLinkedAccount = await accountStore.link();
    } catch (error) {
      if (context.mounted) {
        _showMessage(context: context, message: error.toString());
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    if (signInToLinkedAccount == null) {
      _showMessage(
        context: context,
        message: context.l10n.settingsLinked(accountStore.linkProviderName),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsSwitchAccountTitle),
        content: Text(
          context.l10n.settingsSwitchAccountMessage(
            accountStore.linkProviderName,
            dexStore.monsters.length,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.settingsSwitchAccountConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await accountStore.switchToLinkedAccount(
        signInToLinkedAccount: signInToLinkedAccount,
      );
    } catch (error) {
      if (context.mounted) {
        _showMessage(context: context, message: error.toString());
      }
      return;
    }
    if (context.mounted) {
      _showMessage(
        context: context,
        message: context.l10n.settingsSwitchedAccount,
      );
    }
  }

  /// 「アカウントを削除」。確かめてから消し、消せたらタイトル画面 (アプリのルート) に戻す。
  Future<void> _delete({required BuildContext context}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.settingsDeleteAccountTitle),
        content: Text(context.l10n.settingsDeleteAccountMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(context.l10n.settingsDeleteAccountConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    try {
      await accountStore.delete();
    } catch (error) {
      if (context.mounted) {
        _showMessage(context: context, message: error.toString());
      }
      return;
    }
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// [uri] を開き、開けなかった時 (メールのアプリが無い simulator など) はそのことを伝える。
  /// 開くアプリが無い Android では false ではなく例外になるため、例外の時はその内容を出す。
  Future<void> _open({required BuildContext context, required Uri uri}) async {
    final message = await _openAndDescribeFailure(
      uri: uri,
      couldNotOpenMessage: context.l10n.commonCouldNotOpenUrl(uri.toString()),
    );
    if (message == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// [uri] を開く。開けた時は null、開けなかった時は利用者に出す文言 (false が返った時は [couldNotOpenMessage]) を返す。
  Future<String?> _openAndDescribeFailure({
    required Uri uri,
    required String couldNotOpenMessage,
  }) async {
    try {
      return await openUrl(uri: uri) ? null : couldNotOpenMessage;
    } on Exception catch (error) {
      return error.toString();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.settingsTitle)),
    body: ListView(
      children: [
        // 「データを引き継ぐ」で別のアカウントに切り替わると uid が変わるため、uid ごとに作り直して表示名を読み直す
        // (前の uid の表示名を出したまま保存させないため)
        ListenableBuilder(
          listenable: accountStore.sessionStore,
          builder: (context, _) => _DisplayNameTile(
            key: ValueKey(accountStore.sessionStore.uid),
            pvpClient: pvpClient,
          ),
        ),
        _SectionTitle(title: context.l10n.settingsSupportSection),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(context.l10n.commonContact),
          onTap: () => _open(context: context, uri: contactUri),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(context.l10n.settingsTerms),
          onTap: () => _open(context: context, uri: termsUri),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: Text(context.l10n.settingsPrivacyPolicy),
          onTap: () => _open(context: context, uri: privacyPolicyUri),
        ),
        _SectionTitle(title: context.l10n.settingsAccountSection),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: Text(context.l10n.settingsAboutAccountDeletion),
          onTap: () => _open(context: context, uri: accountDeletionUri),
        ),
        // DEBUG でログインを飛ばした時は、連携・削除するアカウントが無いため押せなくする
        ListenableBuilder(
          listenable: Listenable.merge([
            accountStore,
            accountStore.sessionStore,
          ]),
          builder: (context, _) {
            final linkedProviderNames = accountStore.linkedProviderNames;
            final canOperate =
                accountStore.isSignedIn && !accountStore.isWorking;
            return Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.sync_outlined),
                  title: Text(context.l10n.settingsTransferData),
                  subtitle: Text(
                    linkedProviderNames.isEmpty
                        ? context.l10n.settingsTransferDataDescription(
                            accountStore.linkProviderName,
                          )
                        : context.l10n.settingsLinkedWith(
                            linkedProviderNames.join(
                              context.l10n.settingsProviderSeparator,
                            ),
                          ),
                  ),
                  enabled: canOperate && linkedProviderNames.isEmpty,
                  onTap: () => _link(context: context),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(context.l10n.settingsDeleteAccount),
                  enabled: canOperate,
                  onTap: () => _delete(context: context),
                ),
              ],
            );
          },
        ),
        if (kDebugMode && isDeveloperMenuEnabled) ...[
          const _SectionTitle(title: '開発'),
          ListTile(
            leading: const Icon(Icons.build_outlined),
            title: const Text('開発者メニュー'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => DeveloperMenuScreen(
                  sampleData: sampleData,
                  dexStore: dexStore,
                  sessionStore: sessionStore,
                  monsterGenerator: monsterGenerator,
                  cardSharer: cardSharer,
                  pvpClient: pvpClient,
                  battleRecorder: battleRecorder,
                  openUrl: openUrl,
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

/// 対戦の相手に見える表示名の節。名前はサーバー (Functions の getDisplayName) が決めた値を出し、押すと変えられる。
/// ログインが無い時 (DEBUG ビルドでログインを飛ばした時) は名前が無いため節を出さない。
class _DisplayNameTile extends StatefulWidget {
  const _DisplayNameTile({required super.key, required this.pvpClient});

  final PvpClient pvpClient;

  @override
  State<_DisplayNameTile> createState() => _DisplayNameTileState();
}

class _DisplayNameTileState extends State<_DisplayNameTile> {
  /// 今の表示名。読み込み中・ログインが無い時は null。
  String? _displayName;

  /// 読み込みの失敗。
  Object? _loadError;

  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final displayName = await widget.pvpClient.fetchDisplayName();
      if (mounted) {
        setState(() {
          _displayName = displayName;
          _loadError = null;
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _loadError = error;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _edit({required String currentDisplayName}) async {
    final savedDisplayName = await showDialog<String>(
      context: context,
      // 保存の途中に外を押して閉じると、保存できた名前が画面に反映されないため、閉じるのは「やめる」だけにする
      barrierDismissible: false,
      builder: (context) => _DisplayNameDialog(
        initialDisplayName: currentDisplayName,
        updateDisplayName: widget.pvpClient.updateDisplayName,
      ),
    );
    if (savedDisplayName != null && mounted) {
      setState(() => _displayName = savedDisplayName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _displayName;
    if (!_isLoading && displayName == null && _loadError == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(title: context.l10n.settingsProfileSection),
        ListTile(
          key: const Key('display-name'),
          leading: const Icon(Icons.badge_outlined),
          title: Text(context.l10n.settingsDisplayName),
          subtitle: Text(
            displayName ??
                _loadError?.toString() ??
                context.l10n.settingsDisplayNameLoading,
          ),
          trailing: displayName == null ? null : const Icon(Icons.edit),
          onTap: displayName == null
              ? (_loadError == null ? null : _load)
              : () => _edit(currentDisplayName: displayName),
        ),
      ],
    );
  }
}

/// 表示名を入力するダイアログ。保存できたら保存した名前で閉じ、できなければ理由をそのまま出して閉じない。
class _DisplayNameDialog extends StatefulWidget {
  const _DisplayNameDialog({
    required this.initialDisplayName,
    required this.updateDisplayName,
  });

  final String initialDisplayName;
  final Future<String> Function({required String displayName})
  updateDisplayName;

  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialDisplayName,
  );
  bool _isSaving = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _errorText = null;
    });
    try {
      final savedDisplayName = await widget.updateDisplayName(
        displayName: _controller.text,
      );
      if (mounted) {
        Navigator.of(context).pop(savedDisplayName);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorText = error.toString();
        });
      }
    }
  }

  @override
  // 保存の途中は戻る操作でも閉じさせない (保存できた名前を画面に反映できなくなるため)
  Widget build(BuildContext context) => PopScope(
    canPop: !_isSaving,
    child: AlertDialog(
      title: Text(context.l10n.settingsDisplayName),
      content: TextField(
        key: const Key('display-name-field'),
        controller: _controller,
        autofocus: true,
        enabled: !_isSaving,
        decoration: InputDecoration(
          helperText: context.l10n.settingsDisplayNameHelper,
          errorText: _errorText,
          errorMaxLines: 4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          key: const Key('display-name-save'),
          onPressed: _isSaving ? null : _save,
          child: Text(context.l10n.settingsDisplayNameSave),
        ),
      ],
    ),
  );
}

/// 設定の節の見出し。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
    child: Text(title, style: SnapmonTextStyles.caption),
  );
}
