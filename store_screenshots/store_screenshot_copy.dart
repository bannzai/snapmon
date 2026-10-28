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

  /// 対戦 (他のトレーナーと CPU トレーナーを選ぶ)。
  opponent,

  /// 共有 (SNS に出す図鑑のカード)。
  share,
}

/// スクリーンショットを作る言語。fastlane の locale のディレクトリの名前と、アプリの文言の言語の組。
enum StoreScreenshotLanguage {
  /// 日本語。
  japanese(fastlaneLocale: 'ja', appLocale: Locale('ja')),

  /// 英語 (米国)。
  english(fastlaneLocale: 'en-US', appLocale: Locale('en'));

  const StoreScreenshotLanguage({
    required this.fastlaneLocale,
    required this.appLocale,
  });

  /// fastlane/screenshots/ の下のディレクトリの名前。
  final String fastlaneLocale;

  /// 画面の文言 (lib/l10n/app_*.arb) の言語。
  final Locale appLocale;
}

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
      subline: '元の写真は自分だけに見える',
    ),
    StoreScreenshotPage.battle: (
      headline: 'ステータスと相性で\n勝負が決まる',
      subline: '素早さも威力も弱点も\nターンごとに効く',
    ),
    StoreScreenshotPage.opponent: (
      headline: 'ほかのトレーナーと\n対戦しよう',
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
      subline: 'Only you can see your original photos',
    ),
    StoreScreenshotPage.battle: (
      headline: 'Stats and elements\ndecide the battle',
      subline: 'Speed, power, and weaknesses\nmatter every turn',
    ),
    StoreScreenshotPage.opponent: (
      headline: 'Battle other\ntrainers',
      subline: 'Level up after every battle',
    ),
    StoreScreenshotPage.share: (
      headline: 'Show off\nyour monsters',
      subline: 'Share them as cards on social media',
    ),
  },
};
