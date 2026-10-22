import 'package:flutter/material.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_text_styles.dart';
import '../age_gate/age_confirmation.dart';
import '../age_gate/age_verified_session_store.dart';
import '../capture/sample_generation.dart';
import '../dex/dex_store.dart';
import '../result/result_screen.dart';

/// DEBUG ビルド限定の開発者メニュー。到達困難な状態 (図鑑の数・手持ち・年齢の確認のやり直し) をここで作る
/// (AGENTS.md「ビルド・テスト・検証方法」。リモートの simulator では起動引数を渡しにくいため)。
/// 入口は設定画面にあり、release ビルドでは入口ごと除かれる ([SettingsScreen.isDeveloperMenuEnabled])。
class DeveloperMenuScreen extends StatelessWidget {
  /// 開発者メニューを作る。
  const DeveloperMenuScreen({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.ageConfirmationStore,
    required this.ageVerifiedSessionStore,
  });

  /// 見本データ。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 年齢の確認。
  final AgeConfirmationStore ageConfirmationStore;

  /// 年齢の確認の後のログイン。
  final AgeVerifiedSessionStore ageVerifiedSessionStore;

  void _showMessage({required BuildContext context, required String message}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('開発者メニュー')),
    body: ListenableBuilder(
      listenable: dexStore,
      builder: (context, _) => ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('見本モンスターを図鑑に投入'),
            subtitle: Text(
              '図鑑を見本の ${sampleData.monsters.length} 体に置き換え、先頭の 3 体を手持ちにする',
            ),
            onTap: () {
              dexStore.replaceAll(monsters: sampleData.monsters);
              _showMessage(context: context, message: '見本モンスターを投入しました');
            },
          ),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('見本画像からモンスターを生成'),
            subtitle: const Text('生成を実装するまでは見本のモンスターが生まれる'),
            onTap: () {
              // builder は再び呼ばれることがあるため、生成は push の前に 1 回だけ行う
              final monster = generateSampleMonster(
                sampleData: sampleData,
                dexStore: dexStore,
              );
              Navigator.of(context).push(
                MaterialPageRoute<ResultScreenAction>(
                  builder: (context) => ResultScreen(
                    monster: monster,
                    sampleData: sampleData,
                    dexStore: dexStore,
                    isNewlyBorn: true,
                  ),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('図鑑をクリア'),
            subtitle: Text('いまの図鑑 ${dexStore.monsters.length} 体'),
            onTap: () {
              dexStore.clear();
              _showMessage(context: context, message: '図鑑をクリアしました');
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('ログイン状態'),
            subtitle: Text(
              '匿名ログイン (年齢の確認済み) uid: ${ageVerifiedSessionStore.uid}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('年齢の確認をやり直す'),
            subtitle: const Text('保存した生年月を消して最初の画面に戻る'),
            onTap: () async {
              Navigator.of(context).popUntil((route) => route.isFirst);
              await ageConfirmationStore.reset();
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Text(
              'このメニューは DEBUG ビルドだけに出る',
              style: SnapmonTextStyles.small,
            ),
          ),
        ],
      ),
    ),
  );
}
