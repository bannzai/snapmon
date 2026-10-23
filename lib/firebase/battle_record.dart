import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/battle/battle_state.dart';
import 'session.dart';

/// Functions の startBattle を呼び、battleId を返す。[partyMonsterIds] は連れて行く手持ち。
/// ログインが無い時 (DEBUG ビルドでログインを飛ばした時) は呼ばずに null を返す (Functions がログインの無い呼び出しを拒否するため)。
Future<String?> startBattleRecordWithFirebase({
  required List<String> partyMonsterIds,
}) async {
  if (FirebaseAuth.instance.currentUser == null) {
    return null;
  }
  final result = await FirebaseFunctions.instanceFor(region: functionsRegion)
      .httpsCallable('startBattle')
      .call<Object?>({'partyMonsterIds': partyMonsterIds});
  return (result.data! as Map<Object?, Object?>)['battleId']! as String;
}

/// Functions の recordBattle を呼び、上がった後のレベルを monsterId ごとに返す。
/// 引数は functions/src/battle.ts の recordBattle の data と同じ。
Future<Map<String, int>> completeBattleRecordWithFirebase({
  required String battleId,
  required List<String> participantMonsterIds,
  required BattleSideId winner,
  required int turnCount,
}) async {
  final result = await FirebaseFunctions.instanceFor(region: functionsRegion)
      .httpsCallable('recordBattle')
      .call<Object?>({
        'battleId': battleId,
        'participantMonsterIds': participantMonsterIds,
        'winner': winner.name,
        'turnCount': turnCount,
      });
  return {
    for (final entry
        in ((result.data! as Map<Object?, Object?>)['levels']!
                as Map<Object?, Object?>)
            .entries)
      entry.key! as String: entry.value! as int,
  };
}
