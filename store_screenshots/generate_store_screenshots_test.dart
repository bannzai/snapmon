// App Store のスクリーンショット (fastlane/screenshots/<locale>/) を、本番の画面を見本のデータで描いて書き出す。
// 実行は `make screenshots` (flutter test store_screenshots)。通常の flutter test (test/) には含めない。
// 環境変数 STORE_SCREENSHOT_LANGUAGES (ja,en-US)・STORE_SCREENSHOT_DEVICES (iphone69,iphone63,ipad13)・
// STORE_SCREENSHOT_PAGES (capture,born,…) で、描く言語・端末・ページを絞れる (省略するとすべて)。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_codec;
import 'package:share_plus/share_plus.dart';
import 'package:snapmon/features/battle/battle_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/home/home_shell.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/result/result_screen.dart';
import 'package:snapmon/features/session/session_store.dart';
import 'package:snapmon/features/settings/account_store.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/share_cards.dart';
import 'package:snapmon/l10n/l10n.dart';
import 'package:snapmon/sample/sample_data.dart';
import 'package:snapmon/theme/snapmon_colors.dart';
import 'package:snapmon/theme/snapmon_text_styles.dart';
import 'package:snapmon/theme/snapmon_theme.dart';
import 'package:snapmon/widgets/storage_image.dart';

import '../test/battle_recorder_fixture.dart';
import '../test/card_sharer_fixture.dart';
import '../test/pvp_client_fixture.dart';
import '../test/sample_data_fixture.dart';
import 'store_screenshot_copy.dart';
import 'store_screenshot_fixtures.dart';

/// スクリーンショットを作る端末。画素の大きさは App Store Connect が受け付ける大きさ
/// (https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/ 。
/// fastlane の deliver も同じ大きさで端末の種類を見分ける: deliver/lib/deliver/app_screenshot.rb の DEVICE_RESOLUTIONS)。
/// 論理の大きさ (画素 / 倍率) は各端末の画面の論理の大きさで、アプリの画面もその大きさで描く。
enum StoreScreenshotDevice {
  /// 6.9 インチの iPhone (iPhone 16 Pro Max 等)。
  iPhone69(
    fileNamePrefix: 'iphone69',
    pixelSize: Size(1320, 2868),
    devicePixelRatio: 3,
    // Dynamic Island の端末の上下の安全域の高さ
    safeAreaPadding: EdgeInsets.only(top: 62, bottom: 34),
    isTablet: false,
  ),

  /// 6.3 インチの iPhone (iPhone 16 Pro 等)。App Store Connect の提出に必須の大きさ。
  iPhone63(
    fileNamePrefix: 'iphone63',
    pixelSize: Size(1206, 2622),
    devicePixelRatio: 3,
    safeAreaPadding: EdgeInsets.only(top: 62, bottom: 34),
    isTablet: false,
  ),

  /// 13 インチの iPad (iPad Pro 13 インチ等)。iPad で動くアプリ (TARGETED_DEVICE_FAMILY に 2 を含む) の提出に必須の大きさ。
  iPad13(
    fileNamePrefix: 'ipad13',
    pixelSize: Size(2064, 2752),
    devicePixelRatio: 2,
    // ホームボタンの無い iPad の上下の安全域の高さ
    safeAreaPadding: EdgeInsets.only(top: 24, bottom: 20),
    isTablet: true,
  );

  const StoreScreenshotDevice({
    required this.fileNamePrefix,
    required this.pixelSize,
    required this.devicePixelRatio,
    required this.safeAreaPadding,
    required this.isTablet,
  });

  /// 書き出すファイルの名前の先頭。
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
}

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
    final viewfinderPhoto = storeScreenshotViewfinderPhoto();
    CameraPlatform.instance = StoreScreenshotCameraPlatform(
      viewfinderPhoto: viewfinderPhoto,
    );
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
}

