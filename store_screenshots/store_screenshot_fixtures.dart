import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:snapmon/domain/monster/monster_definition.dart';
import 'package:snapmon/domain/monster/monster_stats.dart';
import 'package:snapmon/features/dex/owned_monster.dart';
import 'package:snapmon/features/opponent/pvp_opponent.dart';
import 'package:snapmon/sample/sample_data.dart';

// App Store のスクリーンショットに出すモンスター・対戦相手・写真と、それを Firebase と端末の機能を通さずに画面へ渡す部品。
// 名前・図鑑の文章・属性・技は本番の生成と同じく日本語のまま (生成の文章は日本語だけで作るため、英語のスクリーンショットでも同じものが出る)。

/// 本番の生成と同じ切り出しで作ったモンスターの絵 (functions/scripts/cutout-store-screenshot-photos.mjs が書き出す)。
const String _cutoutDirectory = 'store_screenshots/fixtures/cutouts';

/// 絵の元の写真 (CC0 / Public domain。出典は同ディレクトリの LICENSES.md)。
const String _photoDirectory = 'functions/test/fixtures/calibration/photos';

/// スクリーンショットのモンスターの写真と絵の Storage のパスから、手元のファイルのパスを引く表。
final Map<String, String> _filePathsByStoragePath = {
  for (final (name, photoFileName) in _photoFileNames)
    ...{
      _artPath(name: name): '$_cutoutDirectory/$name.png',
      _photoPath(name: name): '$_photoDirectory/$photoFileName',
    },
};

/// 絵の名前と元の写真のファイル名 (cutout-store-screenshot-photos.mjs の PHOTOS と同じ組)。
const List<(String, String)> _photoFileNames = [
  ('mug', '01.jpg'),
  ('scissors', '15.jpg'),
  ('cactus', '04.jpg'),
  ('rubber_duck', '08.jpg'),
  ('kettle', '11.jpg'),
  ('candle', '18.jpg'),
];

String _artPath({required String name}) =>
    'monsters/store-screenshot-$name/art.png';

String _photoPath({required String name}) =>
    'users/store-screenshot/photos/$name';

/// StorageImage の読み込み (StorageImageLoaderScope) の代わりに、スクリーンショットの写真と絵を手元のファイルから読む。
Future<Uint8List?> loadStoreScreenshotStorageImage({
  required String storagePath,
}) async => File(
  _filePathsByStoragePath[storagePath] ??
      (throw StateError('$storagePath の画像はスクリーンショットに用意していない')),
).readAsBytesSync();

/// 撮る画面のファインダーに映す写真 (生まれた画面のマグカップと同じ写真)。
Uint8List storeScreenshotViewfinderPhoto() =>
    File('$_photoDirectory/01.jpg').readAsBytesSync();

/// スクリーンショットの図鑑のモンスター。先頭の 3 体が手持ち。
/// 名前・図鑑の文章・技は、本番の生成の形 (名前はカタカナ、図鑑の文章は日本語で 2 文) に合わせて書いた見本。
List<OwnedMonster> storeScreenshotMonsters() => [
  _monster(
    name: 'mug',
    monsterName: 'マグモン',
    encyclopediaText: '朝いちばんのコーヒーの熱を体にためこむ。取っ手を振り回して戦うが、中身をこぼすと急に弱気になる。',
    elementTypeIds: const ['heat', 'metal'],
    level: 12,
    baseStats: const MonsterStats(
      hitPoints: 80,
      attack: 100,
      defense: 100,
      speed: 60,
    ),
  ),
  _monster(
    name: 'rubber_duck',
    monsterName: 'プカプック',
    encyclopediaText: 'お風呂に浮かんで水面を見張っている。押されると高い声で鳴いて仲間を呼ぶ。',
    elementTypeIds: const ['plastic', 'water'],
    level: 9,
    baseStats: const MonsterStats(
      hitPoints: 90,
      attack: 70,
      defense: 80,
      speed: 100,
    ),
  ),
  _monster(
    name: 'cactus',
    monsterName: 'トゲボウ',
    encyclopediaText: '日なたでじっと動かず、トゲの先に光をためる。水をもらうと少しだけ背がのびる。',
    elementTypeIds: const ['plant'],
    level: 7,
    baseStats: const MonsterStats(
      hitPoints: 110,
      attack: 90,
      defense: 110,
      speed: 30,
    ),
  ),
  _monster(
    name: 'scissors',
    monsterName: 'チョッキン',
    encyclopediaText: '2 本の刃を交差させて、目の前の物を何でも切ろうとする。持ち手の輪に指を入れられると、おとなしくなる。',
    elementTypeIds: const ['metal', 'plastic'],
    level: 5,
    baseStats: const MonsterStats(
      hitPoints: 70,
      attack: 90,
      defense: 80,
      speed: 120,
    ),
  ),
  _monster(
    name: 'kettle',
    monsterName: 'ハーブポット',
    encyclopediaText: '体の中でハーブを育てている。湯気といっしょに香りを広げて、相手の気持ちを落ちつかせる。',
    elementTypeIds: const ['metal', 'plant'],
    level: 4,
    baseStats: const MonsterStats(
      hitPoints: 100,
      attack: 70,
      defense: 100,
      speed: 50,
    ),
  ),
  _monster(
    name: 'candle',
    monsterName: 'ロウソクン',
    encyclopediaText: '頭の火がゆれていると機嫌がいい。風の強い日はじっと動かず、火を守っている。',
    elementTypeIds: const ['heat'],
    level: 3,
    baseStats: const MonsterStats(
      hitPoints: 60,
      attack: 110,
      defense: 60,
      speed: 90,
    ),
  ),
];

