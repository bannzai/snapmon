import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../sample/sample_data.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
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

/// 下タブの項目。並びは DIRECTION.md「デザインの方向」の「下タブは図鑑・撮る・対戦」。
enum HomeTab {
  /// 図鑑。
  dex,

  /// 撮る。
  capture,

  /// 対戦。
  opponent,
}

/// 下タブ (図鑑・撮る・対戦) を持つ、タイトル画面からログインを済ませて入る画面。
class HomeShell extends StatefulWidget {
  /// 下タブの画面を作る。
  const HomeShell({
    super.key,
    required this.initialTab,
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

  /// 最初に見せるタブ (タイトル画面のどのボタンから入ったかで決まる)。
  final HomeTab initialTab;

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
  late HomeTab _selectedTab = widget.initialTab;

  /// 一度カメラを開けた (権限を許可された) か。撮る画面はタブを切り替えるたびに作り直されるため、ここで覚え、
  /// 次からはタブを開いた時に映像を出す。覚えるのはこの画面がある間 (アプリを起動し直すと、もう一度押してもらう) で、
  /// 端末に保存しない (#64 の DIRECTION.md の行)
  bool _hasOpenedCamera = false;

  /// タイトルの「カメラで撮ってはじめる」で求めたカメラを、最初に開いた撮る画面でまだ使っていないか。
  /// タブを切り替えたら下ろす (拒否された後に撮る画面へ戻るたびに権限を聞き直さないため)
  late bool _isTitleCameraRequestPending = widget.startsCameraOnCaptureOpen;

  void _selectTab({required HomeTab tab}) => setState(() {
    _selectedTab = tab;
    _isTitleCameraRequestPending = false;
  });

  void _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
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

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: switch (_selectedTab) {
        HomeTab.dex => DexScreen(
          dexStore: widget.dexStore,
          onSelectTab: _selectTab,
          onOpenSettings: _openSettings,
          cardSharer: widget.cardSharer,
        ),
        HomeTab.capture => CaptureScreen(
          startsCameraOnOpen: _hasOpenedCamera || _isTitleCameraRequestPending,
          onCameraOpened: () => _hasOpenedCamera = true,
          dexStore: widget.dexStore,
          monsterGenerator: widget.monsterGenerator,
          onSelectTab: _selectTab,
          onOpenSettings: _openSettings,
          cardSharer: widget.cardSharer,
          sampleData: widget.sampleData,
          pvpClient: widget.pvpClient,
          battleRecorder: widget.battleRecorder,
        ),
        // 設定の「データを引き継ぐ」で別のアカウントに切り替わると uid が変わるため、uid ごとに作り直して
        // 前のアカウントの戦績を持ち越さない
        HomeTab.opponent => ListenableBuilder(
          listenable: widget.sessionStore,
          builder: (context, _) => OpponentScreen(
            key: ValueKey(widget.sessionStore.uid),
            sampleData: widget.sampleData,
            dexStore: widget.dexStore,
            onSelectTab: _selectTab,
            onOpenSettings: _openSettings,
            battleRecorder: widget.battleRecorder,
            pvpClient: widget.pvpClient,
            cardSharer: widget.cardSharer,
          ),
        ),
      },
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        child: Row(
          children: [
            for (final tab in HomeTab.values)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _TabButton(
                    tab: tab,
                    isSelected: tab == _selectedTab,
                    onTap: () => _selectTab(tab: tab),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.tab,
    required this.isSelected,
    required this.onTap,
  });

  final HomeTab tab;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? SnapmonColors.accent : SnapmonColors.textMuted;
    return Material(
      color: isSelected ? SnapmonColors.surface : SnapmonColors.background,
      borderRadius: SnapmonRadii.button,
      child: InkWell(
        key: Key('tab-${tab.name}'),
        borderRadius: SnapmonRadii.button,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                switch (tab) {
                  HomeTab.dex => Icons.grid_view_rounded,
                  HomeTab.capture => Icons.photo_camera_outlined,
                  HomeTab.opponent => Icons.sports_martial_arts,
                },
                color: color,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(switch (tab) {
                HomeTab.dex => context.l10n.tabDex,
                HomeTab.capture => context.l10n.tabCapture,
                HomeTab.opponent => context.l10n.tabOpponent,
              }, style: SnapmonTextStyles.small.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
