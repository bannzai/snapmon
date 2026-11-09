// App Store のスクリーンショット (fastlane/screenshots/<locale>/) と Google Play のスクリーンショット・フィーチャーグラフィック
// (fastlane/metadata/android/<locale>/images/) を、本番の画面を見本のデータで描いて書き出す。
// 実行は `make screenshots` (flutter test store_screenshots)。通常の flutter test (test/) には含めない。
// 環境変数 STORE_SCREENSHOT_LANGUAGES (ja,en-US)・STORE_SCREENSHOT_DEVICES (iphone69,iphone63,ipad13,playphone)・
// STORE_SCREENSHOT_PAGES (capture,born,…) で、描く言語・端末・ページを絞れる (省略するとすべて)。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:snapmon/audio/game_audio.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/home/home_shell.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/features/session/session_store.dart';
import 'package:snapmon/features/settings/account_store.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/share_cards.dart';
import 'package:snapmon/features/title/title_screen.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/sample/sample_data.dart';
import 'package:snapmon/theme/snapmon_colors.dart';
import 'package:snapmon/theme/snapmon_text_styles.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/monster_ui/monster_parts.dart';
import 'package:snapmon/common_ui/storage_image.dart';

import '../test/battle_recorder_fixture.dart';
import '../test/game_audio_fixture.dart';
import '../test/pvp_client_fixture.dart';
import '../test/sample_data_fixture.dart';
import 'store_screenshot_copy.dart';
import 'store_screenshot_fixtures.dart';

/// スクリーンショットを出すストア。書き出す先のディレクトリとファイル名の付け方が違う。
enum StoreScreenshotStore {
  /// App Store (fastlane の deliver)。fastlane/screenshots/<locale>/<端末>_<番号>_<ページ>.png に書き出す。
  appStore,

  /// Google Play (fastlane の supply)。fastlane/metadata/android/<locale>/images/phoneScreenshots/<番号>_<ページ>.png に書き出す
  /// (supply はファイル名の順に並べるため、端末の名前ではなく番号を先頭にする)。
  googlePlay,
}

/// スクリーンショットを作る端末。App Store の画素の大きさは App Store Connect が受け付ける大きさ
/// (https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/ 。
/// fastlane の deliver も同じ大きさで端末の種類を見分ける: deliver/lib/deliver/app_screenshot.rb の DEVICE_RESOLUTIONS)。
/// Google Play の画素の大きさは Play Console の推奨 (9:16 で 1080×1920 以上。
/// https://support.google.com/googleplay/android-developer/answer/9866151 「9:16 for portrait screenshots」「minimum 1080x1920px」)。
/// 論理の大きさ (画素 / 倍率) は各端末の画面の論理の大きさで、アプリの画面もその大きさで描く。
enum StoreScreenshotDevice {
  /// 6.9 インチの iPhone (iPhone 16 Pro Max 等)。
  iPhone69(
    store: StoreScreenshotStore.appStore,
    fileNamePrefix: 'iphone69',
    pixelSize: Size(1320, 2868),
    devicePixelRatio: 3,
    // Dynamic Island の端末の上下の安全域の高さ
    safeAreaPadding: EdgeInsets.only(top: 62, bottom: 34),
    isTablet: false,
  ),

  /// 6.3 インチの iPhone (iPhone 16 Pro 等)。App Store Connect の提出に必須の大きさ。
  iPhone63(
    store: StoreScreenshotStore.appStore,
    fileNamePrefix: 'iphone63',
    pixelSize: Size(1206, 2622),
    devicePixelRatio: 3,
    safeAreaPadding: EdgeInsets.only(top: 62, bottom: 34),
    isTablet: false,
  ),

  /// 13 インチの iPad (iPad Pro 13 インチ等)。iPad で動くアプリ (TARGETED_DEVICE_FAMILY に 2 を含む) の提出に必須の大きさ。
  iPad13(
    store: StoreScreenshotStore.appStore,
    fileNamePrefix: 'ipad13',
    pixelSize: Size(2064, 2752),
    devicePixelRatio: 2,
    // ホームボタンの無い iPad の上下の安全域の高さ
    safeAreaPadding: EdgeInsets.only(top: 24, bottom: 20),
    isTablet: true,
  ),

