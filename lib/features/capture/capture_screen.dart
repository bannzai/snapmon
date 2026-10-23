import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../sample/sample_data.dart';
import '../../theme/snapmon_colors.dart';
import '../../theme/snapmon_radii.dart';
import '../../theme/snapmon_text_styles.dart';
import '../../widgets/square_icon_button.dart';
import '../battle/battle_recorder.dart';
import '../dex/dex_store.dart';
import '../home/home_shell.dart';
import '../opponent/pvp_client.dart';
import '../result/result_screen.dart';
import '../share/card_sharer.dart';
import 'generation_screen.dart';
import 'monster_generator.dart';

/// 撮る画面 (モックの Main.dc.html)。ファインダーにカメラの映像を出し、シャッターで撮るかアルバムから選んだ写真から生成する。
/// カメラが無い端末 (Simulator) と使えない時は、ファインダーにそのことを出してアルバムから選ぶ経路だけを残す。
class CaptureScreen extends StatefulWidget {
  /// 撮る画面を作る。
  const CaptureScreen({
    super.key,
    required this.dexStore,
    required this.monsterGenerator,
    required this.onSelectTab,
    required this.onOpenSettings,
    required this.cardSharer,
    required this.sampleData,
    required this.pvpClient,
    required this.battleRecorder,
  });

  /// 見本データ (手持ちが空の時の初回のバトルの CPU トレーナー)。
  final SampleData sampleData;

  /// 手持ちが空の時の初回のバトルの相手の取得。
  final PvpClient pvpClient;

  /// 手持ちが空の時の初回のバトルの記録と計測。
  final BattleRecorder battleRecorder;

  /// 図鑑と手持ち。
  final DexStore dexStore;

  /// 生成の呼び出しと計測。
  final MonsterGenerator monsterGenerator;

  /// 下タブを切り替える。
  final void Function({required HomeTab tab}) onSelectTab;

  /// 設定画面を開く。
  final VoidCallback onOpenSettings;

  /// 生まれた画面からの図鑑のカードの共有に使う関数の組。
  final CardSharer cardSharer;

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  Object? _cameraError;
  bool _isTakingPicture = false;

