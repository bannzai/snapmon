import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_text_styles.dart';
import '../age_gate/age_confirmation.dart';
import '../developer_menu/developer_menu_screen.dart';
import '../dex/dex_store.dart';

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
    required this.openUrl,
    required this.isDeveloperMenuEnabled,
  });

  /// 見本データ (開発者メニューが使う)。
  final SampleData sampleData;

  /// 図鑑と手持ち (開発者メニューが使う)。
  final DexStore dexStore;

  /// 年齢の確認 (開発者メニューが使う)。
  final AgeConfirmationStore ageConfirmationStore;

  /// リンクを開く。
  final OpenUrl openUrl;

  /// 開発者メニューの入口を出すか。release ビルドでは [kDebugMode] が const の false のため、
  /// この値に関係なく入口と開発者メニューのコードがビルドから除かれる。widget test は false を渡して出ないことを確かめる。
  final bool isDeveloperMenuEnabled;

  /// [uri] を開き、開けなかった時 (メールのアプリが無い simulator など) はそのことを伝える。
  Future<void> _open({required BuildContext context, required Uri uri}) async {
    if (await openUrl(uri: uri) || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$uri を開けませんでした')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('設定')),
    body: ListView(
      children: [
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
                ),
              ),
            ),
          ),
        ],
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
