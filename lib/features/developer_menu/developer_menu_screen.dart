import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_text_styles.dart';
import '../age_gate/age_confirmation.dart';
import '../age_gate/age_verified_session_store.dart';
import '../capture/generation_screen.dart';
import '../capture/monster_generator.dart';
import '../dex/dex_store.dart';
import '../result/result_screen.dart';

/// 開発者メニューから生成に送る見本の写真の名前とファイル。Simulator にはカメラが無いため、撮影の代わりに使う
/// (出典とライセンスは assets/samples/photos/LICENSES.md)。
const Map<String, String> _samplePhotoAssetPaths = {
  'マグカップ': 'assets/samples/photos/mug.jpg',
  'サボテン': 'assets/samples/photos/cactus.jpg',
  'アヒルのおもちゃ': 'assets/samples/photos/rubber_duck.jpg',
};

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
    required this.monsterGenerator,
  });

  /// 見本データ。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 年齢の確認。
  final AgeConfirmationStore ageConfirmationStore;

  /// 年齢の確認の後のログイン。
  final AgeVerifiedSessionStore ageVerifiedSessionStore;

  /// 生成の呼び出しと計測 (見本の写真からの生成に使う)。
  final MonsterGenerator monsterGenerator;

  void _showMessage({required BuildContext context, required String message}) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));

  /// [assetPath] の見本の写真から生成する。
  Future<void> _generateFromSamplePhoto({
    required BuildContext context,
    required String assetPath,
  }) async {
    final sourcePhoto = (await rootBundle.load(assetPath)).buffer.asUint8List();
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<ResultScreenAction>(
        builder: (context) => GenerationScreen(
          sourcePhoto: sourcePhoto,
          photoSource: GenerationPhotoSource.sample,
          monsterGenerator: monsterGenerator,
          dexStore: dexStore,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('開発者メニュー')),
    body: ListenableBuilder(
      listenable: dexStore,
      builder: (context, _) => ListView(
        children: [
          // サーバーの図鑑に繋いでいる時は、端末だけの見本の図鑑と混ぜない (見本はサーバーに無く、手持ちを保存できないため)
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('見本モンスターを図鑑に投入'),
            subtitle: Text(
              dexStore.isServerBacked
                  ? 'ログイン中は使えない (サーバーの図鑑と混ざるため)'
                  : '図鑑を見本の ${sampleData.monsters.length} 体に置き換え、先頭の 3 体を手持ちにする',
            ),
            enabled: !dexStore.isServerBacked,
            onTap: () {
              dexStore.replaceAll(monsters: sampleData.monsters);
              _showMessage(context: context, message: '見本モンスターを投入しました');
            },
          ),
          for (final MapEntry(key: samplePhotoName, value: assetPath)
              in _samplePhotoAssetPaths.entries)
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: Text('見本の写真から生成: $samplePhotoName'),
              subtitle: const Text('同梱した写真を生成に送る (カメラの無い Simulator 向け)'),
              onTap: () => _generateFromSamplePhoto(
                context: context,
                assetPath: assetPath,
              ),
            ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('図鑑をクリア'),
            subtitle: Text(
              dexStore.isServerBacked
                  ? 'ログイン中は使えない (サーバーの図鑑は消せないため)'
                  : 'いまの図鑑 ${dexStore.monsters.length} 体',
            ),
            enabled: !dexStore.isServerBacked,
            onTap: () {
              dexStore.clear();
              _showMessage(context: context, message: '図鑑をクリアしました');
            },
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('ログイン状態'),
            subtitle: Text(
              ageVerifiedSessionStore.uid == null
                  ? '未ログイン (年齢の確認の後のログインを DEBUG で飛ばした)'
                  : '匿名ログイン (年齢の確認済み) uid: ${ageVerifiedSessionStore.uid}',
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
