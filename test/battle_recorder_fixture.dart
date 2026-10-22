import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/domain/battle/battle_state.dart';
import 'package:snapmon/features/battle/battle_recorder.dart';

/// テスト用の [BattleRecorder] が受け取った呼び出し。
class RecordedBattleCalls {
  /// startBattleRecord に渡された手持ちの ID (呼ばれた順)。
  final List<List<String>> startedPartyMonsterIds = [];

  /// completeBattleRecord に渡された引数 (呼ばれた順)。
  final List<
    ({
      String battleId,
      List<String> participantMonsterIds,
      BattleSideId winner,
      int turnCount,
    })
  >
  completedBattles = [];

  /// logEvent に渡されたイベントとパラメータ (呼ばれた順)。
  final List<({AnalyticsEvent event, Map<String, Object>? parameters})>
  loggedEvents = [];
}

/// Firebase を呼ばずに [calls] へ呼び出しを残す [BattleRecorder] を返す。
/// startBattleRecord は [startBattleRecord] の結果を返し、completeBattleRecord は [recordedLevels] を
/// 上がった後のレベルとして返す。
BattleRecorder fakeBattleRecorder({
  required RecordedBattleCalls calls,
  required Future<String?> Function() startBattleRecord,
  required Map<String, int> recordedLevels,
}) => BattleRecorder(
  startBattleRecord: ({required partyMonsterIds}) {
    calls.startedPartyMonsterIds.add(partyMonsterIds);
    return startBattleRecord();
  },
  completeBattleRecord:
      ({
        required battleId,
        required participantMonsterIds,
        required winner,
        required turnCount,
      }) async {
        calls.completedBattles.add((
          battleId: battleId,
          participantMonsterIds: participantMonsterIds,
          winner: winner,
          turnCount: turnCount,
        ));
        return recordedLevels;
      },
  logEvent: ({required event, required parameters}) async =>
      calls.loggedEvents.add((event: event, parameters: parameters)),
);
