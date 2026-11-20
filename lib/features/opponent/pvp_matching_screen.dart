import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_text_styles.dart';
import 'pvp_battle_client.dart';
import 'pvp_match_search.dart';

/// 相手を探し始めてから「CPU と対戦をする」を出すまでの時間。issue #386 が決めた値 (1 分組み合わされなければ CPU と対戦できるようにする)。
const Duration pvpMatchingCpuOfferDelay = Duration(minutes: 1);

/// 相手を探し続ける時間の上限。「CPU と対戦をする」を出した後も探し続け ([pvpMatchingCpuOfferDelay] の後に来た相手とも対戦できるように)、
/// 画面を開いたまま離れた端末が Functions を呼び続けないよう、出してから 4 分で探すのをやめる。
const Duration pvpMatchingSearchLimit = Duration(minutes: 5);

/// 人との対戦の待つ画面を閉じた時の結果。「やめる」で閉じた時は結果を返さない (null)。
typedef PvpMatchingResult = ({
  /// 組み合わされた対戦の ID。組み合わされないまま「CPU と対戦をする」を選んだ時は null。
  String? battleID,
});

/// 人との対戦の待つ画面。開いている間、同じ時に相手を探している他の利用者を探す ([PvpMatchSearch])。
/// 組み合わされたら対戦の ID を返して閉じる。「やめる」でいつでも探すのをやめられ、[pvpMatchingCpuOfferDelay] 組み合わされなければ
/// 「CPU と対戦をする」を出す (出した後も [pvpMatchingSearchLimit] まで探し続ける)。探せなかった時はエラーをそのまま出し、
/// 「CPU と対戦をする」をすぐに出す。相手の絵・名前は出さない (出すのは通報・ブロックのできるバトルの画面だけにする)。
class PvpMatchingScreen extends StatefulWidget {
  /// [battleClient] で、対戦の計算の版 [rulesVersion] ([pvpMatchRulesVersion]) の相手を探す待つ画面を作る。
  const PvpMatchingScreen({
    super.key,
    required this.battleClient,
    required this.rulesVersion,
  });

  /// 組み合わせを呼ぶ関数の組。
  final PvpBattleClient battleClient;

  /// 対戦の計算の版。
  final String rulesVersion;

  @override
  State<PvpMatchingScreen> createState() => _PvpMatchingScreenState();
}

/// [PvpMatchingScreen] の状態。探す操作と、「CPU と対戦をする」を出すまで・探すのをやめるまでのタイマーを持つ。
class _PvpMatchingScreenState extends State<PvpMatchingScreen> {
  /// この画面の探す操作。
  late final PvpMatchSearch _search = PvpMatchSearch(
    client: widget.battleClient,
    rulesVersion: widget.rulesVersion,
  );

  /// [pvpMatchingCpuOfferDelay] の後に「CPU と対戦をする」を出すタイマー。
  late final Timer _cpuOfferTimer;

  /// [pvpMatchingSearchLimit] の後に探すのをやめるタイマー。
  late final Timer _searchLimitTimer;

  /// 「CPU と対戦をする」を出しているか。
  bool _offersCpuBattle = false;

  /// 探すのをやめたか ([pvpMatchingSearchLimit] を過ぎた・探せなかった)。やめた後は探している表示を出さない。
  bool _hasStoppedSearching = false;

  /// 探せなかった時のエラー。
  Object? _searchError;

  /// 「やめる」「CPU と対戦をする」を押して、探すのをやめる呼び出しを待っているか。待つ間はボタンを押せない。
  bool _isLeaving = false;

  @override
  void initState() {
    super.initState();
    _search.start();
    unawaited(_closeWhenMatched());
    _cpuOfferTimer = Timer(
      pvpMatchingCpuOfferDelay,
      () => setState(() => _offersCpuBattle = true),
    );
    // 結果は _closeWhenMatched が受け取るため、ここでは捨てる
    _searchLimitTimer = Timer(
      pvpMatchingSearchLimit,
      () => _search.stop().ignore(),
    );
  }

  @override
  void dispose() {
    _cpuOfferTimer.cancel();
    _searchLimitTimer.cancel();
    // 結果は _closeWhenMatched が受け取る。画面が閉じた後の失敗は出す先が無いため捨てる
    _search.stop().ignore();
    super.dispose();
  }

  /// 探す操作の結果を待ち、組み合わされたら対戦の ID を返して画面を閉じる。
  /// 組み合わされないまま探すのをやめた時 ([pvpMatchingSearchLimit]) と探せなかった時は、画面に残って「CPU と対戦をする」を出す。
  Future<void> _closeWhenMatched() async {
    Object? searchError;
    String? battleID;
    try {
      battleID = await _search.matchedBattleID;
    } catch (error) {
      searchError = error;
    }
    if (!mounted || _isLeaving) {
      return;
    }
    if (battleID != null) {
      Navigator.of(context).pop<PvpMatchingResult>((battleID: battleID));
      return;
    }
    setState(() {
      _hasStoppedSearching = true;
      _offersCpuBattle = true;
      _searchError = searchError;
    });
  }

  /// 探すのをやめて画面を閉じる。[startsCpuBattle] が true なら CPU との対戦を始める結果を、false なら結果なし (やめた) を返す。
  /// やめる前に組み合わされていた時は、どちらでもその対戦の ID を返す (相手は既に対戦に入っているため)。
  Future<void> _leave({required bool startsCpuBattle}) async {
    if (_isLeaving) {
      return;
    }
    setState(() => _isLeaving = true);
    String? battleID;
    try {
      battleID = await _search.stop();
    } catch (error) {
      debugPrint('leavePvpMatch: $error');
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop<PvpMatchingResult>(
      battleID != null || startsCpuBattle ? (battleID: battleID) : null,
    );
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // 戻る操作でも「やめる」と同じく、探すのをやめてから閉じる
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) {
        unawaited(_leave(startsCpuBattle: false));
      }
    },
    child: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_hasStoppedSearching) ...[
                  const Center(
                    child: CircularProgressIndicator(
                      color: SnapmonColors.accent,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                Text(
                  switch (_searchError) {
                    final searchError? => searchError.toString(),
                    null =>
                      _hasStoppedSearching
                          ? context.l10n.pvpMatchingNotFound
                          : context.l10n.opponentSearching,
                  },
                  key: const Key('pvp-matching-status'),
                  textAlign: TextAlign.center,
                  style: SnapmonTextStyles.body,
                ),
                const SizedBox(height: 32),
                if (_offersCpuBattle) ...[
                  FilledButton.icon(
                    key: const Key('pvp-matching-cpu-battle'),
                    onPressed: _isLeaving
                        ? null
                        : () => _leave(startsCpuBattle: true),
                    icon: const Icon(Icons.smart_toy_outlined),
                    label: Text(context.l10n.opponentCpuBattle),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton(
                  key: const Key('pvp-matching-cancel'),
                  onPressed: _isLeaving
                      ? null
                      : () => _leave(startsCpuBattle: false),
                  child: Text(context.l10n.commonCancel),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