  /// Google Play の電話 (9:16 の 1080×1920)。倍率 2.5 で論理の大きさを 432×768 にし、画素の大きさを整数で割り切る。
  playPhone(
    store: StoreScreenshotStore.googlePlay,
    fileNamePrefix: 'playphone',
    pixelSize: Size(1080, 1920),
    devicePixelRatio: 2.5,
    // ステータスバー (24dp) とジェスチャーナビゲーションのバー (16dp) の高さ
    safeAreaPadding: EdgeInsets.only(top: 24, bottom: 16),
    isTablet: false,
  );

  const StoreScreenshotDevice({
    required this.store,
    required this.fileNamePrefix,
    required this.pixelSize,
    required this.devicePixelRatio,
    required this.safeAreaPadding,
    required this.isTablet,
  });

  /// 書き出す先のストア。
  final StoreScreenshotStore store;

  /// 書き出すファイルの名前の先頭 (App Store) と、環境変数 STORE_SCREENSHOT_DEVICES で指す名前。
  final String fileNamePrefix;

  /// 書き出す画像の画素の大きさ。
  final Size pixelSize;

  /// 論理の大きさから画素への倍率。
  final double devicePixelRatio;

  /// アプリの画面の上下の安全域 (ステータスバーとホームインジケーター)。
  final EdgeInsets safeAreaPadding;

  /// iPad か。
  final bool isTablet;

  /// 論理の大きさ (アプリの画面の大きさ)。
  Size get logicalSize => pixelSize / devicePixelRatio;

  /// [language] の [page] の画像を書き出すファイル。
  File screenshotFile({
    required StoreScreenshotLanguage language,
    required StoreScreenshotPage page,
  }) {
    final number = (page.index + 1).toString().padLeft(2, '0');
    return switch (store) {
      StoreScreenshotStore.appStore => File(
        'fastlane/screenshots/${language.fastlaneLocale}/'
        '${fileNamePrefix}_${number}_${page.name}.png',
      ),
      StoreScreenshotStore.googlePlay => File(
        '${playImagesDirectory(language: language)}/phoneScreenshots/'
        '${number}_${page.name}.png',
      ),
    };
  }
}

/// Google Play の [language] の画像 (スクリーンショット・フィーチャーグラフィック・アイコン) のディレクトリ
/// (supply が読む fastlane/metadata/android/<locale>/images/)。
String playImagesDirectory({required StoreScreenshotLanguage language}) =>
    'fastlane/metadata/android/${language.playLocale}/images';

/// Google Play のフィーチャーグラフィックの画素の大きさ (Play Console の要件
/// https://support.google.com/googleplay/android-developer/answer/9866151 「Dimensions: 1024px by 500px」)。
const Size featureGraphicPixelSize = Size(1024, 500);

/// 環境変数 [name] (カンマ区切り) で絞った [values]。環境変数が無ければすべて。
List<T> _selected<T>({
  required String name,
  required List<T> values,
  required String Function(T value) keyOf,
}) {
  final keys = Platform.environment[name]?.split(',').toSet();
  return [
    for (final value in values)
      if (keys == null || keys.contains(keyOf(value))) value,
  ];
}

