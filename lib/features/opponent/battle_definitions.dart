import '../../domain/master/master_data.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';
import 'pvp_client.dart';

/// 対戦の直前に図鑑の定義を最新の master から読み直し、対戦に使う定義を返す。
/// [pvpOpponentMonsters] (他のユーザーの手持ち) を渡した時は、相手のモンスターが参照するその場で作った定義も足す。
/// CPU トレーナー (見本の対戦相手) と戦う時は null を渡す。
/// 相性表は対戦時点の最新の版を両者に適用する (documents/adr/0001-tech-stack.md) ため、読み直せない時は古い版で戦わせず例外を投げる。
Future<MasterData> prepareBattleDefinitions({
  required DexStore dexStore,
  required PvpClient pvpClient,
  required List<OwnedMonster>? pvpOpponentMonsters,
}) async {
  await dexStore.refreshDefinitions();
  if (pvpOpponentMonsters == null) {
    // 見本の対戦相手の属性・技は master と同じ ID・同じ値のため (test/sample/sample_data_test.dart)、
    // 図鑑の定義 (サーバーの master と図鑑が参照する定義) から両者を引ける
    return dexStore.definitions;
  }
  return pvpClient.fetchDefinitions(
    base: dexStore.definitions,
    definitionIds: [
      for (final monster in pvpOpponentMonsters) ...monster.definitionIds,
    ],
  );
}
