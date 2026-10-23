import '../../domain/master/master_data.dart';
import '../../sample/sample_data.dart';
import '../battle/battle_screen.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../opponent/battle_definitions.dart';
import '../opponent/cpu_party.dart';
import '../opponent/pvp_client.dart';
import '../opponent/pvp_opponent.dart';

/// 初回の導線 (手持ちが空の時に写真を選んでそのまま戦う 1 戦目) の対戦相手と、その対戦に使う定義。
/// `pvpOpponent` は相手が他のユーザーの時の候補そのもの (バトルの画面の通報・ブロックの宛先)。CPU トレーナーの時は null。
typedef FirstBattleOpponent = ({
  String opponentName,
  List<OwnedMonster> opponentParty,
  BattleOpponentKind opponentKind,
  PvpOpponent? pvpOpponent,
  MasterData definitions,
});

/// 生まれたモンスターを手持ちに入れた後の [dexStore] の手持ちと戦う、初回のバトルの相手を決める。
/// 他のユーザーの候補 ([PvpClient.fetchOpponents]。手持ちの平均レベルが近い順) の先頭の 1 人と戦う。
/// 候補を取れない時 (ログインが無い・候補が 0 人・呼び出しの失敗) は、見本の CPU トレーナーの手持ちのレベルを
/// [randomSeed] で自分の手持ちに合わせて戦う ([buildCpuParty])。定義を読み直せない時は例外を投げる ([prepareBattleDefinitions])。
Future<FirstBattleOpponent> prepareFirstBattleOpponent({
  required DexStore dexStore,
  required PvpClient pvpClient,
  required SampleData sampleData,
  required int randomSeed,
}) async {
  List<PvpOpponent>? pvpOpponents;
  try {
    pvpOpponents = await pvpClient.fetchOpponents();
  } catch (_) {
    // 初回の 1 戦は他のユーザーを読めなくても止めず、CPU トレーナーと戦わせる (issue #45 の「取れない時は CPU」)
  }
  final pvpOpponent = pvpOpponents?.firstOrNull;
  if (pvpOpponent != null) {
    return (
      opponentName: pvpOpponent.displayName,
      opponentParty: pvpOpponent.monsters,
      opponentKind: BattleOpponentKind.pvp,
      pvpOpponent: pvpOpponent,
      definitions: await prepareBattleDefinitions(
        dexStore: dexStore,
        pvpClient: pvpClient,
        pvpOpponentMonsters: pvpOpponent.monsters,
      ),
    );
  }
  final cpuOpponent = sampleData.opponents.firstWhere(
    (opponent) => opponent.id == cpuOpponentId,
    orElse: () => throw StateError('見本データに CPU トレーナーが無い'),
  );
  return (
    opponentName: cpuOpponent.name,
    opponentParty: buildCpuParty(
      monsters: [
        for (final monsterId in cpuOpponent.monsterIds)
          sampleData.monsterById(monsterId: monsterId),
      ],
      playerParty: dexStore.party,
      randomSeed: randomSeed,
    ),
    opponentKind: BattleOpponentKind.cpu,
    pvpOpponent: null,
    definitions: await prepareBattleDefinitions(
      dexStore: dexStore,
      pvpClient: pvpClient,
      pvpOpponentMonsters: null,
    ),
  );
}
