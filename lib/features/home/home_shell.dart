import 'package:flutter/material.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../age_gate/age_confirmation.dart';
import '../capture/capture_screen.dart';
import '../dex/dex_screen.dart';
import '../dex/dex_store.dart';
import '../opponent/opponent_screen.dart';
import '../settings/settings_screen.dart';

/// 下タブの項目。並びは DIRECTION.md「デザインの方向」の「下タブは図鑑・撮る・対戦」。
enum HomeTab {
  /// 図鑑。
  dex,

  /// 撮る。
  capture,

  /// 対戦。
  opponent,
}

/// 下タブ (図鑑・撮る・対戦) を持つ、年齢の確認の後の画面。
class HomeShell extends StatefulWidget {
  /// 下タブの画面を作る。
  const HomeShell({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.ageConfirmationStore,
    required this.openUrl,
    required this.isDeveloperMenuEnabled,
  });

  /// 見本データ。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 年齢の確認 (開発者メニューのやり直しに使う)。
  final AgeConfirmationStore ageConfirmationStore;

  /// 設定画面のリンクを開く。
  final OpenUrl openUrl;

  /// 設定画面に開発者メニューを出すか (DEBUG ビルドだけ true。[SettingsScreen.isDeveloperMenuEnabled])。
  final bool isDeveloperMenuEnabled;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  // 起動して最初に見せるのは撮る画面 (モックの起点の画面。documents/design/mock-2026-10-21/Main.dc.html)
  HomeTab _selectedTab = HomeTab.capture;

  void _selectTab({required HomeTab tab}) => setState(() => _selectedTab = tab);

  void _openSettings() => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => SettingsScreen(
        sampleData: widget.sampleData,
        dexStore: widget.dexStore,
        ageConfirmationStore: widget.ageConfirmationStore,
        openUrl: widget.openUrl,
        isDeveloperMenuEnabled: widget.isDeveloperMenuEnabled,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      bottom: false,
      child: switch (_selectedTab) {
        HomeTab.dex => DexScreen(
          sampleData: widget.sampleData,
          dexStore: widget.dexStore,
          onSelectTab: _selectTab,
          onOpenSettings: _openSettings,
        ),
        HomeTab.capture => CaptureScreen(
          sampleData: widget.sampleData,
          dexStore: widget.dexStore,
          onSelectTab: _selectTab,
          onOpenSettings: _openSettings,
        ),
        HomeTab.opponent => OpponentScreen(
          sampleData: widget.sampleData,
          dexStore: widget.dexStore,
          onSelectTab: _selectTab,
          onOpenSettings: _openSettings,
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
                HomeTab.dex => '図鑑',
                HomeTab.capture => '撮る',
                HomeTab.opponent => '対戦',
              }, style: SnapmonTextStyles.small.copyWith(color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