/// スクリーンショットのモンスター 1 体。技は属性ごとに見本の定義 (assets/samples/sample_monsters.json) の技を覚える。
OwnedMonster _monster({
  required String name,
  required String monsterName,
  required String encyclopediaText,
  required List<String> elementTypeIds,
  required int level,
  required MonsterStats baseStats,
}) => OwnedMonster(
  definition: MonsterDefinition(
    id: 'store-screenshot-$name',
    sourcePhotoReference: _photoPath(name: name),
    name: monsterName,
    encyclopediaText: encyclopediaText,
    elementTypeIds: elementTypeIds,
    learnset: [
      for (final elementTypeId in elementTypeIds) ...[
        LearnsetEntry(moveId: '${elementTypeId}_1', unlockLevel: 1),
        LearnsetEntry(moveId: '${elementTypeId}_2', unlockLevel: 5),
      ],
    ],
    baseStats: baseStats,
    individualValues: const MonsterStats(
      hitPoints: 18,
      attack: 24,
      defense: 12,
      speed: 20,
    ),
    statCalculationVersion: 1,
    masterVersion: 1,
  ),
  level: level,
  artPath: _artPath(name: name),
  definitionIds: const [],
);

/// 対戦の画面に出す他のトレーナー。モンスターは見本のモンスター (名前だけを出す) を使う。
List<PvpOpponent> storeScreenshotOpponents({required SampleData sampleData}) =>
    [
      PvpOpponent(
        opponentUid: 'store-screenshot-trainer-1',
        displayName: 'ゆうき',
        monsters: [
          for (final monsterId in [
            'sample-slippan',
            'sample-noton',
            'sample-ringora',
          ])
            sampleData.monsterById(monsterId: monsterId),
        ],
      ),
      PvpOpponent(
        opponentUid: 'store-screenshot-trainer-2',
        displayName: 'トレーナー 0417',
        monsters: [
          for (final monsterId in [
            'sample-petbottler',
            'sample-keybon',
            'sample-mugmon',
          ])
            sampleData.monsterById(monsterId: monsterId),
        ],
      ),
    ];

/// 撮る画面のカメラ。ファインダーに [viewfinderPhoto] を映す (widget test にはカメラが無いため、camera の端末側の実装を差し替える)。
/// CameraController の initialize・dispose と CameraPreview が呼ぶ分だけを実装する (camera 0.12.0+2 の camera_controller.dart)。
class StoreScreenshotCameraPlatform extends CameraPlatform {
  /// [viewfinderPhoto] を映すカメラを作る。
  StoreScreenshotCameraPlatform({required this.viewfinderPhoto});

  /// ファインダーに映す写真。
  final Uint8List viewfinderPhoto;

  /// 撮る画面が開くカメラ (背面)。
  static const CameraDescription backCamera = CameraDescription(
    name: 'store-screenshot-back',
    lensDirection: CameraLensDirection.back,
    sensorOrientation: 90,
  );

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    backCamera,
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async => 1;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}

  // 端末のカメラの 16:9 のプレビュー (横長のセンサーの幅 / 高さ)
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1920,
          1080,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  // エラーも端末の向きの変化も起きない (first で待たれても終わらないよう、閉じないストリームにする)
  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      StreamController<DeviceOrientationChangedEvent>().stream;

  // マグカップは写真の右寄りに写っているため、縦長のファインダーで切れないよう右に寄せて切り取る
  @override
  Widget buildPreview(int cameraId) => Image.memory(
    viewfinderPhoto,
    fit: BoxFit.cover,
    alignment: const Alignment(0.6, 0),
  );

  @override
  Future<void> dispose(int cameraId) async {}
}

/// アプリに同梱したフォントとアイコンのフォント (FontManifest.json の全部) を読み込む。
/// widget test の既定のフォントは文字を四角で描くため、スクリーンショットの前に本物のフォントを読む。
Future<void> loadStoreScreenshotFonts() async {
  final fontManifest =
      jsonDecode(await rootBundle.loadString('FontManifest.json'))
          as List<dynamic>;
  for (final fontFamily in fontManifest.cast<Map<String, dynamic>>()) {
    final fontLoader = FontLoader(fontFamily['family'] as String);
    for (final font
        in (fontFamily['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      fontLoader.addFont(rootBundle.load(font['asset'] as String));
    }
    await fontLoader.load();
  }
}
