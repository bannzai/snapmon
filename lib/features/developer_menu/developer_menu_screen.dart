import 'dart:async';

import 'package:flutter/material.dart';

import '../../common_ui/scene_route.dart';

import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_text_styles.dart';
import '../action_card/action_card_client.dart';
import '../action_card/action_card_store.dart';
import '../battle/battle_recorder.dart';
import '../capture/generation_screen.dart';
import '../capture/monster_generator.dart';
import '../capture/subject_mask.dart';
import '../capture/ticket_purchase_sheet.dart';
import '../dex/dex_store.dart';
import '../opponent/pvp_client.dart';
import '../result/result_screen.dart';
import '../session/session_store.dart';
import '../settings/settings_screen.dart';
import '../share/card_sharer.dart';
import 'move_effect_preview_screen.dart';

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

  /// 手持ちが空の時の初回のバトルの前の定義の読み直しに渡す。
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

  /// [monsterGenerator] の OS の切り出しだけを、写真の中央の短辺いっぱいの正方形を被写体として返すものに替えた [MonsterGenerator]。
  /// Simulator では Vision の前景のマスクが返らず (#242 の simtunnel で確かめた)、OS の切り出しが被写体を見つけた時の画面
  /// (切り抜くかを選ぶ画面) に届かないため、被写体が見つかったことにして確かめる。
  MonsterGenerator _monsterGeneratorWithSubjectFound() => MonsterGenerator(
    listCameras: monsterGenerator.listCameras,
    openAppSettings: monsterGenerator.openAppSettings,
    pickAlbumPhoto: monsterGenerator.pickAlbumPhoto,
    preparePhoto: monsterGenerator.preparePhoto,
    createSubjectMask: ({required photo}) {
      final photoSize = photoPixelSize(photo: photo);
      return monsterGenerator.createSquareMask(
        photo: photo,
        crop: initialSquareCrop(
          photoWidth: photoSize.width,
          photoHeight: photoSize.height,
        ),
      );
    },
    createSquareMask: monsterGenerator.createSquareMask,
    createCutoutPreview: monsterGenerator.createCutoutPreview,
    createRequestID: monsterGenerator.createRequestID,
    uploadPhoto: monsterGenerator.uploadPhoto,
    uploadMask: monsterGenerator.uploadMask,
    requestGeneration: monsterGenerator.requestGeneration,
    fetchGeneration: monsterGenerator.fetchGeneration,
    fetchTicketPackages: monsterGenerator.fetchTicketPackages,
    purchaseTicketPackage: monsterGenerator.purchaseTicketPackage,
    syncTicketPurchases: monsterGenerator.syncTicketPurchases,
    watchGenerationTickets: monsterGenerator.watchGenerationTickets,
    logEvent: monsterGenerator.logEvent,
  );

  /// [assetPath] の見本の写真から [generator] で生成する。[letsUserChooseSubjectRange] は [GenerationScreen.letsUserChooseSubjectRange] に渡す。
  Future<void> _generateFromSamplePhoto({
    required BuildContext context,
    required String assetPath,
    required bool letsUserChooseSubjectRange,
    required MonsterGenerator generator,
  }) async {
    final sourcePhoto = (await rootBundle.load(assetPath)).buffer.asUint8List();
    if (!context.mounted) {
      return;
    }
    await Navigator.of(context).push(
      sceneRoute<ResultScreenAction>(
        builder: (context) => GenerationScreen(
          sourcePhoto: sourcePhoto,
          photoSource: GenerationPhotoSource.sample,
          letsUserChooseSubjectRange: letsUserChooseSubjectRange,
          monsterGenerator: generator,
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
              subtitle: const Text(
                '同梱した写真を生成に送る (カメラの無い Simulator 向け)\n自動の切り出しで被写体が見つかれば選ばずに切り抜き 使えない時は写真全体で送る',
              ),
              onTap: () => _generateFromSamplePhoto(
                context: context,
                assetPath: assetPath,
                letsUserChooseSubjectRange: false,
                generator: monsterGenerator,
              ),
            ),
          // Action Card は Simulator で購入できず、ログインを飛ばした端末は Functions を呼べないため、ログインを飛ばした間だけ
          // 端末だけの見本 (lib/sample/sample_action_cards.dart) で表示・購入・技のランクを作る。見本はアプリ全体の Action Card を置き換える
          if (ActionCardScope.maybeOf(context)?.sampleActionCards
              case final sampleActionCards?) ...[
            ValueListenableBuilder(
              valueListenable: sampleActionCards.isActionCardsVisible,
              builder: (context, isActionCardsVisible, _) => SwitchListTile(
                key: const Key('developer-action-card-visible'),
                secondary: const Icon(Icons.style_outlined),
                title: const Text('Action Card の見本の表示の切り替え'),
                subtitle: Text(
                  dexStore.isServerBacked
                      ? 'ログイン中は使えない (サーバーの Action Card を置き換えないため)'
                      : 'actionCardsVisible の代わり\nオンにした時に技のランクの表が無ければ見本の master から作る',
                ),
                value: isActionCardsVisible,
                onChanged: dexStore.isServerBacked
                    ? null
                    : (value) {
                        sampleActionCards.isActionCardsVisible.value = value;
                        if (value &&
                            sampleActionCards.rankByMoveID.value == null) {
                          sampleActionCards.loadSampleMoveRanks(
                            master: dexStore.definitions,
                          );
                        }
                      },
              ),
            ),
            for (final rank in actionCardRanks)
              ListTile(
                key: Key('developer-action-card-unassigned-$rank'),
                leading: const Icon(Icons.add_card_outlined),
                title: Text('技に結び付いていないランク $rank の購入を 1 件足す'),
                subtitle: const Text('選び直しの導線を確かめるため'),
                enabled: !dexStore.isServerBacked,
                onTap: () {
                  sampleActionCards.addUnassignedPurchase(rank: rank);
                  _showMessage(
                    context: context,
                    message: 'ランク $rank の購入を足しました',
                  );
                },
              ),
            ValueListenableBuilder(
              valueListenable:
                  sampleActionCards.blocksReservedMoveBeforeArrival,
              builder: (context, blocksReservedMove, _) => SwitchListTile(
                key: const Key('developer-action-card-block-reserved-move'),
                secondary: const Icon(Icons.trending_up),
                title: const Text('次の購入が届く前に選んだ技を受け取れなくする'),
                subtitle: const Text(
                  '技のランクを 1 つ上げる (ランク 3 の技は同じ技を先に受け取ったことにする)\n技を受け取れずに購入が残る流れを確かめるため',
                ),
                value: blocksReservedMove,
                onChanged: dexStore.isServerBacked
                    ? null
                    : (value) =>
                          sampleActionCards
                                  .blocksReservedMoveBeforeArrival
                                  .value =
                              value,
              ),
            ),
          ],
          // ストアに商品が無い間と Simulator で、購入画面の見た目と流れを確かめるため。見本の package と見本の購入を使い、ストアも RevenueCat も呼ばない
          ListTile(
            leading: const Icon(Icons.confirmation_number_outlined),
            title: const Text('生成チケットの購入画面の見本を開く'),
            subtitle: const Text('見本の価格を出す。買うと 3 秒後に残高が 10 枚になる'),
            onTap: () {
              final sampleGenerationTickets = StreamController<int>();
              showTicketPurchaseSheet(
                context: context,
                packages: const [
                  Package(
                    'ticket10',
                    PackageType.custom,
                    StoreProduct(
                      'sample10',
                      '',
                      '生成チケット 10 回 (見本)',
                      0,
                      '見本の価格',
                      '',
                    ),
                    PresentedOfferingContext('sample', null, null),
                  ),
                ],
                // 買った時から数える (受け取りを待つ表示を見られるように)
                purchaseTicketPackage: ({required package}) async {
                  Timer(const Duration(seconds: 3), () {
                    if (!sampleGenerationTickets.isClosed) {
                      sampleGenerationTickets.add(10);
                    }
                  });
                  return TicketPurchaseResult.purchased;
                },
                watchGenerationTickets: () => sampleGenerationTickets.stream,
                logEvent: ({required event, required parameters}) async {},
              ).whenComplete(sampleGenerationTickets.close);
            },
          ),
          // アルバムのファイル選択を自動の操作で通しにくい Web (webtunnel) と Simulator で、切り抜くかを選ぶ画面と範囲を決める画面を確かめるため
          ListTile(
            leading: const Icon(Icons.crop_outlined),
            title: Text(
              '見本の写真から範囲を決めて生成: ${_samplePhotoAssetPaths.keys.first}',
            ),
            subtitle: const Text(
              'アルバムから選んだ時と同じく 自動の切り出しで被写体が見つかれば切り抜くかを選ぶ画面を\n見つからない・使えない時は範囲を決める画面を出す',
            ),
            onTap: () => _generateFromSamplePhoto(
              context: context,
              assetPath: _samplePhotoAssetPaths.values.first,
              letsUserChooseSubjectRange: true,
              generator: monsterGenerator,
            ),
          ),
          // Simulator では Vision の前景のマスクが返らないため、被写体が見つかった時の切り抜くかを選ぶ画面を確かめる
          ListTile(
            leading: const Icon(Icons.content_cut_outlined),
            title: Text(
              '見本の写真から切り抜くかを選んで生成: ${_samplePhotoAssetPaths.keys.first}',
            ),
            subtitle: const Text(
              '写真の中央の正方形を自動の切り出しが見つけた被写体として\n切り抜くかを選ぶ画面を出す\n切り抜いた絵で作ると 正方形のマスクが ios_subject として生成のレコードに残る',
            ),
            onTap: () => _generateFromSamplePhoto(
              context: context,
              assetPath: _samplePhotoAssetPaths.values.first,
              letsUserChooseSubjectRange: true,
              generator: _monsterGeneratorWithSubjectFound(),
            ),
          ),
          // 全属性の技を当てるにはバトルを何度も重ねる必要があるため、エフェクトだけを見本のモンスターに当てて確かめる
          ListTile(
            leading: const Icon(Icons.flare_outlined),
            title: const Text('技のエフェクトの見本'),
            subtitle: const Text('選んだ技のエフェクトを見本のモンスターに当て続ける'),
            onTap: () => Navigator.of(context).push(
              sceneRoute<void>(
                builder: (context) => MoveEffectPreviewScreen(
                  playerMonster: sampleData.monsters[0],
                  opponentMonster: sampleData.monsters[1],
                  cardSharer: cardSharer,
                  definitions: sampleData.definitions,
                ),
              ),
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
