import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/battle/battle_state.dart';
import 'age_verified_session.dart';

/// Functions の startBattle を呼び、battleId を返す。[partyMonsterIds] は連れて行く手持ち。
/// 年齢の確認を通ったログイン (ID トークンに ageVerified のクレーム) が無い時は呼ばずに null を返す
/// (Functions がクレームの無い呼び出しを拒否するため。アプリは年齢の確認の後のログインが済むまで下タブの画面に入れない)。
Future<String?> startBattleRecordWithFirebase({
  required List<String> partyMonsterIds,
}) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null ||
      !await hasAgeVerifiedClaim(user: user, forceRefresh: false)) {
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
