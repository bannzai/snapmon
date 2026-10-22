import '../../analytics/analytics_events.dart';
import '../../domain/battle/battle_state.dart';

/// バトルの記録 (Functions の startBattle・recordBattle) と計測を呼ぶ関数の組。
/// バトル画面を Firebase と切り離してテストするため、実体 (lib/firebase/battle_record.dart と [logAnalyticsEvent]) は main.dart から渡す。
class BattleRecorder {
  /// 関数の組を作る。
  const BattleRecorder({
    required this.startBattleRecord,
    required this.completeBattleRecord,
    required this.logEvent,
  });

  /// バトルの開始を記録し、結果の送信に使う battleId を返す。[partyMonsterIds] は連れて行く手持ち。
  /// 記録しない時 (年齢の確認を通ったログインが無い・図鑑がサーバーに無い) は null を返す。
  final Future<String?> Function({required List<String> partyMonsterIds})
  startBattleRecord;

  /// [battleId] のバトルの結果を記録する。[participantMonsterIds] は場に出たことがある自分のモンスター。
  /// レベルの加算は Functions が行い、上がった後のレベルを monsterId ごとに返す。
  final Future<Map<String, int>> Function({
    required String battleId,
    required List<String> participantMonsterIds,
    required BattleSideId winner,
    required int turnCount,
  })
  completeBattleRecord;

  /// Analytics にイベントを送る ([logAnalyticsEvent] と同じ形)。
  final Future<void> Function({
    required AnalyticsEvent event,
    required Map<String, Object>? parameters,
  })
  logEvent;
}
