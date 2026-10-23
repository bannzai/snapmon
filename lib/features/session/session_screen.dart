import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_text_styles.dart';
import 'session_store.dart';

/// Firebase へのログインが済むまで出す画面。開くとログインを始め、
/// 失敗したらエラーの文言と「もう一度試す」を出してこの画面で止める (ログインせずにアプリに入れない)。
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
  @override
  void initState() {
    super.initState();
    // build の途中で状態を変えて親の ListenableBuilder を作り直させないため、最初のフレームの後に始める
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.sessionStore.start(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: ListenableBuilder(
        listenable: widget.sessionStore,
        builder: (context, _) {
          final error = widget.sessionStore.error;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 56, 20, 40),
            children: [
              const Text('snapmon', style: SnapmonTextStyles.logo),
              const SizedBox(height: 32),
              if (error == null) ...[
                const Text('じゅんびしています', style: SnapmonTextStyles.hero),
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ] else ...[
                const Text('つながりませんでした', style: SnapmonTextStyles.hero),
                const SizedBox(height: 16),
                Text(
                  error.toString(),
                  style: SnapmonTextStyles.body.copyWith(
                    color: SnapmonColors.hitPointsLoss,
                  ),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: widget.sessionStore.start,
                  child: const Text('もう一度試す'),
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
