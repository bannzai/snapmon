import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_text_styles.dart';
import '../battle/battle_recorder.dart';
import '../capture/generation_screen.dart';
import '../capture/monster_generator.dart';
import '../dex/dex_store.dart';
import '../opponent/pvp_client.dart';
import '../result/result_screen.dart';
import '../session/session_store.dart';
import '../share/card_sharer.dart';

/// 開発者メニューから生成に送る見本の写真の名前とファイル。Simulator にはカメラが無いため、撮影の代わりに使う
/// (出典とライセンスは assets/samples/photos/LICENSES.md)。
const Map<String, String> _samplePhotoAssetPaths = {
  'マグカップ': 'assets/samples/photos/mug.jpg',
  'サボテン': 'assets/samples/photos/cactus.jpg',
  'アヒルのおもちゃ': 'assets/samples/photos/rubber_duck.jpg',
};

/// DEBUG ビルド限定の開発者メニュー。到達困難な状態 (図鑑の数・手持ち・新しいアカウントでの始め直し) をここで作る
/// (AGENTS.md「ビルド・テスト・検証方法」。リモートの simulator では起動引数を渡しにくいため)。
/// 入口は設定画面にあり、release ビルドでは入口ごと除かれる ([SettingsScreen.isDeveloperMenuEnabled])。
class DeveloperMenuScreen extends StatelessWidget {
  /// 開発者メニューを作る。
  const DeveloperMenuScreen({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.sessionStore,
    required this.monsterGenerator,
    required this.cardSharer,
    required this.pvpClient,
    required this.battleRecorder,
  });

  /// 見本の写真から始めた初回のバトル (手持ちが空の時) の相手の取得。
  final PvpClient pvpClient;

  /// 見本の写真から始めた初回のバトル (手持ちが空の時) の記録と計測。
  final BattleRecorder battleRecorder;

  /// 見本データ。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// ログイン。
  final SessionStore sessionStore;

  /// 生成の呼び出しと計測 (見本の写真からの生成に使う)。
  final MonsterGenerator monsterGenerator;

  /// 見本の写真から生まれた画面の、図鑑のカードの共有に使う関数の組。
  final CardSharer cardSharer;

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
          cardSharer: cardSharer,
          startsFirstBattle: dexStore.party.isEmpty,
          sampleData: sampleData,
          pvpClient: pvpClient,
          battleRecorder: battleRecorder,
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
              sessionStore.uid == null
                  ? '未ログイン (ログインを DEBUG で飛ばした)'
                  : '匿名ログイン uid: ${sessionStore.uid}',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('新しいアカウントで始め直す'),
            subtitle: const Text('ログインを終えてタイトルに戻り 新しい匿名アカウントでログインする'),
            onTap: () async {
              Navigator.of(context).popUntil((route) => route.isFirst);
              await sessionStore.reset();
            },
          ),
          // ログインに成功しても App Check の debug token が未登録だと Functions に拒否されるため、
          // サーバーに繋がずに見本の図鑑・バトルを確かめる経路を残す
          ListTile(
            leading: const Icon(Icons.cloud_off_outlined),
            title: const Text('ログインせずに使う'),
            subtitle: const Text(
              'ログインを終えてタイトルに戻り サーバーに繋がずに見本で動作を確かめる\n生成は見本のモンスターで置き換える',
            ),
            onTap: () async {
              Navigator.of(context).popUntil((route) => route.isFirst);
              await sessionStore.reset();
              // タイトルが裏のログインを始める前に、ログインを飛ばした状態にする
              sessionStore.skipForDebug();
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
