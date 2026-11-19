import '../features/dex/dex_store.dart';
import '../features/dex/owned_monster.dart';
import '../features/session/session_store.dart';
import 'sample_data.dart';

/// 紹介用のプレイ動画を撮る状態にする (issue #384)。DEBUG ビルドの開発者メニューだけが使う。
/// ログインを終えて「ログインせずに使う」状態にし、[dexStore] の図鑑を [SamplePlayVideo.companionMonster] だけ、手持ちを空にする。
/// 手持ちが空のため、この後に写真を選ぶと初回の導線 (生まれてそのまま戦う) になり、生成 (lib/sample/sample_generation.dart) が
/// [SamplePlayVideo.bornMonster] を生んで 2 体の手持ちにし、相手 (lib/features/opponent/cpu_party.dart) が決まった 2 体になる。
/// 撮影用かどうかは図鑑と手持ちの中身だけで決まり、別の切り替えの値は持たない。何度呼んでも同じ状態になる (冪等)。
Future<void> preparePlayVideo({
  required SessionStore sessionStore,
  required DexStore dexStore,
  required SampleData sampleData,
}) async {
  // ログインを終えた通知でサーバーの図鑑との接続が切れて図鑑が空になるため、図鑑に入れるのはその後にする
  await sessionStore.reset();
  sessionStore.skipForDebug();
  dexStore.applyServerSnapshot(
    monsters: [sampleData.playVideo.companionMonster],
    partyMonsterIDs: const [],
    definitions: null,
  );
}

/// [party] が撮影用の味方 ([SamplePlayVideo.bornMonster] と [SamplePlayVideo.companionMonster]) の 2 体だけか。並びは問わない。
bool isPlayVideoParty({
  required SampleData sampleData,
  required List<OwnedMonster> party,
}) =>
    party.length == 2 &&
    {for (final monster in party) monster.definition.id}.containsAll([
      sampleData.playVideo.bornMonster.definition.id,
      sampleData.playVideo.companionMonster.definition.id,
    ]);
