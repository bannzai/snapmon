/// 利用者に見せるアプリの名前。ロゴとタスクスイッチャー・ブラウザのタブの名前に使う
/// (スペースなしの 1 語で、日本語でも同じ表記。https://github.com/bannzai/snapmon/issues/343 )。
/// ホーム画面のアイコンの下の名前 (ios/Runner/Info.plist・AndroidManifest.xml・web/) と
/// 文言 (lib/l10n/app_*.arb) は Dart の定数を読めないため、同じ表記をそれぞれに書いている。
const String appDisplayName = 'SnapMonster';