/// 1 枚を描いて fastlane/screenshots/<locale>/<端末>_<番号>_<ページ>.png に書き出す。
Future<void> _writeScreenshot({
  required WidgetTester tester,
  required SampleData sampleData,
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
  // 共有のカードは切り出した絵をデコード済みの画像で受け取る
  final shareMonster = monsters[1];
  final shareArtImage = page == StoreScreenshotPage.share
      ? await tester.runAsync(
          () async => decodeImageFromList(
            (await loadStoreScreenshotStorageImage(
              storagePath: shareMonster.artPath!,
            ))!,
          ),
        )
      : null;
  const canvasKey = Key('store-screenshot-canvas');
  await tester.pumpWidget(
    _StoreScreenshotCanvas(
      key: canvasKey,
      language: language,
      device: device,
      page: page,
      content: switch (page) {
        StoreScreenshotPage.capture => _homeShell(
          sampleData: sampleData,
          dexStore: dexStore,
          initialTab: HomeTab.capture,
        ),
        StoreScreenshotPage.born => ResultScreen(
          monster: monsters.first,
          dexStore: dexStore,
          origin: ResultScreenOrigin.newlyBorn,
          cardSharer: _cardSharer(),
        ),
        StoreScreenshotPage.dex => _homeShell(
          sampleData: sampleData,
          dexStore: dexStore,
          initialTab: HomeTab.dex,
        ),
        StoreScreenshotPage.battle => BattleScreen(
          playerParty: monsters.take(3).toList(),
          opponentParty: [
            for (final monsterId in [
              'sample-keybon',
              'sample-ringora',
              'sample-noton',
            ])
              _withLevel(
                monster: sampleData.monsterById(monsterId: monsterId),
                level: 10,
              ),
          ],
          opponentKind: BattleOpponentKind.pvp,
          definitions: sampleData.definitions,
          // 生成し直しても同じ場面になるよう、乱数の seed を固定する
          randomSeed: 7,
          battleRecorder: fakeBattleRecorder(
            calls: RecordedBattleCalls(),
            startBattleRecord: () async => null,
            recordedLevels: const {},
          ),
          onPlayerLevelsChanged: ({required levelsByMonsterId}) {},
          cardSharer: _cardSharer(),
          firstBattleBornMonster: null,
          firstBattleMonsterIsNewlyBorn: false,
          opponentSafetyMenu: null,
        ),
        StoreScreenshotPage.opponent => _homeShell(
          sampleData: sampleData,
          dexStore: dexStore,
          initialTab: HomeTab.opponent,
        ),
        StoreScreenshotPage.share => MonsterShareCard(
          monster: shareMonster,
          artImagesByPath: {shareMonster.artPath!: shareArtImage!},
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
  final pngBytes = await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(canvasKey),
    );
    final capturedImage = await boundary.toImage(
      pixelRatio: device.devicePixelRatio,
    );
    final rgbaBytes = await capturedImage.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final png = image_codec.encodePng(
      // App Store のスクリーンショットは透明を含めない (アルファの無い RGB にする)
      image_codec.Image.fromBytes(
        width: capturedImage.width,
        height: capturedImage.height,
        bytes: rgbaBytes!.buffer,
        numChannels: 4,
        order: image_codec.ChannelOrder.rgba,
      ).convert(numChannels: 3),
    );
    capturedImage.dispose();
    return png;
  });
  File(
      'fastlane/screenshots/${language.fastlaneLocale}/'
      '${device.fileNamePrefix}_${(page.index + 1).toString().padLeft(2, '0')}_${page.name}.png',
    )
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(pngBytes!);
  // 次の 1 枚の前に、この画面 (カメラ・バトルの演出) を閉じてから、共有のカードに渡した画像を手放す
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  shareArtImage?.dispose();
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
      definitionIds: monster.definitionIds,
    );

/// 共有の操作をしない画面に渡す [CardSharer]。
CardSharer _cardSharer() => fakeCardSharer(
  calls: RecordedShareCalls(),
  artImage: null,
  shareResultStatus: ShareResultStatus.dismissed,
);

/// ログイン済みで、図鑑・撮る・対戦のタブを持つ画面。対戦の相手と戦績は見本を返す。
Widget _homeShell({
  required SampleData sampleData,
  required DexStore dexStore,
  required HomeTab initialTab,
}) {
  final sessionStore = SessionStore(
    startSession: () async => 'store-screenshot-uid',
    endSession: () async {},
    resumedUid: 'store-screenshot-uid',
  );
  final PvpClient pvpClient = fakePvpClient(
    calls: RecordedPvpCalls(),
    fetchOpponents: () async =>
        storeScreenshotOpponents(sampleData: sampleData),
    extraDefinitions: null,
    battleRecord: (wins: 14, losses: 6),
    displayName: 'snap',
    reportMonster: () async {},
    blockUser: () async {},
    updateDisplayName: ({required displayName}) async => displayName,
  );
  return HomeShell(
    initialTab: initialTab,
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
      pickAlbumPhoto: () async => null,
      preparePhoto: ({required sourceBytes}) async => sourceBytes,
      createRequestId: () => 'store-screenshot-request',
      uploadPhoto: ({required requestId, required photo}) async {},
      requestGeneration: ({required requestId, required onCompletedStage}) =>
          throw StateError('スクリーンショットでは生成しない'),
      fetchGeneration: ({required requestId}) =>
          throw StateError('スクリーンショットでは生成しない'),
      logEvent: ({required event, required parameters}) async {},
    ),
    pvpClient: pvpClient,
    cardSharer: _cardSharer(),
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
  });

  final StoreScreenshotLanguage language;
  final StoreScreenshotDevice device;
  final StoreScreenshotPage page;

  /// 端末の枠 (共有のページはカードの枠) の中に描く画面。
  final Widget content;

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
                      : _DeviceFrame(device: device, screen: content),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// アプリの画面を端末の論理の大きさで描き、角の丸い端末の枠に収める。枠は余りの高さに収まる大きさにする。
class _DeviceFrame extends StatelessWidget {
  const _DeviceFrame({required this.device, required this.screen});

  final StoreScreenshotDevice device;
  final Widget screen;

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
    );
  }
}

/// 共有するカード (縦長 1080×1920 の論理の大きさ) を、角を丸めて余りの高さに収める。
class _ShareCardFrame extends StatelessWidget {
  const _ShareCardFrame({required this.card, required this.scale});

  final Widget card;
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
