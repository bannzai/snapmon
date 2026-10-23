import 'package:flutter/material.dart';

import 'features/battle/battle_recorder.dart';
import 'features/capture/monster_generator.dart';
import 'features/dex/dex_store.dart';
import 'features/home/home_shell.dart';
import 'features/opponent/pvp_client.dart';
import 'features/session/session_screen.dart';
import 'features/session/session_store.dart';
import 'features/settings/account_store.dart';
import 'features/settings/settings_screen.dart';
import 'features/share/card_sharer.dart';
import 'sample/sample_data.dart';
import 'theme/snapmon_theme.dart';

/// アプリのルート。ログインが済むまではログインの画面 (読み込み中・失敗と再試行) だけを出し、済んだら下タブの画面を出す。
class SnapmonApp extends StatelessWidget {
  /// アプリのルートを作る。
  const SnapmonApp({
    super.key,
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

  /// 非同期 PvP の相手の取得・通報・ブロック・戦績・表示名。
  final PvpClient pvpClient;

  /// 見本データ。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// ログイン。
  final SessionStore sessionStore;

  /// 設定画面のリンクを開く。
  final OpenUrl openUrl;

  /// 設定画面に開発者メニューを出すか ([SettingsScreen.isDeveloperMenuEnabled])。
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
  Widget build(BuildContext context) => MaterialApp(
    title: 'snapmon',
    theme: snapmonThemeData(),
    home: ListenableBuilder(
      listenable: sessionStore,
      builder: (context, _) => sessionStore.canEnterApp
          ? HomeShell(
              sampleData: sampleData,
              dexStore: dexStore,
              sessionStore: sessionStore,
              openUrl: openUrl,
              isDeveloperMenuEnabled: isDeveloperMenuEnabled,
              battleRecorder: battleRecorder,
              monsterGenerator: monsterGenerator,
              pvpClient: pvpClient,
              cardSharer: cardSharer,
              accountStore: accountStore,
            )
          : SessionScreen(
              sessionStore: sessionStore,
              isDebugSkipEnabled: isDeveloperMenuEnabled,
            ),
    ),
  );
}
