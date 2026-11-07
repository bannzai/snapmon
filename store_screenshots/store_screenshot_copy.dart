import 'package:flutter/widgets.dart';

/// App Store のスクリーンショットの 1 枚。並びが掲載順 (fastlane/screenshots の番号) になる。
enum StoreScreenshotPage {
  /// 撮る (カメラで身の回りの物を撮る)。
  capture,

  /// 生まれた (写真から生まれたモンスターのカード)。
  born,

  /// 図鑑 (手持ちと集めたモンスター)。
  dex,

  /// バトル (ターン制のバトルの途中)。
  battle,

  /// 対戦 (CPU トレーナーを選ぶ)。
  opponent,

  /// 共有 (SNS に出す図鑑のカード)。
  share,
}

/// スクリーンショットを作る言語。fastlane の locale のディレクトリの名前 (App Store と Google Play で違う) と、アプリの文言の言語の組。
enum StoreScreenshotLanguage {
  /// 日本語。
  japanese(fastlaneLocale: 'ja', playLocale: 'ja-JP', appLocale: Locale('ja')),

  /// 英語 (米国)。
  english(
    fastlaneLocale: 'en-US',
    playLocale: 'en-US',
    appLocale: Locale('en'),
  );

  const StoreScreenshotLanguage({
    required this.fastlaneLocale,
    required this.playLocale,
    required this.appLocale,
  });

  /// fastlane/screenshots/ (App Store。deliver) の下のディレクトリの名前。
  final String fastlaneLocale;

  /// fastlane/metadata/android/ (Google Play。supply) の下のディレクトリの名前。
  final String playLocale;

  /// 画面の文言 (lib/l10n/app_*.arb) の言語。
  final Locale appLocale;
}

/// Google Play のフィーチャーグラフィック (1024×500) に置く文言。アプリ名のロゴの横に置く 1 行の訴求で、
/// App Store の subtitle (fastlane/metadata/<locale>/subtitle.txt) と同じ文にする。
const Map<StoreScreenshotLanguage, String> storeFeatureGraphicTagline = {
  StoreScreenshotLanguage.japanese: '撮った写真が\nモンスターになる',
  StoreScreenshotLanguage.english: 'Your photos\nbecome monsters',
};

/// スクリーンショットの上に置くキャッチコピー (見出しと補足)。アプリの文言ではなくストアの訴求のため、ARB ではなくここに置く。
/// 何ができるかより先に、使うと何が起きるかを書く (appstore-screenshot-builder skill のキャッチコピーの訴求方針)。
/// 用語は英語の ARB (lib/l10n/app_en.arb) と揃える (図鑑 = Dex、手持ち = party、技 = move、属性 = element)。
const Map<
  StoreScreenshotLanguage,
  Map<StoreScreenshotPage, ({String headline, String subline})>
>
storeScreenshotCopy = {
  StoreScreenshotLanguage.japanese: {
    StoreScreenshotPage.capture: (
      headline: '身の回りの物を\n撮るだけ',
      subline: 'マグカップもサボテンも\nモンスターになる',
    ),
    StoreScreenshotPage.born: (
      headline: '写真そっくりの\nモンスターが生まれる',
      subline: '名前も技もステータスも\n写真の被写体から決まる',
    ),
    StoreScreenshotPage.dex: (
      headline: '集めて\n図鑑を埋めよう',
      subline: '生まれた姿のまま\nずっと図鑑に残る',
    ),
    StoreScreenshotPage.battle: (
      headline: 'ステータスと相性で\n勝負が決まる',
      subline: '素早さも威力も弱点も\nターンごとに効く',
    ),
    StoreScreenshotPage.opponent: (
      headline: 'CPU トレーナーと\n対戦しよう',
      subline: '1 戦ごとにレベルが上がる',
    ),
    StoreScreenshotPage.share: (
      headline: '生まれたモンスターを\n見せ合おう',
      subline: 'カードにして SNS に共有',
    ),
  },
  StoreScreenshotLanguage.english: {
    StoreScreenshotPage.capture: (
      headline: 'Snap anything\naround you',
      subline: 'Mugs and cacti\nturn into monsters',
    ),
    StoreScreenshotPage.born: (
      headline: 'A monster just\nlike your photo',
      subline: 'Its name, moves, and stats\ncome from what you snapped',
    ),
    StoreScreenshotPage.dex: (
      headline: 'Collect them\nand fill your Dex',
      subline: 'They keep the look\nthey were born with',
    ),
    StoreScreenshotPage.battle: (
      headline: 'Stats and elements\ndecide the battle',
      subline: 'Speed, power, and weaknesses\nmatter every turn',
    ),
    StoreScreenshotPage.opponent: (
      headline: 'Battle CPU\ntrainers',
      subline: 'Level up after every battle',
    ),
    StoreScreenshotPage.share: (
      headline: 'Show off\nyour monsters',
      subline: 'Share them as cards on social media',
    ),
  },
};
