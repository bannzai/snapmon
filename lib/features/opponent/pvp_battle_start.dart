import 'package:flutter/widgets.dart';

import '../../common_ui/scene_route.dart';
import '../../domain/master/master_data.dart';
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
/// 手持ちは [dexStore] の今の手持ちではなく、組み合わせた時点の 2 人の手持ちの写し (`pvpBattles/{battleID}`) を使う
/// (2 人の端末が同じ入力から計算するため)。定義は、相手を探した時に版を伝えた定義 [definitions] に、2 人のモンスターが参照する
/// その場で作った定義を足す。[dexStore] の今の定義は使わない (探している間に図鑑の定義が新しい master に替わると、
/// 相手と違う版で計算することになるため)。
/// 相手の通報・ブロックのメニュー ([OpponentSafetyMenuButton]) と、勝者の報告を挟む記録 ([pvpBattleRecorder]) を画面に渡す。
/// [firstBattleBornMonster]・[firstBattleMonsterIsNewlyBorn] は初回の 1 戦の時だけ渡す ([BattleScreen.firstBattleBornMonster])。
/// ログインが無い時・対戦を読めない時・定義を読めない時は例外を投げる。
Future<BattleScreen> preparePvpBattleScreen({
  required String battleID,
  required MasterData definitions,
  required DexStore dexStore,
  required PvpClient pvpClient,
  required BattleRecorder battleRecorder,
  required CardSharer cardSharer,
  required OwnedMonster? firstBattleBornMonster,
  required bool firstBattleMonsterIsNewlyBorn,
}) async {
  final playerUID = pvpClient.battleClient.signedInUID();
  final battle = await pvpClient.battleClient
      .watchBattle(battleID: battleID)
      .first;
  if (playerUID == null || battle == null) {
    throw StateError('対戦を読み込めませんでした');
  }
  final session = PvpBattleSession(
    client: pvpClient.battleClient,
    battle: battle,
    playerUID: playerUID,
    definitions: await pvpClient.fetchDefinitions(
      base: definitions,
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
          battleID: battleID,
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
  if (pvpClient.battleClient.signedInUID() != null) {
    // 同じ版の master の利用者だけを組み合わせるため、探す前に定義を最新の master から読み直す
    await dexStore.refreshDefinitions();
    // 相手に版を伝える定義と、対戦で使う定義を同じものにする (探している間に図鑑の定義が替わっても、伝えた版で計算するため)
    final definitions = dexStore.definitions;
    final matchingResult = await navigator.push(
      sceneRoute<PvpMatchingResult>(
        builder: (context) => PvpMatchingScreen(
          battleClient: pvpClient.battleClient,
          rulesVersion: pvpMatchRulesVersion(definitions: definitions),
        ),
      ),
    );
    if (matchingResult == null) {
      return null;
    }
    if (matchingResult.battleID case final battleID?) {
      return preparePvpBattleScreen(
        battleID: battleID,
        definitions: dexStore.definitions,
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
