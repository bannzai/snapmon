import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../analytics/analytics_events.dart';
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
import '../settings/settings_screen.dart';
import '../share/card_sharer.dart';
import 'generation_screen.dart';
import 'monster_generator.dart';

/// 撮る画面 (モックの Main.dc.html)。ファインダーにカメラの映像を出し、シャッターで撮るかアルバムから選んだ写真から生成する。
/// カメラの権限は、撮るボタンか「カメラを使う」を押すまで求めない (開いただけで権限を聞かないため。#64)。
/// 権限が無い時は、ファインダーに設定を開く・もう一度試す導線を出す。
/// カメラが無い端末 (Simulator) と使えない時は、ファインダーにそのことを出してアルバムから選ぶ経路だけを残す。
class CaptureScreen extends StatefulWidget {
  /// 撮る画面を作る。
  const CaptureScreen({
    super.key,
    required this.startsCameraOnOpen,
    required this.onCameraOpened,
    required this.dexStore,
    required this.monsterGenerator,
    required this.onSelectTab,
    required this.onOpenSettings,
    required this.cardSharer,
    required this.sampleData,
    required this.pvpClient,
    required this.battleRecorder,
    required this.openUrl,
  });

  /// 画面を開いた時に、押すのを待たずにカメラを開くか (このアプリを起動してから一度カメラを開けた後と、
  /// タイトルの「カメラで撮ってはじめる」から来た時)。
  final bool startsCameraOnOpen;

  /// カメラを開けた時に呼ぶ (次に画面を開いた時に [startsCameraOnOpen] にするため)。
  final VoidCallback onCameraOpened;

  /// 手持ちが空の時の初回のバトルの相手を通報する時に、お問い合わせを開く。
  final OpenUrl openUrl;

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

  /// この画面でカメラを求めたか。求める前は、アプリが前に戻ってもカメラを開かない (権限をいきなり聞かないため)。
  late bool _isCameraRequested = widget.startsCameraOnOpen;

  /// カメラを開く試みが走っているか。走っている間は新しい試みを始めない (権限の要求を重ねないため)。
  bool _isStartingCamera = false;

  /// 権限が無い時に「設定を開く」を押したか。押した後にアプリが前に戻った時だけ、権限が無かったカメラを開き直す。
  bool _hasOpenedAppSettings = false;

