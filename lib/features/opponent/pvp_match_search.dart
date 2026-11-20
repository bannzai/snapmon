import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/battle/battle_engine.dart';
import '../../domain/master/master_data.dart';
import 'pvp_battle_client.dart';

/// 相手を探している間に Functions の joinPvpMatch を呼び直す間隔。
/// Functions は最後の呼び出しから 10 秒 (functions/src/pvp_battle_rules.ts の `MATCH_TICKET_FRESH_SECONDS`) の間だけ相手に選ぶため、
/// 1 回の呼び出しが遅れても途切れず、後から来た相手に組み合わされたことを 3 秒以内に知れる間隔にした。
const Duration pvpMatchJoinInterval = Duration(seconds: 3);

/// 人との対戦で、同じ版の利用者だけを組み合わせるために Functions に渡す対戦の計算の版。
/// バトルの計算の版 ([pvpRulesVersion]) と、技・属性・相性の表 [definitions] の版から作る
/// (2 人の端末が違う計算や違う表で進めると、同じ行動から違う結果になるため)。
String pvpMatchRulesVersion({required MasterData definitions}) =>
    '$pvpRulesVersion.${definitions.version}';

/// 人との対戦の相手を探す 1 回の操作。[start] から [stop] まで [pvpMatchJoinInterval] ごとに相手を探す。
/// 対戦タブの待つ画面と、初回のバトルの前の短い間の両方で使う (探す長さは呼ぶ側が [stop] で決める)。
class PvpMatchSearch {
  /// [client] で、対戦の計算の版 [rulesVersion] の相手を探す操作を作る。
  PvpMatchSearch({required this.client, required this.rulesVersion})
    : _searchID = client.createSearchID();

  /// 組み合わせを呼ぶ関数の組。
  final PvpBattleClient client;

  /// 対戦の計算の版 ([pvpMatchRulesVersion])。
  final String rulesVersion;

  /// この探す操作の ID。
  final String _searchID;

  /// [matchedBattleID] の実体。
  final Completer<String?> _matchedBattleID = Completer();

  /// 相手を探す呼び出しを繰り返すタイマー。[start] の前と [stop] の後は null。
  Timer? _joinTimer;

  /// 進行中の相手を探す呼び出し。呼び出しの間は重ねて呼ばず、[stop] はこれが終わるのを待つ。
  Future<void>? _joinInProgress;

  /// 最初の [stop] の呼び出し。2 回目からは同じ結果を返す。
  Future<String?>? _stopInProgress;

  /// 組み合わされた対戦の ID で完了する。組み合わされる前に [stop] した時は null で完了し、
  /// 相手を探す呼び出しが失敗した時 (通信の失敗・手持ちが空) は、失敗の前に組み合わされていたらその対戦の ID で、
  /// そうでなければそのエラーで完了する。
  Future<String?> get matchedBattleID => _matchedBattleID.future;

  /// 相手を探し始める。
  void start() {
    _join();
    _joinTimer = Timer.periodic(pvpMatchJoinInterval, (_) => _join());
  }

  /// 相手を 1 回探す。前の呼び出しが終わっていない時と、結果が決まった後は何もしない。
  void _join() {
    if (_joinInProgress != null || _matchedBattleID.isCompleted) {
      return;
    }
    _joinInProgress = () async {
      try {
        final battleID = await client.joinMatch(
          rulesVersion: rulesVersion,
          searchID: _searchID,
        );
        if (battleID != null && !_matchedBattleID.isCompleted) {
          _joinTimer?.cancel();
          _matchedBattleID.complete(battleID);
        }
      } catch (error, stackTrace) {
        if (!_matchedBattleID.isCompleted) {
          _joinTimer?.cancel();
          await _settleFailedJoin(joinError: error, joinStackTrace: stackTrace);
        }
      } finally {
        _joinInProgress = null;
      }
    }();
  }

  /// 相手を探す呼び出しが [joinError] ([joinStackTrace]) で失敗した時に、Functions に探すのをやめると伝えて [matchedBattleID] を決める。
  /// 前の呼び出しで置いた待ちの札が残っていると、探すのをやめた後に別の利用者と組み合わされ、相手が行動の期限まで待たされるため。
  /// 失敗の前に組み合わされていたらその対戦の ID で、そうでなければ [joinError] で完了する。
  /// やめると伝える呼び出しも失敗した時 (通信が切れている) は [joinError] で完了する
  /// (札は最後の呼び出しから 10 秒で相手に選ばれなくなる。functions/src/pvp_battle_rules.ts の `MATCH_TICKET_FRESH_SECONDS`)。
  Future<void> _settleFailedJoin({
    required Object joinError,
    required StackTrace joinStackTrace,
  }) async {
    try {
      final battleID = await client.leaveMatch(searchID: _searchID);
      if (battleID != null) {
        _matchedBattleID.complete(battleID);
        return;
      }
    } catch (leaveError) {
      debugPrint('leavePvpMatch: $leaveError');
    }
    _matchedBattleID.completeError(joinError, joinStackTrace);
  }

  /// 相手を探すのをやめ、[matchedBattleID] と同じ結果を返す。
  /// やめる時に Functions が既に組み合わせていたら、その対戦の ID を返す (相手は既に対戦に入っているため、呼ぶ側はその対戦を始める)。
  /// 何度呼んでも同じ結果を返す (冪等)。
  Future<String?> stop() => _stopInProgress ??= _stop();

  /// [stop] の本体。相手を探す呼び出しを止め、結果が決まっていなければ Functions に探すのをやめると伝えて結果を決める。
  Future<String?> _stop() async {
    _joinTimer?.cancel();
    await _joinInProgress;
    if (!_matchedBattleID.isCompleted) {
      try {
        _matchedBattleID.complete(await client.leaveMatch(searchID: _searchID));
      } catch (error, stackTrace) {
        _matchedBattleID.completeError(error, stackTrace);
      }
    }
    return matchedBattleID;
  }
}