void main() {
  final sampleData = loadSampleDataFixture();

  testWidgets('App Store のスクリーンショットを fastlane/screenshots に書き出す', (
    tester,
  ) async {
    await tester.runAsync(loadStoreScreenshotFonts);
    CameraPlatform.instance = StoreScreenshotCameraPlatform(
      viewfinderPhoto: storeScreenshotViewfinderPhoto(),
    );
    // 切り出した絵は先にデコードしておく。バトル画面は initState で絵を読み始め、widget test の偽の時間の中では
    // 画像のデコードが終わらないため、デコード済みの画像をすぐ返す (_cardSharer)
    final artImagesByPath = (await tester.runAsync(
      () async => {
        for (final monster in storeScreenshotMonsters())
          monster.artPath!: await decodeImageFromList(
            (await loadStoreScreenshotStorageImage(
              storagePath: monster.artPath!,
            ))!,
          ),
      },
    ))!;
    addTearDown(() {
      for (final artImage in artImagesByPath.values) {
        artImage.dispose();
      }
    });
    addTearDown(tester.view.reset);
    // 端末とカードの影を描く (flutter_test は既定で影を描かない)。flutter_test はテストの本体の後に既定のままかを
    // 確かめるため、本体の中で既定に戻す
    debugDisableShadows = false;
    try {
      for (final language in _selected(
        name: 'STORE_SCREENSHOT_LANGUAGES',
        values: StoreScreenshotLanguage.values,
        keyOf: (language) => language.fastlaneLocale,
      )) {
        for (final device in _selected(
          name: 'STORE_SCREENSHOT_DEVICES',
          values: StoreScreenshotDevice.values,
          keyOf: (device) => device.fileNamePrefix,
        )) {
          for (final page in _selected(
            name: 'STORE_SCREENSHOT_PAGES',
            values: StoreScreenshotPage.values,
            keyOf: (page) => page.name,
          )) {
            await _writeScreenshot(
              tester: tester,
              sampleData: sampleData,
              artImagesByPath: artImagesByPath,
              language: language,
              device: device,
              page: page,
            );
          }
        }
      }
    } finally {
      debugDisableShadows = true;
    }
  });

  testWidgets('Google Play のフィーチャーグラフィックを fastlane/metadata/android に書き出す', (
    tester,
  ) async {
    await tester.runAsync(loadStoreScreenshotFonts);
    addTearDown(tester.view.reset);
    for (final language in _selected(
      name: 'STORE_SCREENSHOT_LANGUAGES',
      values: StoreScreenshotLanguage.values,
      keyOf: (language) => language.fastlaneLocale,
    )) {
      await _writeFeatureGraphic(tester: tester, language: language);
    }
  });
}

/// Google Play のフィーチャーグラフィック (1024×500) を 1 枚描いて書き出す。
Future<void> _writeFeatureGraphic({
  required WidgetTester tester,
  required StoreScreenshotLanguage language,
}) async {
  tester.view
    ..physicalSize = featureGraphicPixelSize
    ..devicePixelRatio = 1;
  const canvasKey = Key('store-feature-graphic-canvas');
  await tester.pumpWidget(
    _FeatureGraphicCanvas(key: canvasKey, language: language),
  );
  await tester.pump();
  final pngBytes = await tester.runAsync(
    () => _encodeOpaquePng(tester: tester, key: canvasKey, pixelRatio: 1),
  );
  File('${playImagesDirectory(language: language)}/featureGraphic.png')
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(pngBytes!);
  await tester.pumpWidget(const SizedBox.shrink());
}

