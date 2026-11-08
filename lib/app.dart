import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'analytics/analytics_events.dart';
import 'audio/game_audio.dart';
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
import 'l10n/l10n.dart';
import 'sample/sample_data.dart';
import 'theme/snapmon_theme.dart';
import 'widgets/app_content_width.dart';

/// ブラウザがページの操作に数えないキー。Esc は HTML 仕様の activation triggering input event が除いていて
/// ( https://html.spec.whatwg.org/multipage/interaction.html#tracking-user-activation )、修飾キーだけの押下は
/// Chromium が数えない (`KeyboardEventManager` が `ui::KeycodeConverter::IsDomKeyForModifier` の true のキーを除く。
/// 一覧は ACCEL・ALT・ALT_GRAPH・CAPS_LOCK・CONTROL・FN・FN_LOCK・HYPER・META・NUM_LOCK・SCROLL_LOCK・SHIFT・SUPER・
/// SYMBOL・SYMBOL_LOCK・SHIFT_LEVEL5。 https://source.chromium.org/chromium/chromium/src/+/main:ui/events/keycodes/dom/keycode_converter.cc 。
/// ACCEL・SHIFT_LEVEL5 は Flutter の LogicalKeyboardKey に無い)。
/// これらで先に伝えると、ブラウザが再生を許す前に流そうとして待ち行列が止まる。
const keysNotCountedAsUserInteraction = {
  LogicalKeyboardKey.escape,
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.altLeft,
  LogicalKeyboardKey.altRight,
  LogicalKeyboardKey.altGraph,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
  LogicalKeyboardKey.capsLock,
  LogicalKeyboardKey.numLock,
  LogicalKeyboardKey.scrollLock,
  LogicalKeyboardKey.fn,
  LogicalKeyboardKey.fnLock,
  LogicalKeyboardKey.hyper,
  LogicalKeyboardKey.superKey,
  LogicalKeyboardKey.symbol,
  LogicalKeyboardKey.symbolLock,
};

/// アプリのルート。起動するとタイトル画面を出し、タイトルのボタンでログインを済ませてから下タブの画面に入る。
/// ログインを終えた (アカウントの削除・開発者メニューのやり直し) 時はタイトルに戻る。
class SnapmonApp extends StatefulWidget {
  /// アプリのルートを作る。
  const SnapmonApp({
    super.key,
    required this.sampleData,
    required this.dexStore,
    required this.sessionStore,
    required this.gameAudio,
    required this.openUrl,
    required this.isDeveloperMenuEnabled,
    required this.battleRecorder,
    required this.monsterGenerator,
    required this.pvpClient,
    required this.cardSharer,
    required this.accountStore,
    required this.logEvent,
  });

  /// BGM・効果音。[GameAudioScope] で全画面から引けるようにする。
  final GameAudio gameAudio;

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

  /// 下タブの画面に入った時に、撮る画面で押すのを待たずにカメラを開くか (タイトルの「カメラで撮ってはじめる」から来た時)。
  bool _startsCameraOnHomeOpen = false;

  @override
  void initState() {
    super.initState();
    widget.sessionStore.addListener(_onSessionChanged);
    HardwareKeyboard.instance.addHandler(_onHardwareKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onHardwareKeyEvent);
    widget.sessionStore.removeListener(_onSessionChanged);
    super.dispose();
  }

  /// キーボードだけで操作する時 (Web を Tab・Enter・Space で操作する時) も、最初のキーを BGM に伝える。
  /// ブラウザはキーの押下もページの操作に数える ([keysNotCountedAsUserInteraction] を除く)。
  /// フォーカスに依らず全てのキーを受けるため、Focus ではなくこちらで受ける。キーは消費しない (false) ので、画面の操作はそのまま届く。
  bool _onHardwareKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent &&
        !keysNotCountedAsUserInteraction.contains(event.logicalKey)) {
      unawaited(widget.gameAudio.notifyUserInteraction());
    }
    return false;
  }

  /// ポインターの操作を最初の操作として BGM に伝える。ブラウザが操作に数えるのは、マウスは押した時 (pointerdown)、
  /// タッチ・ペンは離した時 (pointerup) で、タッチの pointerdown は数えない (上の HTML 仕様)。
  /// タッチで押した時点で伝えると、ブラウザが再生を許す前に流そうとして待ち行列が止まるため、種類で分ける。
  void _notifyPointerInteraction({
    required PointerEvent event,
    required bool isDown,
  }) {
    if ((event.kind == PointerDeviceKind.mouse) == isDown) {
      unawaited(widget.gameAudio.notifyUserInteraction());
    }
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
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    // Navigator より外に置き、push したバトル画面・設定画面からも引けるようにする
    builder: (context, child) => GameAudioScope(
      gameAudio: widget.gameAudio,
      // Web はユーザーが一度ページを操作するまで音を出せないため、最初のタップ・クリックを BGM に伝える (キーは _onHardwareKeyEvent)
      child: Listener(
        onPointerDown: (event) =>
            _notifyPointerInteraction(event: event, isDown: true),
        onPointerUp: (event) =>
            _notifyPointerInteraction(event: event, isDown: false),
        child: constrainToAppContentWidth(
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
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
            onEnterHome: ({required tab, required startsCamera}) =>
                setState(() {
                  _homeTab = tab;
                  _startsCameraOnHomeOpen = startsCamera;
                }),
            battleRecorder: widget.battleRecorder,
          );
        }
        return HomeShell(
          initialTab: homeTab,
          startsCameraOnCaptureOpen: _startsCameraOnHomeOpen,
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
