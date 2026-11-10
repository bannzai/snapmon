import '../features/capture/monster_generator.dart';
import '../features/dex/dex_store.dart';
import '../features/dex/owned_monster.dart';
import 'sample_data.dart';

/// 生成 (Functions の generate) の代わりに、見本のモンスターを図鑑に入れて生成の結果を返す。
/// DEBUG ビルドで「ログインせずに使う」時だけ main.dart が使う (Functions のデプロイや App Check の debug token の登録が
/// 済んでいない検証環境 (simtunnel・webtunnel) でも、写真を選んでから戦うまでの導線を確かめるため。issue #45)。
///
/// [sampleData] の見本のモンスターのうち [dexStore] の図鑑にまだいない最初の 1 体を、レベル 1 (生まれたばかり) にして
/// 図鑑に足し、[requestID] の saved を返す。全部いる時は先頭の見本のモンスターの duplicate を返す (同じ被写体の扱いを確かめるため)。
/// サーバーに繋いでいない図鑑だけに使う ([DexStore.applyServerSnapshot] で端末の図鑑に足すため)。
GenerationResult generateSampleMonster({
  required DexStore dexStore,
  required SampleData sampleData,
  required String requestID,
}) {
  final sampleMonster = sampleData.monsters
      .where((monster) => !dexStore.contains(monsterID: monster.definition.id))
      .firstOrNull;
  if (sampleMonster == null) {
    return GenerationResult(
      requestID: requestID,
      status: GenerationStatus.duplicate,
      monsterID: sampleData.monsters.first.definition.id,
      rejectionReason: null,
      personDetected: false,
    );
  }
  dexStore.applyServerSnapshot(
    monsters: [
      ...dexStore.monsters,
      OwnedMonster(
        definition: sampleMonster.definition,
        level: 1,
        actionCardMoveIDs: const [],
        artPath: sampleMonster.artPath,
        definitionIDs: sampleMonster.definitionIDs,
        decoration: sampleMonster.decoration,
        decorationVersion: sampleMonster.decorationVersion,
      ),
    ],
    partyMonsterIDs: null,
    definitions: null,
  );
  return GenerationResult(
    requestID: requestID,
    status: GenerationStatus.saved,
    monsterID: sampleMonster.definition.id,
    rejectionReason: null,
    personDetected: false,
  );
}
