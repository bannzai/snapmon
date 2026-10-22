import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_text_styles.dart';
import '../age_gate/age_confirmation.dart';
import '../age_gate/age_verified_session_store.dart';
import '../capture/monster_generator.dart';
import '../developer_menu/developer_menu_screen.dart';
import '../dex/dex_store.dart';
import '../opponent/pvp_client.dart';

/// [uri] を外部のアプリ (ブラウザ・メール) で開き、開けたかを返す。
typedef OpenUrl = Future<bool> Function({required Uri uri});

/// お問い合わせの宛先 (docs/index.html のサポートの連絡先と同じ)。
final Uri contactUri = Uri.parse('mailto:bannzai.app@gmail.com');

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
    required this.ageConfirmationStore,
    required this.ageVerifiedSessionStore,
    required this.monsterGenerator,
    required this.pvpClient,
    required this.openUrl,
    required this.isDeveloperMenuEnabled,
  });

  /// 表示名の読み込みと変更。
  final PvpClient pvpClient;

  /// 見本データ (開発者メニューが使う)。
  final SampleData sampleData;

  /// 図鑑と手持ち (開発者メニューが使う)。
  final DexStore dexStore;

  /// 年齢の確認 (開発者メニューが使う)。
  final AgeConfirmationStore ageConfirmationStore;

  /// 年齢の確認の後のログイン (開発者メニューが使う)。
  final AgeVerifiedSessionStore ageVerifiedSessionStore;

  /// 生成の呼び出しと計測 (開発者メニューが使う)。
  final MonsterGenerator monsterGenerator;

  /// リンクを開く。
  final OpenUrl openUrl;

  /// 開発者メニューの入口を出すか。release ビルドでは [kDebugMode] が const の false のため、
  /// この値に関係なく入口と開発者メニューのコードがビルドから除かれる。widget test は false を渡して出ないことを確かめる。
  final bool isDeveloperMenuEnabled;

  /// [uri] を開き、開けなかった時 (メールのアプリが無い simulator など) はそのことを伝える。
  /// 開くアプリが無い Android では false ではなく例外になるため、例外の時はその内容を出す。
  Future<void> _open({required BuildContext context, required Uri uri}) async {
    final message = await _openAndDescribeFailure(uri: uri);
    if (message == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// [uri] を開く。開けた時は null、開けなかった時は利用者に出す文言を返す。
  Future<String?> _openAndDescribeFailure({required Uri uri}) async {
    try {
      return await openUrl(uri: uri) ? null : '$uri を開けませんでした';
    } on Exception catch (error) {
      return error.toString();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('設定')),
    body: ListView(
      children: [
        _DisplayNameTile(pvpClient: pvpClient),
        const _SectionTitle(title: 'サポート'),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: const Text('お問い合わせ'),
          onTap: () => _open(context: context, uri: contactUri),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('利用規約'),
          onTap: () => _open(context: context, uri: termsUri),
        ),
        ListTile(
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('プライバシーポリシー'),
          onTap: () => _open(context: context, uri: privacyPolicyUri),
        ),
        const _SectionTitle(title: 'アカウント'),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('アカウントの削除について'),
          onTap: () => _open(context: context, uri: accountDeletionUri),
        ),
        // アカウントの削除はアカウント連携 (#17) で実装する。それまでは入口だけを出す
        const ListTile(
          leading: Icon(Icons.delete_outline),
          title: Text('アカウントを削除'),
          subtitle: Text('準備中'),
          enabled: false,
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
                  ageConfirmationStore: ageConfirmationStore,
                  ageVerifiedSessionStore: ageVerifiedSessionStore,
                  monsterGenerator: monsterGenerator,
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
  const _DisplayNameTile({required this.pvpClient});

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
        const _SectionTitle(title: 'プロフィール'),
        ListTile(
          key: const Key('display-name'),
          leading: const Icon(Icons.badge_outlined),
          title: const Text('表示名'),
          subtitle: Text(displayName ?? _loadError?.toString() ?? '読み込んでいます'),
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
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('表示名'),
    content: TextField(
      key: const Key('display-name-field'),
      controller: _controller,
      autofocus: true,
      enabled: !_isSaving,
      decoration: InputDecoration(
        helperText: '対戦の相手に見える名前',
        errorText: _errorText,
        errorMaxLines: 4,
      ),
    ),
    actions: [
      TextButton(
        onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
        child: const Text('やめる'),
      ),
      TextButton(
        key: const Key('display-name-save'),
        onPressed: _isSaving ? null : _save,
        child: const Text('保存'),
      ),
    ],
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
