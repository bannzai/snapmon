import 'dart:async';

import 'package:flutter/material.dart';

import '../../audio/game_audio.dart';
import '../../common_ui/scene_route.dart';
import '../../sample/sample_data.dart';
import '../battle/battle_recorder.dart';
import '../capture/capture_screen.dart';
import '../capture/monster_generator.dart';
import '../dex/dex_screen.dart';
import '../dex/dex_store.dart';
import '../opponent/opponent_screen.dart';
import '../opponent/pvp_client.dart';
import '../session/session_store.dart';
import '../settings/account_store.dart';
import '../settings/settings_screen.dart';
import '../share/card_sharer.dart';

/// ホームの画面で切り替えるシーン。撮るを起点にし、図鑑・対戦は撮るのボタンから開いて「もどる」で撮るに戻る (#264)。
enum HomeScene {
  /// 図鑑。
  dex,

  /// 撮る。ホームの画面の起点のシーン。
  capture,

  /// 対戦。
  opponent,
}

/// タイトル画面からログインを済ませて入る、図鑑・撮る・対戦のシーンを 1 つずつ出す画面。
/// 下タブは置かず、シーンの間は画面の中のボタンで移り、フェードで切り替える (#264)。
class HomeShell extends StatefulWidget {
  /// ホームの画面を作る。
  const HomeShell({
    super.key,
    required this.initialScene,
    required this.startsCameraOnCaptureOpen,
    required this.sampleData,
    required this.dexStore,
    required this.sessionStore,
    required this.openUrl,
    required this.isDeveloperMenuEnabled,
    required this.battleRecorder,
    required this.monsterGenerator,
    required this.pvpClient,
    required this.cardSharer,
    required this.accountStore,
  });

  /// 最初に見せるシーン (タイトル画面のどのボタンから入ったかで決まる)。
  final HomeScene initialScene;

  /// 最初に撮る画面を開いた時に、押すのを待たずにカメラを開くか (タイトルの「カメラで撮ってはじめる」から来た時)。
  final bool startsCameraOnCaptureOpen;

  /// 非同期 PvP の相手の取得・通報・ブロック・戦績・表示名。
  final PvpClient pvpClient;

  /// 見本データ。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// ログイン (開発者メニューのログイン状態と始め直し、対戦の画面の作り直しに使う)。
  final SessionStore sessionStore;

  /// 設定画面のリンクを開く。
  final OpenUrl openUrl;

  /// 設定画面に開発者メニューを出すか (DEBUG ビルドだけ true。[SettingsScreen.isDeveloperMenuEnabled])。
  final bool isDeveloperMenuEnabled;

  /// バトルの記録と計測。
  final BattleRecorder battleRecorder;

  /// 撮る・選ぶ・生成の呼び出しと計測。
  final MonsterGenerator monsterGenerator;

  /// 図鑑のカードとバトルの結果の共有に使う関数の組。
  final CardSharer cardSharer;

  /// 設定画面のアカウントの連携と削除。
  final AccountStore accountStore;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  late HomeScene _selectedScene = widget.initialScene;

  /// 一度カメラを開けた (権限を許可された) か。撮る画面はシーンを切り替えるたびに作り直されるため、ここで覚え、
  /// 次からは撮るのシーンを開いた時に映像を出す。覚えるのはこの画面がある間 (アプリを起動し直すと、もう一度押してもらう) で、
  /// 端末に保存しない (#64 の DIRECTION.md の行)
  bool _hasOpenedCamera = false;

  /// タイトルの「カメラで撮ってはじめる」で求めたカメラを、最初に開いた撮る画面でまだ使っていないか。
  /// シーンを切り替えたら下ろす (拒否された後に撮る画面へ戻るたびに権限を聞き直さないため)
  late bool _isTitleCameraRequestPending = widget.startsCameraOnCaptureOpen;

  @override
  void initState() {
    super.initState();
    // タイトルから続けて同じ曲を流す (同じ曲なら流し直さない)。バトル画面から戻った時はバトル画面が流し直す
    unawaited(
      GameAudioScope.read(
        context,
      ).playBackgroundMusic(music: BackgroundMusic.home),
    );
  }

  void _selectScene({required HomeScene scene}) => setState(() {
    _selectedScene = scene;
    _isTitleCameraRequestPending = false;
  });

  /// 設定画面を開き、閉じるまで待つ (対戦の画面が閉じた後にプロフィールを読み直すため)。
  Future<void> _openSettings() => Navigator.of(context).push(
    sceneRoute<void>(
      builder: (context) => SettingsScreen(
        sampleData: widget.sampleData,
        dexStore: widget.dexStore,
        sessionStore: widget.sessionStore,
        monsterGenerator: widget.monsterGenerator,
        pvpClient: widget.pvpClient,
        cardSharer: widget.cardSharer,
        openUrl: widget.openUrl,
        isDeveloperMenuEnabled: widget.isDeveloperMenuEnabled,
        accountStore: widget.accountStore,
        battleRecorder: widget.battleRecorder,
      ),
    ),
  );

  Widget _buildScene({required HomeScene scene}) => switch (scene) {
    HomeScene.dex => DexScreen(
      dexStore: widget.dexStore,
      onSelectScene: _selectScene,
      onOpenSettings: _openSettings,
      cardSharer: widget.cardSharer,
    ),
    HomeScene.capture => CaptureScreen(
      startsCameraOnOpen: _hasOpenedCamera || _isTitleCameraRequestPending,
      onCameraOpened: () => _hasOpenedCamera = true,
      dexStore: widget.dexStore,
      monsterGenerator: widget.monsterGenerator,
      onSelectScene: _selectScene,
      onOpenSettings: _openSettings,
      cardSharer: widget.cardSharer,
      sampleData: widget.sampleData,
      pvpClient: widget.pvpClient,
      battleRecorder: widget.battleRecorder,
    ),
    // 設定の「データを引き継ぐ」で別のアカウントに切り替わると uid が変わるため、uid ごとに作り直して
    // 前のアカウントの戦績を持ち越さない
    HomeScene.opponent => ListenableBuilder(
      listenable: widget.sessionStore,
      builder: (context, _) => OpponentScreen(
        key: ValueKey(widget.sessionStore.uid),
        sampleData: widget.sampleData,
        dexStore: widget.dexStore,
        onSelectScene: _selectScene,
        onOpenSettings: _openSettings,
        battleRecorder: widget.battleRecorder,
        pvpClient: widget.pvpClient,
        cardSharer: widget.cardSharer,
      ),
    ),
  };

  @override
  Widget build(BuildContext context) => PopScope(
    // 図鑑・対戦では端末の戻る操作 (Android の戻るボタン・戻るジェスチャー) で撮るに戻り、撮るでは今までどおりアプリを閉じる
    canPop: _selectedScene == HomeScene.capture,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        _selectScene(scene: HomeScene.capture);
      }
    },
    child: Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: sceneTransitionDuration,
          // 前のシーンは切り替えた時点で外し、新しいシーンのフェードインだけにする。前のシーンを重ねて残すと、
          // 撮る → 図鑑 → 撮る を素早く押した時に撮る画面が 2 つ同時にあり、カメラを 2 回開くため
          layoutBuilder: (currentChild, previousChildren) =>
              currentChild ?? const SizedBox.shrink(),
          child: KeyedSubtree(
            key: ValueKey(_selectedScene),
            child: _buildScene(scene: _selectedScene),
          ),
        ),
      ),
    ),
  );
}
