import '../../sample/sample_data.dart';
import '../dex/dex_store.dart';
import '../dex/owned_monster.dart';

/// 写真からの生成 (#13) を実装するまでの代わり。見本のうち図鑑にいない最初の 1 体
/// (全員いれば見本の先頭) を生まれたモンスターとして図鑑に入れ、そのモンスターを返す。
OwnedMonster generateSampleMonster({
  required SampleData sampleData,
  required DexStore dexStore,
}) {
  final monster = sampleData.monsters.firstWhere(
    (sampleMonster) =>
        !dexStore.contains(monsterId: sampleMonster.definition.id),
    orElse: () => sampleData.monsters.first,
  );
  dexStore.addMonster(monster: monster);
  return monster;
}