  /// カメラを開く試みの番号。開いている途中にアプリが裏に回る・開き直すと進み、古い試みの結果を捨てる目印にする。
  int _cameraStartGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    super.dispose();
  }

  // アプリが裏に回る間はカメラを離し、戻ったら開き直す (camera パッケージの README の扱い)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // 開いている途中の試みも、裏に回った後に開き終えたカメラを持たないよう無効にする
        _cameraStartGeneration++;
        final cameraController = _cameraController;
        setState(() => _cameraController = null);
        cameraController?.dispose();
      case AppLifecycleState.resumed:
        if (_cameraController == null) {
          _startCamera();
        }
      case AppLifecycleState.detached ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        break;
    }
  }

  /// 背面のカメラ (無ければ最初のカメラ) を開く。カメラが無い・開けない時は [_cameraError] に残す。
  /// 開き終える前に次の試みが始まった・アプリが裏に回った時は、開いたカメラを捨てて結果を反映しない。
  Future<void> _startCamera() async {
    final generation = ++_cameraStartGeneration;
    bool isCurrent() => mounted && generation == _cameraStartGeneration;
    try {
      final cameras = await widget.monsterGenerator.listCameras();
      if (cameras.isEmpty) {
        throw StateError('カメラが見つかりません');
      }
      final cameraController = CameraController(
        cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        ),
        // 生成に送る写真は長辺 1024px に縮めるため (photo_preparation.dart)、それを下回らない解像度にした
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      try {
        await cameraController.initialize();
      } catch (_) {
        // 開けなかったカメラも、開く途中で始めた端末の向きの購読等を残さないよう捨てる
        await cameraController.dispose();
        rethrow;
      }
      if (!isCurrent()) {
        await cameraController.dispose();
        return;
      }
      final previousCameraController = _cameraController;
      setState(() {
        _cameraController = cameraController;
        _cameraError = null;
      });
      await previousCameraController?.dispose();
    } catch (error) {
      if (isCurrent()) {
        setState(() => _cameraError = error);
      }
    }
  }

  /// カメラで撮って生成する。
  Future<void> _takePicture() async {
    final cameraController = _cameraController;
    if (_isTakingPicture) {
      return;
    }
    if (cameraController == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('カメラが使えません\nアルバムから選んでください')),
        );
      return;
    }
    setState(() => _isTakingPicture = true);
    try {
      final picture = await cameraController.takePicture();
      await _generate(
        sourcePhoto: await picture.readAsBytes(),
        photoSource: GenerationPhotoSource.camera,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _isTakingPicture = false);
      }
    }
  }

  /// アルバムから選んで生成する。選ばずに閉じた時は何もしない。
  Future<void> _pickAlbumPhoto() async {
    try {
      final photo = await widget.monsterGenerator.pickAlbumPhoto();
      if (photo != null) {
        await _generate(
          sourcePhoto: photo,
          photoSource: GenerationPhotoSource.album,
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _generate({
    required Uint8List sourcePhoto,
    required GenerationPhotoSource photoSource,
  }) async {
    if (!mounted) {
      return;
    }
    final action = await Navigator.of(context).push(
      MaterialPageRoute<ResultScreenAction>(
        builder: (context) => GenerationScreen(
          sourcePhoto: sourcePhoto,
          photoSource: photoSource,
          monsterGenerator: widget.monsterGenerator,
          dexStore: widget.dexStore,
          cardSharer: widget.cardSharer,
          startsFirstBattle: widget.dexStore.party.isEmpty,
          sampleData: widget.sampleData,
          pvpClient: widget.pvpClient,
          battleRecorder: widget.battleRecorder,
        ),
      ),
    );
    if (action == ResultScreenAction.openDex) {
      widget.onSelectTab(tab: HomeTab.dex);
    }
  }

  // 高さが足りない画面 (横向き・低い Web のウィンドウ) では全体をスクロールし、撮る操作に必ず届くようにする。
  // 足りる時はファインダーが残りの高さを埋める
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(child: _buildContent(context: context)),
      ),
    ),
  );

  Widget _buildContent({required BuildContext context}) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
        child: Row(
          children: [
            // 端末の文字を大きくした時は、右のボタンを押し出さないようロゴの方を縮める
            const Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('snapmon', style: SnapmonTextStyles.logo),
                ),
              ),
            ),
            ListenableBuilder(
              listenable: widget.dexStore,
              builder: (context, _) => Material(
                color: SnapmonColors.surface,
                borderRadius: SnapmonRadii.button,
                child: InkWell(
                  borderRadius: SnapmonRadii.button,
                  onTap: () => widget.onSelectTab(tab: HomeTab.dex),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.grid_view_rounded,
                          color: SnapmonColors.accent,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '図鑑 ${widget.dexStore.monsters.length}',
                          style: SnapmonTextStyles.label,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SquareIconButton(
              icon: Icons.settings_outlined,
              tooltip: '設定',
              onPressed: widget.onOpenSettings,
              size: 44,
            ),
          ],
        ),
      ),
      // 手持ちが空の (初回の) 人に、最初の操作を 1 行で示す。撮った後はそのまま戦う導線になる
      ListenableBuilder(
        listenable: widget.dexStore,
        builder: (context, _) => widget.dexStore.party.isEmpty
            ? Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  _cameraController == null
                      ? '身の回りの物の写真を 1 枚選ぼう'
                      : '身の回りの物を 1 つ撮ろう',
                  key: const Key('capture-first-hint'),
                  textAlign: TextAlign.center,
                  style: SnapmonTextStyles.label.copyWith(
                    color: SnapmonColors.accent,
                  ),
                ),
              )
            : const SizedBox.shrink(),
      ),
      Expanded(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: _minimumViewfinderHeight,
          ),
          child: _Viewfinder(
            cameraController: _cameraController,
            cameraError: _cameraError,
          ),
        ),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 0),
        child: Text(
          '身の回りの物を撮る\nモンスターが生まれる',
          textAlign: TextAlign.center,
          style: SnapmonTextStyles.hero,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SquareIconButton(
              icon: Icons.photo_library_outlined,
              tooltip: 'アルバムから選ぶ',
              onPressed: _pickAlbumPhoto,
              size: 56,
            ),
            const SizedBox(width: 28),
            Tooltip(
              message: '撮る',
              child: Material(
                color: _cameraController == null
                    ? SnapmonColors.surfaceRaised
                    : SnapmonColors.accent,
                shape: const CircleBorder(
                  side: BorderSide(color: SnapmonColors.background, width: 6),
                ),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: _takePicture,
                  child: SizedBox.square(
                    dimension: 84,
                    child: Icon(
                      Icons.photo_camera_outlined,
                      color: _cameraController == null
                          ? SnapmonColors.textMuted
                          : SnapmonColors.textOnCard,
                      size: 34,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 28),
            SquareIconButton(
              icon: Icons.sports_martial_arts,
              tooltip: '対戦する',
              onPressed: () => widget.onSelectTab(tab: HomeTab.opponent),
              size: 56,
            ),
          ],
        ),
      ),
    ],
  );
}