  /// 次に結果が出た試みの許可・拒否を計測に送るか。カメラを求めた時と設定を開いた時に立て、結果を送ったら下ろす。
  bool _logsCameraPermissionOutcome = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isCameraRequested) {
      _startCamera();
    }
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
        // 開いている途中の試みは止めない。iOS・Android の権限のダイアログもアプリを inactive にするため、
        // 止めるとダイアログの答えを受け取れず、戻るたびに権限を聞き直すことになる
        final cameraController = _cameraController;
        if (cameraController != null) {
          setState(() => _cameraController = null);
          cameraController.dispose();
        }
      case AppLifecycleState.resumed:
        if (!_isCameraRequested ||
            _cameraController != null ||
            _isStartingCamera) {
          return;
        }
        // 権限が無かった後は、設定を開いて戻った時だけ開き直す (Android は拒否の後にもう一度ダイアログを出せるため、
        // 戻るたびに開き直すと聞き続けることになる)。Web は設定を開くボタンが無く、拒否済みの時は聞かずに失敗するため開き直す
        if (_isCameraAccessDenied(error: _cameraError) &&
            !_hasOpenedAppSettings &&
            !kIsWeb) {
          return;
        }
        setState(() => _hasOpenedAppSettings = false);
        _startCamera();
      case AppLifecycleState.detached ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        break;
    }
  }

  /// 背面のカメラ (無ければ最初のカメラ) を開く。カメラが無い・開けない時は [_cameraError] に残す。
  /// 開き終えた時にアプリが前に出ていなければ (権限のダイアログの間に許可された時)、カメラを持たずに捨て、
  /// 前に戻った時 (resumed) に開き直す。
  Future<void> _startCamera() async {
    _isStartingCamera = true;
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
      if (!mounted) {
        await cameraController.dispose();
        return;
      }
      if (_logsCameraPermissionOutcome) {
        _logCameraPermission(step: CameraPermissionStep.granted);
        _logsCameraPermissionOutcome = false;
      }
      widget.onCameraOpened();
      // テストの環境では lifecycleState が null のことがあり、その時は前に出ているものとして扱う
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      final isInForeground =
          lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
      setState(() {
        _isStartingCamera = false;
        _cameraError = null;
        if (isInForeground) {
          _cameraController = cameraController;
        }
      });
      if (!isInForeground) {
        await cameraController.dispose();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (_logsCameraPermissionOutcome) {
        if (_isCameraAccessDenied(error: error)) {
          _logCameraPermission(step: CameraPermissionStep.denied);
        }
        _logsCameraPermissionOutcome = false;
      }
      setState(() {
        _isStartingCamera = false;
        _cameraError = error;
      });
    }
  }

  /// 押されてカメラを求める (権限を聞くのはここから)。開いている途中は何もしない (連打で要求を重ねないため)。
  void _requestCamera() {
    if (_isStartingCamera) {
      return;
    }
    _logCameraPermission(step: CameraPermissionStep.requested);
    _logsCameraPermissionOutcome = true;
    setState(() {
      _isCameraRequested = true;
      _cameraError = null;
    });
    _startCamera();
  }

  /// 権限が無い時に、OS の設定アプリでこのアプリの設定を開く。戻った時は resumed で開き直す。
  Future<void> _openAppSettings() async {
    _logCameraPermission(step: CameraPermissionStep.openSettings);
    _logsCameraPermissionOutcome = true;
    _hasOpenedAppSettings = true;
    try {
      await widget.monsterGenerator.openAppSettings();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  /// カメラの権限の段階 [step] を送る。計測の失敗は画面の進み方に影響させない。
  void _logCameraPermission({required CameraPermissionStep step}) => unawaited(
    widget.monsterGenerator
        .logEvent(
          event: AnalyticsEvent.cameraPermission,
          parameters: {'step': step.stepName},
        )
        .catchError((Object _) {}),
  );

  /// カメラで撮って生成する。カメラを開いていない時は、撮る代わりにカメラを求める。
  Future<void> _takePicture() async {
    final cameraController = _cameraController;
    if (_isTakingPicture) {
      return;
    }
    if (cameraController == null) {
      _requestCamera();
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
          cropsWhenSubjectNotFound: true,
          monsterGenerator: widget.monsterGenerator,
          dexStore: widget.dexStore,
          cardSharer: widget.cardSharer,
          startsFirstBattle: widget.dexStore.party.isEmpty,
          sampleData: widget.sampleData,
          pvpClient: widget.pvpClient,
          battleRecorder: widget.battleRecorder,
          openUrl: widget.openUrl,
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
            isCameraRequested: _isCameraRequested,
            onRequestCamera: _requestCamera,
            onOpenAppSettings: _openAppSettings,
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

/// [error] がカメラの権限が無いことを表すか (利用者が設定で直せる時だけ。直せない時は他のエラーと同じく生の文言を出す)。
/// コードは camera_avfoundation の CameraPermissionManager.swift (iOS の初回の拒否は `CameraAccessDenied`、
/// 拒否済みは `CameraAccessDeniedWithoutPrompt`)、camera_android_camerax の CameraPermissionsManager.java と
/// camera_web の CameraErrorCode.permissionDenied (どちらも `CameraAccessDenied`) による。
/// iOS の `CameraAccessRestricted` (スクリーンタイム等の制限) は本人が設定で直せるとは限らないため含めない。
bool _isCameraAccessDenied({required Object? error}) =>
    error is CameraException &&
    (error.code == 'CameraAccessDenied' ||
        error.code == 'CameraAccessDeniedWithoutPrompt');

/// ファインダーの上に重ねるボタンの形。テーマの FilledButton は横幅いっぱい (`Size.fromHeight(56)`) で、
/// ファインダーの枠を横切る帯になり「設定を開く」と「もう一度試す」も横に並ばないため、文言の幅に縮める。
/// 高さ 48 は Material の最小のタップ領域。
final ButtonStyle _viewfinderFilledButtonStyle = FilledButton.styleFrom(
  minimumSize: const Size(0, 48),
);

/// 高さが足りない画面でのファインダーの高さ。四隅の鉤形 (36 + 余白 24) 2 つと案内の札が重ならない高さにした。
const double _minimumViewfinderHeight = 200;

/// ファインダー。カメラの映像の上に枠と案内を重ねる。カメラを求める前は「カメラを使う」を、
/// 権限が無い時は設定を開く・もう一度試す導線を、それ以外で使えない時は映像の代わりにその理由を出す。
class _Viewfinder extends StatelessWidget {
  const _Viewfinder({
    required this.cameraController,
    required this.cameraError,
    required this.isCameraRequested,
    required this.onRequestCamera,
    required this.onOpenAppSettings,
  });

  /// 開いたカメラ。開くまでと使えない時は null。
  final CameraController? cameraController;

  /// カメラを開けなかった理由。開けた時と開いている途中は null。
  final Object? cameraError;

  /// カメラを求めたか。求める前は「カメラを使う」を出す。
  final bool isCameraRequested;

  /// カメラを求める (「カメラを使う」と「もう一度試す」)。
  final VoidCallback onRequestCamera;

  /// OS の設定アプリでこのアプリの設定を開く (iOS・Android の「設定を開く」)。
  final VoidCallback onOpenAppSettings;

  @override
  Widget build(BuildContext context) {
    final openedCameraController = cameraController;
    final error = cameraError;
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
              if (_isCameraAccessDenied(error: error))
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'カメラの許可が必要です',
                          key: Key('capture-camera-permission-denied'),
                          textAlign: TextAlign.center,
                          style: SnapmonTextStyles.label,
                        ),
                        const SizedBox(height: 4),
                        // Web はアプリから設定を開けないため、ブラウザで許可する場所を案内する
                        Text(
                          kIsWeb
                              ? 'アドレスバーのサイトの設定から\nカメラを許可してください'
                              : '設定でカメラを許可してください',
                          textAlign: TextAlign.center,
                          style: SnapmonTextStyles.small,
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            if (!kIsWeb)
                              FilledButton(
                                style: _viewfinderFilledButtonStyle,
                                onPressed: onOpenAppSettings,
                                child: const Text('設定を開く'),
                              ),
                            OutlinedButton(
                              onPressed: onRequestCamera,
                              child: const Text('もう一度試す'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else if (error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 48),
                    child: Text(
                      'カメラが使えません\nアルバムから選んでください\n\n$error',
                      textAlign: TextAlign.center,
                      style: SnapmonTextStyles.small,
                    ),
                  ),
                )
              else if (!isCameraRequested)
                Center(
                  child: FilledButton.icon(
                    key: const Key('capture-use-camera'),
                    style: _viewfinderFilledButtonStyle,
                    onPressed: onRequestCamera,
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('カメラを使う'),
                  ),
                )
              else if (openedCameraController == null)
                const Center(child: CircularProgressIndicator()),
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
              // 権限が無い時の案内とボタンは、ファインダーが低い時 (最小の高さ) にこの札と重なり、
              // 後から描くこの札がボタンへのタップを受けてしまうため出さない
              if (!_isCameraAccessDenied(error: error))
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
