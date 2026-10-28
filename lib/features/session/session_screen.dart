import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_text_styles.dart';
import 'session_store.dart';

/// Firebase へのログインが済むまで出す画面。タイトル画面のボタンを押した時にログインが済んでいなければ開く。
/// 開くとログインを始め、失敗したらエラーの文言と「もう一度試す」を出してこの画面で止める (ログインせずにアプリに入れない)。
class SessionScreen extends StatefulWidget {
  /// ログインを待つ画面を作る。
  const SessionScreen({
    super.key,
    required this.sessionStore,
    required this.isDebugSkipEnabled,
  });

  /// ログインの状態。
  final SessionStore sessionStore;

  /// 失敗の画面に「ログインせずに進む (DEBUG)」を出すか。release ビルドでは [kDebugMode] が const の false のため、
  /// この値に関係なくボタンがビルドから除かれる (設定画面の開発者メニューの入口と同じ)。
  final bool isDebugSkipEnabled;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  /// この画面が自分でログインを始めたか。始める前は、タイトルの裏のログインが残した前回のエラーを出さずに
  /// 「じゅんびしています」を出す (最初の 1 フレームだけ前回のエラーが見えるちらつきを防ぐ)。
  bool _hasStartedHere = false;

  @override
  void initState() {
    super.initState();
    // build の途中で状態を変えて親の ListenableBuilder を作り直させないため、最初のフレームの後に始める
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() {
    if (!_hasStartedHere) {
      setState(() => _hasStartedHere = true);
    }
    return widget.sessionStore.start();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.sessionStore,
        builder: (context, _) {
          final error = _hasStartedHere ? widget.sessionStore.error : null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 40),
            children: [
              const Text('snapmon', style: SnapmonTextStyles.logo),
              const SizedBox(height: 32),
              if (error == null) ...[
                Text(
                  context.l10n.sessionPreparing,
                  style: SnapmonTextStyles.hero,
                ),
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ] else ...[
                Text(
                  context.l10n.sessionConnectionFailed,
                  style: SnapmonTextStyles.hero,
                ),
                const SizedBox(height: 16),
                Text(
                  error.toString(),
                  style: SnapmonTextStyles.body.copyWith(
                    color: SnapmonColors.hitPointsLoss,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: _start,
                  child: Text(context.l10n.commonRetry),
                ),
                if (kDebugMode && widget.isDebugSkipEnabled) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: widget.sessionStore.skipForDebug,
                    child: const Text('ログインせずに進む (DEBUG)'),
                  ),
                ],
              ],
            ],
          );
        },
      ),
    ),
  );
}
