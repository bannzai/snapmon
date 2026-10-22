import 'package:flutter/material.dart';

import 'features/age_gate/age_confirmation.dart';
import 'features/age_gate/age_gate_screen.dart';
import 'features/battle/battle_recorder.dart';
import 'features/dex/dex_store.dart';
import 'features/home/home_shell.dart';
import 'features/settings/settings_screen.dart';
import 'sample/sample_data.dart';
import 'theme/snapmon_theme.dart';

/// アプリのルート。年齢の確認が済むまでは年齢の確認の画面だけを出し、済んだら下タブの画面を出す。
class SnapmonApp extends StatelessWidget {
  /// アプリのルートを作る。
  const SnapmonApp({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.ageConfirmationStore,
    required this.openUrl,
    required this.isDeveloperMenuEnabled,
    required this.battleRecorder,
  });

  /// 見本データ。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 年齢の確認。
  final AgeConfirmationStore ageConfirmationStore;

  /// 設定画面のリンクを開く。
  final OpenUrl openUrl;

  /// 設定画面に開発者メニューを出すか ([SettingsScreen.isDeveloperMenuEnabled])。
  final bool isDeveloperMenuEnabled;

  /// バトルの記録と計測。
  final BattleRecorder battleRecorder;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'snapmon',
    theme: snapmonThemeData(),
    home: ListenableBuilder(
      listenable: ageConfirmationStore,
      builder: (context, _) => switch (ageConfirmationStore.status) {
        AgeConfirmationStatus.unanswered => AgeGateScreen(
          ageConfirmationStore: ageConfirmationStore,
        ),
        AgeConfirmationStatus.restricted => const AgeRestrictedScreen(),
        AgeConfirmationStatus.allowed => HomeShell(
          sampleData: sampleData,
          dexStore: dexStore,
          ageConfirmationStore: ageConfirmationStore,
          openUrl: openUrl,
          isDeveloperMenuEnabled: isDeveloperMenuEnabled,
          battleRecorder: battleRecorder,
        ),
      },
    ),
  );
}
