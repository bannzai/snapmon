/// 見本データのファイル。CPU 対戦の相手、ログインが無い時 (DEBUG ビルド) の PvP の相手の代わり、開発者メニューの見本の投入に使う。
/// Flutter に依存しないファイルに置くのは、`dart run` で動くシミュレーションのツール (tool/simulate_battles.dart) も読むため。
const String sampleDataAssetPath = 'assets/samples/sample_monsters.json';
