import 'package:flutter/widgets.dart';

import '../../common_ui/scene_route.dart';
import '../../sample/sample_data.dart';
import '../battle/battle_recorder.dart';
import '../battle/battle_screen.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import '../share/card_sharer.dart';
import 'opponent_safety_menu.dart';
import 'pvp_battle_session.dart';
import 'pvp_client.dart';
import 'pvp_match_search.dart';
import 'pvp_matching_screen.dart';
import 'random_cpu_battle.dart';

/// 組み合わされた人との対戦 [battleID] の対戦の画面を作る。
/// 手持ちは [dexStore] の今の手持ちではなく、組み合わせた時点の 2 人の手持ちの写し (`pvpBattles/{battleID}`) を使い
/// (2 人の端末が同じ入力から計算するため)、定義は [dexStore] の定義に 2 人のモンスターが参照するその場で作った定義を足す。
/// 定義の master は読み直さない (探す前に読み直した版で組み合わされているため。[prepareMatchedBattleScreen])。
/// 相手の通報・ブロックのメニュー ([OpponentSafetyMenuButton]) と、勝者の報告を挟む記録 ([pvpBattleRecorder]) を画面に渡す。
/// [firstBattleBornMonster]・[firstBattleMonsterIsNewlyBorn] は初回の 1 戦の時だけ渡す ([BattleScreen.firstBattleBornMonster])。
/// ログインが無い時・対戦を読めない時・定義を読めない時は例外を投げる。
Future<BattleScreen> preparePvpBattleScreen({
  required String battleID,
  required DexStore dexStore,
  required PvpClient pvpClient,
  required BattleRecorder battleRecorder,
  required CardSharer cardSharer,
  required OwnedMonster? firstBattleBornMonster,
  required bool firstBattleMonsterIsNewlyBorn,
}) async {
  final playerUid = pvpClient.battleClient.signedInUid();
  final battle = await pvpClient.battleClient
      .watchBattle(battleID: battleID)
      .first;
  if (playerUid == null || battle == null) {
    throw StateError('対戦を読み込めませんでした');
  }
  final session = PvpBattleSession(
    client: pvpClient.battleClient,
    battle: battle,
    playerUid: playerUid,
    definitions: await pvpClient.fetchDefinitions(
      base: dexStore.definitions,
      definitionIDs: [
        for (final trainer in [battle.host, battle.guest])
          for (final monster in trainer.monsters) ...monster.definitionIDs,
      ],
    ),
  );
  return BattleScreen(
    playerParty: session.player.monsters,
    opponentParty: session.opponent.monsters,
    opponentKind: BattleOpponentKind.pvp,
    pvpSession: session,
    opponentSafetyMenuBuilder: ({required revealedOpponentMonsters}) =>
        OpponentSafetyMenuButton(
          opponent: session.opponent,
          reportableMonsters: revealedOpponentMonsters,
          pvpClient: pvpClient,
        ),
    definitions: session.definitions,
    randomSeed: battle.randomSeed,
    battleRecorder: pvpBattleRecorder(base: battleRecorder, session: session),
    onPlayerLevelsChanged: dexStore.updateLevels,
    cardSharer: cardSharer,
    firstBattleBornMonster: firstBattleBornMonster,
    firstBattleMonsterIsNewlyBorn: firstBattleMonsterIsNewlyBorn,
    playerProfile: (
      displayName: session.player.displayName,
      iconPath: session.player.iconPath,
    ),
    opponentDisplayName: session.opponent.displayName,
  );
}

/// 対戦のシーンの「対戦をする」と、人との対戦の後の「もう一回対戦する」で始める対戦の画面を作る。
/// 人との対戦の待つ画面 ([PvpMatchingScreen]) を [navigator] に開いて相手を探し、組み合わされたらその対戦の画面
/// ([preparePvpBattleScreen]) を、待つ画面で「CPU と対戦をする」を選んだら CPU との対戦の画面
/// ([prepareRandomCpuBattleScreen]) を返す。待つ画面を「やめる」で閉じた時は null を返す。
/// ログインが無い時 (DEBUG ビルドでログインを飛ばした時) は、組み合わせる相手を探せないため待つ画面を開かずに CPU との対戦の画面を返す。
/// 定義を読み直せない時・対戦を読めない時は例外を投げる。
Future<BattleScreen?> prepareMatchedBattleScreen({
  required NavigatorState navigator,
  required DexStore dexStore,
  required PvpClient pvpClient,
  required SampleData sampleData,
  required BattleRecorder battleRecorder,
  required CardSharer cardSharer,
  required PlayerProfile? playerProfile,
}) async {
  if (pvpClient.battleClient.signedInUid() != null) {
    // 同じ版の master の利用者だけを組み合わせるため、探す前に定義を最新の master から読み直す
    await dexStore.refreshDefinitions();
    final matchingResult = await navigator.push(
      sceneRoute<PvpMatchingResult>(
        builder: (context) => PvpMatchingScreen(
          battleClient: pvpClient.battleClient,
          rulesVersion: pvpMatchRulesVersion(definitions: dexStore.definitions),
        ),
      ),
    );
    if (matchingResult == null) {
      return null;
    }
    if (matchingResult.battleID case final battleID?) {
      return preparePvpBattleScreen(
        battleID: battleID,
        dexStore: dexStore,
        pvpClient: pvpClient,
        battleRecorder: battleRecorder,
        cardSharer: cardSharer,
        firstBattleBornMonster: null,
        firstBattleMonsterIsNewlyBorn: false,
      );
    }
  }
  return prepareRandomCpuBattleScreen(
    dexStore: dexStore,
    pvpClient: pvpClient,
    sampleData: sampleData,
    battleRecorder: battleRecorder,
    cardSharer: cardSharer,
    playerProfile: playerProfile,
  );
}