/// [key] の RepaintBoundary を [pixelRatio] 倍で画像にし、透明を含まない (アルファの無い RGB の) PNG にする。
/// App Store のスクリーンショットと Google Play のスクリーンショット・フィーチャーグラフィックは透明を受け付けない。
Future<List<int>> _encodeOpaquePng({
  required WidgetTester tester,
  required Key key,
  required double pixelRatio,
}) async {
  final capturedImage = await tester
      .renderObject<RenderRepaintBoundary>(find.byKey(key))
      .toImage(pixelRatio: pixelRatio);
  final png = image_codec.encodePng(
    image_codec.Image.fromBytes(
      width: capturedImage.width,
      height: capturedImage.height,
      bytes: (await capturedImage.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer,
      numChannels: 4,
      order: image_codec.ChannelOrder.rgba,
    ).convert(numChannels: 3),
  );
  capturedImage.dispose();
  return png;
}

/// 1 枚を描いて [StoreScreenshotDevice.screenshotFile] に書き出す。
/// [artImagesByPath] はスクリーンショットのモンスターの切り出した絵の Storage のパスと、デコード済みの画像。
Future<void> _writeScreenshot({
  required WidgetTester tester,
  required SampleData sampleData,
  required Map<String, ui.Image> artImagesByPath,
  required StoreScreenshotLanguage language,
  required StoreScreenshotDevice device,
  required StoreScreenshotPage page,
}) async {
  tester.view
    ..physicalSize = device.pixelSize
    ..devicePixelRatio = device.devicePixelRatio;
  final monsters = storeScreenshotMonsters();
  final dexStore = DexStore(definitions: sampleData.definitions)
    ..applyServerSnapshot(
      monsters: monsters,
      partyMonsterIds: [
        for (final monster in monsters.take(3)) monster.definition.id,
      ],
      definitions: null,
    );
  final shareMonster = monsters[1];
  const canvasKey = Key('store-screenshot-canvas');
  await tester.pumpWidget(
    _StoreScreenshotCanvas(
      key: canvasKey,
      language: language,
      device: device,
      page: page,
      artImagesByPath: artImagesByPath,
      content: switch (page) {
        StoreScreenshotPage.capture => _homeShell(
          sampleData: sampleData,
          dexStore: dexStore,
          initialTab: HomeTab.capture,
          artImagesByPath: artImagesByPath,
        ),
        StoreScreenshotPage.born => ResultScreen(
          monster: monsters.first,
          dexStore: dexStore,
          origin: ResultScreenOrigin.newlyBorn,
          cardSharer: _cardSharer(artImagesByPath: artImagesByPath),
        ),
        StoreScreenshotPage.dex => _homeShell(
          sampleData: sampleData,
          dexStore: dexStore,
          initialTab: HomeTab.dex,
          artImagesByPath: artImagesByPath,
        ),
        StoreScreenshotPage.battle => BattleScreen(
          playerParty: monsters.take(3).toList(),
          // 相手も切り出した絵のあるモンスターにする (見本のモンスターは絵が無く、仮の図形で描かれるため)
          opponentParty: [
            for (final monster in monsters.skip(3))
              _withLevel(monster: monster, level: 10),
          ],
          opponentKind: BattleOpponentKind.cpu,
          definitions: sampleData.definitions,
          // 生成し直しても同じ場面になるよう、乱数の seed を固定する
          randomSeed: 7,
          battleRecorder: fakeBattleRecorder(
            calls: RecordedBattleCalls(),
            startBattleRecord: () async => null,
            recordedLevels: const {},
          ),
          onPlayerLevelsChanged: ({required levelsByMonsterId}) {},
          cardSharer: _cardSharer(artImagesByPath: artImagesByPath),
          firstBattleBornMonster: null,
          firstBattleMonsterIsNewlyBorn: false,
          // 対戦タブ (_homeShell) の表示名と同じにする
          playerProfile: (displayName: 'snap', iconPath: null),
          opponentDisplayName: sampleData.cpuTrainerNames.first,
        ),
        StoreScreenshotPage.opponent => _homeShell(
          sampleData: sampleData,
          dexStore: dexStore,
          initialTab: HomeTab.opponent,
          artImagesByPath: artImagesByPath,
        ),
        StoreScreenshotPage.share => MonsterShareCard(
          monster: shareMonster,
          artImagesByPath: {
            shareMonster.artPath!: artImagesByPath[shareMonster.artPath!]!,
          },
          definitions: sampleData.definitions,
          format: ShareCardFormat.portrait,
        ),
      },
    ),
  );
  if (page == StoreScreenshotPage.battle) {
    // 技を 1 つ選び、攻撃・被弾の演出 (lib/features/battle/battle_screen.dart の _lungeDuration・_hitDuration) を進める
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('move-slot-0')));
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  await _settleImages(tester: tester);
  final pngBytes = await tester.runAsync(
    () => _encodeOpaquePng(
      tester: tester,
      key: canvasKey,
      pixelRatio: device.devicePixelRatio,
    ),
  );
  device.screenshotFile(language: language, page: page)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(pngBytes!);
  // 次の 1 枚の前に、この画面 (カメラ・バトルの演出) を閉じる
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}

