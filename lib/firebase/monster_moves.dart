import 'package:cloud_functions/cloud_functions.dart';

import 'session.dart';

/// Functions の selectMonsterMoves (functions/src/monster_moves.ts) を呼び、図鑑の [monsterID] のモンスターの
/// 対戦の前に選んだ技を [moveIDs] (枠の順) にする (`DexStore.connectServer` の `saveSelectedMoveIDs`)。
/// 断られた時は Functions のエラーをそのまま投げる。
Future<void> selectMonsterMovesWithFirebase({
  required String monsterID,
  required List<String> moveIDs,
}) => FirebaseFunctions.instanceFor(region: functionsRegion)
    .httpsCallable('selectMonsterMoves')
    .call<Object?>({'monsterID': monsterID, 'moveIDs': moveIDs});
