import 'package:flutter/material.dart';

import 'analytics/analytics_events.dart';
import 'features/battle/battle_recorder.dart';
import 'features/capture/monster_generator.dart';
import 'features/dex/dex_store.dart';
import 'features/home/home_shell.dart';
import 'features/opponent/pvp_client.dart';
import 'features/session/session_store.dart';
import 'features/settings/account_store.dart';
import 'features/settings/settings_screen.dart';
import 'features/share/card_sharer.dart';
import 'features/title/title_screen.dart';
import 'sample/sample_data.dart';
import 'theme/snapmon_theme.dart';

/// アプリのルート。起動するとタイトル画面を出し、タイトルのボタンでログインを済ませてから下タブの画面に入る。
/// ログインを終えた (アカウントの削除・開発者メニューのやり直し) 時はタイトルに戻る。
class SnapmonApp extends StatefulWidget {
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
    required this.logEvent,
  });

  /// 非同期 PvP の相手の取得・通報・ブロック・戦績・表示名。
  final PvpClient pvpClient;

  /// 見本データ。
  final SampleData sampleData;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// ログイン。
  final SessionStore sessionStore;

  /// 設定画面・タイトル画面のリンクを開く。
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

  /// タイトル画面の計測 ([logAnalyticsEvent] と同じ形)。
  final Future<void> Function({
    required AnalyticsEvent event,
    required Map<String, Object>? parameters,
  })
  logEvent;

  @override
  State<SnapmonApp> createState() => _SnapmonAppState();
}

class _SnapmonAppState extends State<SnapmonApp> {
  /// 下タブの画面に入った時の最初のタブ。タイトルを出している間は null。
  HomeTab? _homeTab;

  @override
  void initState() {
    super.initState();
    widget.sessionStore.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.sessionStore.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// ログインを終えたら、次にログインした時に下タブへ飛ばずタイトルから始めるようにする。
  void _onSessionChanged() {
    if (!widget.sessionStore.canEnterApp && _homeTab != null) {
      setState(() => _homeTab = null);
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'snapmon',
    theme: snapmonThemeData(),
    home: ListenableBuilder(
      listenable: widget.sessionStore,
      builder: (context, _) {
        final homeTab = _homeTab;
        if (homeTab == null || !widget.sessionStore.canEnterApp) {
          return TitleScreen(
            sampleData: widget.sampleData,
            dexStore: widget.dexStore,
            sessionStore: widget.sessionStore,
            monsterGenerator: widget.monsterGenerator,
            pvpClient: widget.pvpClient,
            cardSharer: widget.cardSharer,
            openUrl: widget.openUrl,
            isDeveloperMenuEnabled: widget.isDeveloperMenuEnabled,
            accountStore: widget.accountStore,
            logEvent: widget.logEvent,
            onEnterHome: ({required tab}) => setState(() => _homeTab = tab),
          );
        }
        return HomeShell(
          initialTab: homeTab,
          sampleData: widget.sampleData,
          dexStore: widget.dexStore,
          sessionStore: widget.sessionStore,
          openUrl: widget.openUrl,
          isDeveloperMenuEnabled: widget.isDeveloperMenuEnabled,
          battleRecorder: widget.battleRecorder,
          monsterGenerator: widget.monsterGenerator,
          pvpClient: widget.pvpClient,
          cardSharer: widget.cardSharer,
          accountStore: widget.accountStore,
        );
      },
    ),
  );
}
