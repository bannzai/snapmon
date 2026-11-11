import 'dart:math' as math;

import '../../sample/sample_data.dart';
import '../battle/battle_recorder.dart';
import '../battle/battle_screen.dart';
import '../dex/dex_store.dart';
import '../share/card_sharer.dart';
import 'battle_definitions.dart';
import 'cpu_party.dart';
import 'pvp_client.dart';

/// 定義を読み直し、乱数で決めた CPU の相手と [dexStore] の今の手持ちで戦う対戦の画面を作る。
/// 対戦のシーンの「ランダムな相手と戦う」と、勝敗の画面の「もう一回対戦する」が開く。
/// 図鑑の定義を読み直せない時は例外を投げる ([prepareBattleDefinitions])。
/// [playerProfile] は自分の札に出すアイコンと表示名で、読めていない時は null。
Future<BattleScreen> prepareRandomCpuBattleScreen({
  required DexStore dexStore,
  required PvpClient pvpClient,
  required SampleData sampleData,
  required BattleRecorder battleRecorder,
  required CardSharer cardSharer,
  required PlayerProfile? playerProfile,
}) async {
  final definitions = await prepareBattleDefinitions(
    dexStore: dexStore,
    pvpClient: pvpClient,
    pvpOpponentMonsters: null,
  );
  // 決着の後にレベルが上がった手持ちを渡し直さないよう、作る時の手持ちで固定する
  final playerParty = List.of(dexStore.party);
  // 押すたびに別の相手・別の展開にするため、相手を決める seed とバトルの seed は毎回作る。
  // 値の範囲は DeterministicRandom の状態 (32 bit) に合わせた。
  // Web (JavaScript) ではシフトが 32 bit に切り詰められ `1 << 32` が 0 になるため、上限は整数リテラルで書く
  final cpuOpponent = chooseRandomCpuOpponent(
    sampleData: sampleData,
    playerParty: playerParty,
    randomSeed: math.Random().nextInt(0x100000000),
  );
  return BattleScreen(
    playerParty: playerParty,
    opponentParty: cpuOpponent.opponentParty,
    opponentKind: BattleOpponentKind.cpu,
    definitions: definitions,
    randomSeed: math.Random().nextInt(0x100000000),
    battleRecorder: battleRecorder,
    onPlayerLevelsChanged: dexStore.updateLevels,
    cardSharer: cardSharer,
    firstBattleBornMonster: null,
    firstBattleMonsterIsNewlyBorn: false,
    playerProfile: playerProfile,
    opponentDisplayName: cpuOpponent.opponentName,
  );
}