/// 画像 (写真・切り出した絵・ファインダーの写真) を読み終えるまで描き進める。
/// 画像のデコードは本物の非同期の処理のため、runAsync の中で待ってから描き直す。
Future<void> _settleImages({required WidgetTester tester}) async {
  for (var frame = 0; frame < 10; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.runAsync(() async {
    for (final element in find.byType(Image).evaluate()) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// [monster] のレベルを [level] にしたもの。
OwnedMonster _withLevel({required OwnedMonster monster, required int level}) =>
    OwnedMonster(
      definition: monster.definition,
      level: level,
      artPath: monster.artPath,
      decoration: monster.decoration,
      decorationVersion: monster.decorationVersion,
      definitionIds: monster.definitionIds,
    );

/// 切り出した絵を [artImagesByPath] のデコード済みの画像の複製で返す関数 (受け取った側が使い終わった画像を dispose するため)。
/// バトル画面 (_cardSharer) と図鑑・生まれたカード (MonsterArtImageLoaderScope) が使う。
LoadMonsterArtImage _loadArtImage({
  required Map<String, ui.Image> artImagesByPath,
}) =>
    ({required artPath}) async =>
        artImagesByPath[artPath]?.clone() ??
        (throw StateError('$artPath の絵はスクリーンショットに用意していない'));

/// 共有の操作をしない画面に渡す [CardSharer]。loadArtImage は [_loadArtImage]。
CardSharer _cardSharer({required Map<String, ui.Image> artImagesByPath}) =>
    CardSharer(
      loadArtImage: _loadArtImage(artImagesByPath: artImagesByPath),
      renderPng: ({required view, required card, required format}) =>
          throw StateError('スクリーンショットでは共有しない'),
      shareImage:
          ({
            required pngBytes,
            required fileName,
            required text,
            required sharePositionOrigin,
          }) => throw StateError('スクリーンショットでは共有しない'),
      logEvent: ({required event, required parameters}) async {},
    );

/// ログイン済みで、図鑑・撮る・対戦のタブを持つ画面。戦績は見本を返す (対戦の相手は CPU トレーナーだけで、他のユーザーは読まない。issue #130)。
/// [artImagesByPath] は切り出した絵の Storage のパスとデコード済みの画像 (_cardSharer に渡す)。
Widget _homeShell({
  required SampleData sampleData,
  required DexStore dexStore,
  required HomeTab initialTab,
  required Map<String, ui.Image> artImagesByPath,
}) {
  final sessionStore = SessionStore(
    startSession: () async => 'store-screenshot-uid',
    endSession: () async {},
    resumedUid: 'store-screenshot-uid',
  );
  return HomeShell(
    initialTab: initialTab,
    // 撮るページはファインダーに写真を映すため、押すのを待たずにカメラを開いた状態で描く
    startsCameraOnCaptureOpen: initialTab == HomeTab.capture,
    sampleData: sampleData,
    dexStore: dexStore,
    sessionStore: sessionStore,
    openUrl: ({required uri}) async => true,
    isDeveloperMenuEnabled: false,
    battleRecorder: fakeBattleRecorder(
      calls: RecordedBattleCalls(),
      startBattleRecord: () async => null,
      recordedLevels: const {},
    ),
    monsterGenerator: MonsterGenerator(
      listCameras: () async => const [StoreScreenshotCameraPlatform.backCamera],
      openAppSettings: () async => false,
      pickAlbumPhoto: () async => null,
      preparePhoto: ({required sourceBytes}) async => sourceBytes,
      createSubjectMask: ({required photo}) =>
          throw StateError('スクリーンショットでは生成しない'),
      createSquareMask: ({required photo, required crop}) =>
          throw StateError('スクリーンショットでは生成しない'),
      createCutoutPreview: ({required photo, required mask}) =>
          throw StateError('スクリーンショットでは生成しない'),
      createRequestId: () => 'store-screenshot-request',
      uploadPhoto: ({required requestId, required photo}) async {},
      uploadMask: ({required requestId, required mask}) =>
          throw StateError('スクリーンショットでは生成しない'),
      requestGeneration:
          ({
            required requestId,
            required maskSource,
            required onCompletedStage,
          }) => throw StateError('スクリーンショットでは生成しない'),
      fetchGeneration: ({required requestId}) =>
          throw StateError('スクリーンショットでは生成しない'),
      fetchTicketPackages: () async => const [],
      purchaseTicketPackage: ({required package}) =>
          throw StateError('スクリーンショットでは購入しない'),
      syncTicketPurchases: () async {},
      watchGenerationTickets: () => const Stream.empty(),
      logEvent: ({required event, required parameters}) async {},
    ),
    pvpClient: fakePvpClient(
      calls: RecordedPvpCalls(),
      fetchOpponents: () async => null,
      extraDefinitions: null,
      battleRecord: (wins: 14, losses: 6),
      profile: (displayName: 'snap', iconPath: null),
      reportMonster: () async {},
      blockUser: () async {},
      updateDisplayName: ({required displayName}) async => displayName,
      updateIcon: ({required photo}) async => throw StateError('使わない'),
    ),
    cardSharer: _cardSharer(artImagesByPath: artImagesByPath),
    accountStore: AccountStore(
      sessionStore: sessionStore,
      linkProviderName: 'Apple',
      readLinkedProviderNames: () => const [],
      linkAccount: () async => null,
      discardCurrentAccount: () async {},
      deleteAccount: () async {},
    ),
  );
}

/// 1 枚のスクリーンショット。地の色の上にキャッチコピーを置き、その下に端末の枠に入れたアプリの画面 ([content]) を置く。
/// 共有のページは、端末の枠ではなく共有するカードの画像そのものを置く。
class _StoreScreenshotCanvas extends StatelessWidget {
  const _StoreScreenshotCanvas({
    required super.key,
    required this.language,
    required this.device,
    required this.page,
    required this.content,
    required this.artImagesByPath,
  });

  /// キャッチコピーとアプリの画面の言語。
  final StoreScreenshotLanguage language;

  /// 描く端末 (画面の大きさと、iPad なら文字と余白を大きくする)。
  final StoreScreenshotDevice device;

  /// 描くページ (キャッチコピーと、共有のページだけ端末の枠ではなくカードの枠にする)。
  final StoreScreenshotPage page;

  /// 端末の枠 (共有のページはカードの枠) の中に描く画面。
  final Widget content;

  /// 切り出した絵の Storage のパスとデコード済みの画像 (_DeviceFrame に渡す)。
  final Map<String, ui.Image> artImagesByPath;

  @override
  Widget build(BuildContext context) {
    final copy = storeScreenshotCopy[language]![page]!;
    // iPad は画面が広いため、文字と余白を大きくする。論理の幅の比 (iPad 13 の 1032 / iPhone 6.9 の 440 = 2.35) より小さい
    // 1.9 にし、見出しの長い行にも左右の余白を残した (2026-10-26 の run 40325860131 の ipad13 の画像で、見出しが 2 行に
    // 収まり左右に余白があることを目視で確かめた。2.35 では描いて確かめていない)
    final scale = device.isTablet ? 1.9 : 1.0;
    return RepaintBoundary(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: snapmonThemeData(),
        locale: language.appLocale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Material で包み、文字が MaterialApp のエラー用の文字の形 (太さ w900・黄色の二重下線) を受け継がないようにする
        home: Material(
          color: SnapmonColors.background,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24 * scale, 56 * scale, 24 * scale, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  copy.headline,
                  textAlign: TextAlign.center,
                  style: SnapmonTextStyles.hero.copyWith(
                    fontSize: 32 * scale,
                    height: 1.3,
                    color: SnapmonColors.accent,
                  ),
                ),
                SizedBox(height: 14 * scale),
                Text(
                  copy.subline,
                  textAlign: TextAlign.center,
                  style: SnapmonTextStyles.body.copyWith(
                    fontSize: 17 * scale,
                    height: 1.5,
                    color: SnapmonColors.textOnBackground,
                  ),
                ),
                SizedBox(height: 32 * scale),
                Expanded(
                  child: page == StoreScreenshotPage.share
                      ? _ShareCardFrame(card: content, scale: scale)
                      : _DeviceFrame(
                          device: device,
                          screen: content,
                          artImagesByPath: artImagesByPath,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Google Play のフィーチャーグラフィック (横長 1024×500)。地の色の上に、左にタイトル画面のヒーロー (浮遊の途中の絵)、
/// 右にアプリ名のロゴと訴求の文言を置く。ヒーローの絵はタイトル画面と同じ [TitleHeroPainter] で描く
/// (アプリアイコンとも同じ形で、ストアの掲載とアプリの見た目を揃えるため)。
class _FeatureGraphicCanvas extends StatelessWidget {
  const _FeatureGraphicCanvas({required super.key, required this.language});

  /// 訴求の文言の言語。
  final StoreScreenshotLanguage language;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: snapmonThemeData(),
      locale: language.appLocale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Material(
        color: SnapmonColors.background,
        child: Row(
          children: [
            // ヒーローは見出しの分 (72) を下に空けて中心を決めるため、その分だけ高く描いて絵の中心を画像の上下の中央に置く
            // (はみ出す 72 は見出しの場所で、絵は無い)
            SizedBox(
              width: 440,
              height: featureGraphicPixelSize.height,
              child: OverflowBox(
                alignment: Alignment.topCenter,
                minHeight: featureGraphicPixelSize.height + 72,
                maxHeight: featureGraphicPixelSize.height + 72,
                child: const CustomPaint(
                  painter: TitleHeroPainter(
                    progress: 0.5,
                    eyeLidClosure: 0,
                    pupilOffset: Offset.zero,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 56),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'snapmon',
                      style: SnapmonTextStyles.logo.copyWith(fontSize: 56),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      storeFeatureGraphicTagline[language]!,
                      style: SnapmonTextStyles.hero.copyWith(
                        fontSize: 40,
                        height: 1.3,
                        color: SnapmonColors.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// アプリの画面を端末の論理の大きさで描き、角の丸い端末の枠に収める。枠は余りの高さに収まる大きさにする。
class _DeviceFrame extends StatelessWidget {
  const _DeviceFrame({
    required this.device,
    required this.screen,
    required this.artImagesByPath,
  });

  /// 枠の形と、アプリの画面の論理の大きさ・倍率・安全域を決める端末。
  final StoreScreenshotDevice device;

  /// 枠の中に描くアプリの画面。
  final Widget screen;

  /// 切り出した絵の Storage のパスとデコード済みの画像 (画面の中の MonsterArt が読む)。
  final Map<String, ui.Image> artImagesByPath;

  @override
  Widget build(BuildContext context) {
    final screenSize = device.logicalSize;
    // 枠の太さと角の丸みは、iPhone・iPad の実機の外形に近い比率 (画面の幅に対する割合) にした
    final bezel = screenSize.width * (device.isTablet ? 0.03 : 0.045);
    final screenRadius = screenSize.width * (device.isTablet ? 0.03 : 0.13);
    return Align(
      alignment: Alignment.topCenter,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF0A0810),
            borderRadius: BorderRadius.circular(screenRadius + bezel),
            border: Border.all(color: SnapmonColors.surfaceRaised, width: 3),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 40),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(bezel),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(screenRadius),
              child: SizedBox.fromSize(
                size: screenSize,
                child: MediaQuery(
                  data: MediaQueryData(
                    size: screenSize,
                    devicePixelRatio: device.devicePixelRatio,
                    padding: device.safeAreaPadding,
                    viewPadding: device.safeAreaPadding,
                  ),
                  child: StorageImageLoaderScope(
                    loadBytes: loadStoreScreenshotStorageImage,
                    child: MonsterArtImageLoaderScope(
                      loadArtImage: _loadArtImage(
                        artImagesByPath: artImagesByPath,
                      ),
                      // 撮影では音を鳴らさない (バトル画面・下タブの画面が GameAudioScope を求めるため置く)
                      child: GameAudioScope(
                        gameAudio: fakeGameAudio(
                          calls: RecordedAudioCalls(),
                          isBackgroundMusicEnabled: false,
                          isSoundEffectsEnabled: false,
                          waitsForUserInteractionBeforeBackgroundMusic: false,
                        ),
                        child: MaterialApp(
                          debugShowCheckedModeBanner: false,
                          theme: snapmonThemeData(),
                          locale: Localizations.localeOf(context),
                          localizationsDelegates:
                              AppLocalizations.localizationsDelegates,
                          supportedLocales: AppLocalizations.supportedLocales,
                          home: screen,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 共有するカード (縦長 1080×1920 の論理の大きさ) を、角を丸めて余りの高さに収める。
class _ShareCardFrame extends StatelessWidget {
  const _ShareCardFrame({required this.card, required this.scale});

  /// 枠の中に描く共有のカード。
  final Widget card;

  /// 下の余白の倍率 (_StoreScreenshotCanvas の文字と余白の倍率と同じ。iPad で大きくする)。
  final double scale;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 48 * scale),
    child: Align(
      alignment: Alignment.topCenter,
      child: FittedBox(
        fit: BoxFit.contain,
        alignment: Alignment.topCenter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: SnapmonColors.surfaceRaised, width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 40),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: SizedBox.fromSize(
              size: ShareCardFormat.portrait.logicalSize,
              child: card,
            ),
          ),
        ),
      ),
    ),
  );
}