/// 高さが足りない画面でのファインダーの高さ。四隅の鉤形 (36 + 余白 24) 2 つと案内の札が重ならない高さにした。
const double _minimumViewfinderHeight = 200;

/// ファインダー。カメラの映像の上に枠と案内を重ねる。カメラが使えない時は、映像の代わりにその理由を出す。
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.cameraController,
    required this.cameraError,
  });

  /// 開いたカメラ。開くまでと使えない時は null。
  final CameraController? cameraController;

  /// カメラを開けなかった理由。開けた時と開いている途中は null。
  final Object? cameraError;

  @override
  Widget build(BuildContext context) {
    final openedCameraController = cameraController;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: SnapmonRadii.panel,
        child: ColoredBox(
          color: SnapmonColors.surfaceRaised,
          child: Stack(
            children: [
              if (openedCameraController != null)
                // 枠いっぱいに映像を広げ、はみ出た分は切る (撮れる範囲は映像の全体)。
                // aspectRatio はセンサーの向き (横長) の幅 / 高さで、縦持ちの映像は高さ / 幅がこの値になる
                Positioned.fill(
                  child: FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: 1,
                      height: openedCameraController.value.aspectRatio,
                      child: CameraPreview(openedCameraController),
                    ),
                  ),
                ),
              if (cameraError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      'カメラが使えません\nアルバムから選んでください\n\n$cameraError',
                      textAlign: TextAlign.center,
                      style: SnapmonTextStyles.small,
                    ),
                  ),
                ),
              for (final alignment in [
                Alignment.topLeft,
                Alignment.topRight,
                Alignment.bottomLeft,
                Alignment.bottomRight,
              ])
                Align(
                  alignment: alignment,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _ViewfinderCorner(alignment: alignment),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: SnapmonColors.scrim,
                      borderRadius: SnapmonRadii.button,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text('被写体を枠に入れる', style: SnapmonTextStyles.body),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ファインダーの四隅の鉤形。
class _ViewfinderCorner extends StatelessWidget {
  const _ViewfinderCorner({required this.alignment});

  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Transform.scale(
    // 左上の鉤形を描き、他の隅は左右・上下に反転して描く
    scaleX: alignment.x < 0 ? 1 : -1,
    scaleY: alignment.y < 0 ? 1 : -1,
    child: const CustomPaint(
      size: Size.square(36),
      painter: _ViewfinderCornerPainter(),
    ),
  );
}

class _ViewfinderCornerPainter extends CustomPainter {
  const _ViewfinderCornerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const strokeWidth = 4.0;
    const cornerRadius = 10.0;
    const inset = strokeWidth / 2;
    canvas.drawPath(
      Path()
        ..moveTo(inset, size.height)
        ..lineTo(inset, inset + cornerRadius)
        ..arcToPoint(
          const Offset(inset + cornerRadius, inset),
          radius: const Radius.circular(cornerRadius),
        )
        ..lineTo(size.width, inset),
      Paint()
        ..color = SnapmonColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderCornerPainter oldDelegate) => false;
}
