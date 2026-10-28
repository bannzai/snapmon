import 'dart:async';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/features/capture/capture_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../monster_generator_fixture.dart';
import '../../pvp_client_fixture.dart';
import '../../sample_data_fixture.dart';

/// 端末のカメラの代わり。[initializeCamera] は [initializeError] があればそれを投げ、無ければ開けたことにする。
class _FakeCameraPlatform extends CameraPlatform {
  /// initializeCamera が投げるエラー。null の時は開ける。
  Object? initializeError;

  /// initializeCamera が呼ばれた回数。
  int initializeCallCount = 0;

  @override
  Future<int> createCameraWithSettings(
    CameraDescription cameraDescription,
    MediaSettings mediaSettings,
  ) async => 1;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

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

  @override
  // 空のストリームだと CameraController が `.first` で待つ所で StateError になるため、何も流さず閉じないストリームにする
  Stream<CameraErrorEvent> onCameraError(int cameraId) =>
      StreamController<CameraErrorEvent>().stream;

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    initializeCallCount++;
    final error = initializeError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Widget buildPreview(int cameraId) =>
      const SizedBox.expand(key: Key('fake-camera-preview'));

  @override
  Future<void> dispose(int cameraId) async {}
}

/// テストの端末の背面のカメラ。
const CameraDescription _backCamera = CameraDescription(
  name: 'back',
  lensDirection: CameraLensDirection.back,
  sensorOrientation: 90,
);

/// iOS の初回・Android・Web で権限を拒否した時のエラー (camera_avfoundation・camera_android_camerax・camera_web と同じコード)。
final CameraException _accessDenied = CameraException(
  'CameraAccessDenied',
  'The camera cannot be used or the permission to access the camera is not granted.',
);

void main() {
  late _FakeCameraPlatform cameraPlatform;
  late RecordedGenerationCalls generationCalls;
  late int listCamerasCallCount;
  late int cameraOpenedCallCount;

  setUp(() {
    cameraPlatform = _FakeCameraPlatform();
    CameraPlatform.instance = cameraPlatform;
    generationCalls = RecordedGenerationCalls();
    listCamerasCallCount = 0;
    cameraOpenedCallCount = 0;
  });

  /// 撮る画面を開く。カメラの一覧は [listCameras] が返す。
  Future<void> pumpCaptureScreen({
    required WidgetTester tester,
    required bool startsCameraOnOpen,
    required Future<List<CameraDescription>> Function() listCameras,
  }) async {
    final generator = fakeMonsterGenerator(
      calls: generationCalls,
      albumPhoto: null,
      uploadError: null,
      requestGeneration: ({required requestId}) =>
          throw StateError('requestGeneration は呼ばない'),
      fetchGeneration: ({required requestId}) =>
          throw StateError('fetchGeneration は呼ばない'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: snapmonThemeData(),
        home: Scaffold(
          body: CaptureScreen(
            startsCameraOnOpen: startsCameraOnOpen,
            onCameraOpened: () => cameraOpenedCallCount++,
            dexStore: DexStore(
              definitions: loadSampleDataFixture().definitions,
            ),
            cardSharer: fakeCardSharer(
              calls: RecordedShareCalls(),
              artImage: null,
              shareResultStatus: ShareResultStatus.success,
            ),
            monsterGenerator: MonsterGenerator(
              listCameras: () {
                listCamerasCallCount++;
                return listCameras();
              },
              openAppSettings: generator.openAppSettings,
              pickAlbumPhoto: generator.pickAlbumPhoto,
              preparePhoto: generator.preparePhoto,
              createRequestId: generator.createRequestId,
              uploadPhoto: generator.uploadPhoto,
              requestGeneration: generator.requestGeneration,
              fetchGeneration: generator.fetchGeneration,
              logEvent: generator.logEvent,
            ),
            onSelectTab: ({required tab}) {},
            onOpenSettings: () {},
            sampleData: loadSampleDataFixture(),
            pvpClient: signedOutPvpClient(calls: RecordedPvpCalls()),
            battleRecorder: fakeBattleRecorder(
              calls: RecordedBattleCalls(),
              startBattleRecord: () async => null,
              recordedLevels: const {},
            ),
            openUrl: ({required uri}) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 送ったカメラの権限の段階 (送った順)。
  List<Object?> loggedCameraPermissionSteps() => [
    for (final logged in generationCalls.loggedEvents)
      if (logged.event == AnalyticsEvent.cameraPermission)
        logged.parameters?['step'],
  ];

  /// アプリが裏に回って戻る (OS の設定から戻った時・iOS の権限のダイアログを閉じた時)。
  Future<void> goToBackgroundAndReturn({required WidgetTester tester}) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  testWidgets('開いただけではカメラを求めず、「カメラを使う」を押した時にカメラを開く', (tester) async {
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () async => const [_backCamera],
    );
    expect(listCamerasCallCount, 0);
    expect(cameraPlatform.initializeCallCount, 0);
    expect(find.byKey(const Key('capture-use-camera')), findsOneWidget);

    // 求める前にアプリが裏に回って戻っても、カメラを求めない
    await goToBackgroundAndReturn(tester: tester);
    expect(listCamerasCallCount, 0);
    expect(cameraPlatform.initializeCallCount, 0);

    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pumpAndSettle();
    expect(listCamerasCallCount, 1);
    expect(cameraPlatform.initializeCallCount, 1);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    expect(find.byKey(const Key('capture-use-camera')), findsNothing);
    expect(cameraOpenedCallCount, 1);
    expect(loggedCameraPermissionSteps(), ['requested', 'granted']);
  });

  testWidgets('開いていない時に撮るボタンを押すと、撮らずにカメラを求める', (tester) async {
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () async => const [_backCamera],
    );
    await tester.tap(find.byTooltip('撮る'));
    await tester.pumpAndSettle();
    expect(cameraPlatform.initializeCallCount, 1);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    expect(generationCalls.uploadedRequestIds, isEmpty);
  });

  testWidgets('一度カメラを開けた後 (startsCameraOnOpen) は、開いた時に押すのを待たずにカメラを開く', (
    tester,
  ) async {
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: true,
      listCameras: () async => const [_backCamera],
    );
    expect(listCamerasCallCount, 1);
    expect(cameraPlatform.initializeCallCount, 1);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    // 押して求めていないため、許可・拒否は送らない
    expect(loggedCameraPermissionSteps(), isEmpty);
  });

  testWidgets('権限を拒否すると生の例外ではなく設定を開く・もう一度試すを出し、設定で許可して戻ると開き直す', (tester) async {
    cameraPlatform.initializeError = _accessDenied;
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () async => const [_backCamera],
    );
    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('capture-camera-permission-denied')),
      findsOneWidget,
    );
    expect(find.text('設定でカメラを許可してください'), findsOneWidget);
    expect(find.textContaining('CameraAccessDenied'), findsNothing);
    expect(find.textContaining('CameraException'), findsNothing);
    expect(cameraOpenedCallCount, 0);

    await tester.tap(find.text('設定を開く'));
    await tester.pumpAndSettle();
    expect(generationCalls.openAppSettingsCallCount, 1);

    // 設定で許可して戻る
    cameraPlatform.initializeError = null;
    await goToBackgroundAndReturn(tester: tester);
    expect(cameraPlatform.initializeCallCount, 2);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    expect(
      find.byKey(const Key('capture-camera-permission-denied')),
      findsNothing,
    );
    expect(cameraOpenedCallCount, 1);
    expect(loggedCameraPermissionSteps(), [
      'requested',
      'denied',
      'open_settings',
      'granted',
    ]);
  });

  testWidgets('ファインダーが低い (横向き) 時も、拒否の後は下の札を出さず「もう一度試す」を押せる', (tester) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    cameraPlatform.initializeError = _accessDenied;
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () async => const [_backCamera],
    );
    expect(find.text('被写体を枠に入れる'), findsOneWidget);
    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pumpAndSettle();
    expect(find.text('被写体を枠に入れる'), findsNothing);

    cameraPlatform.initializeError = null;
    await tester.tap(find.text('もう一度試す'));
    await tester.pumpAndSettle();
    expect(cameraPlatform.initializeCallCount, 2);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
  });

  testWidgets('拒否した後に「もう一度試す」を押すと、カメラを求め直す', (tester) async {
    cameraPlatform.initializeError = CameraException(
      'CameraAccessDeniedWithoutPrompt',
      'User has previously denied the camera access request.',
    );
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () async => const [_backCamera],
    );
    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('capture-camera-permission-denied')),
      findsOneWidget,
    );

    cameraPlatform.initializeError = null;
    await tester.tap(find.text('もう一度試す'));
    await tester.pumpAndSettle();
    expect(cameraPlatform.initializeCallCount, 2);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    expect(loggedCameraPermissionSteps(), [
      'requested',
      'denied',
      'requested',
      'granted',
    ]);
  });

  testWidgets('カメラの一覧で権限を拒否された時 (Web) も、設定を開く・もう一度試すを出す', (tester) async {
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () => Future.error(_accessDenied),
    );
    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('capture-camera-permission-denied')),
      findsOneWidget,
    );
    expect(find.text('もう一度試す'), findsOneWidget);
    expect(find.textContaining('CameraAccessDenied'), findsNothing);
  });

  testWidgets('本人が設定で直せるとは限らないエラー (制限) は、今までどおり生の文言を出す', (tester) async {
    cameraPlatform.initializeError = CameraException(
      'CameraAccessRestricted',
      'Camera access is restricted.',
    );
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () async => const [_backCamera],
    );
    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pumpAndSettle();
    expect(find.textContaining('CameraAccessRestricted'), findsOneWidget);
    expect(
      find.byKey(const Key('capture-camera-permission-denied')),
      findsNothing,
    );
    expect(loggedCameraPermissionSteps(), ['requested']);
  });

  testWidgets('権限を拒否した後は、設定を開かずに裏に回って戻っても求め直さない', (tester) async {
    cameraPlatform.initializeError = _accessDenied;
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () async => const [_backCamera],
    );
    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pumpAndSettle();
    await goToBackgroundAndReturn(tester: tester);
    expect(cameraPlatform.initializeCallCount, 1);
    expect(
      find.byKey(const Key('capture-camera-permission-denied')),
      findsOneWidget,
    );
  });

  testWidgets('開いたカメラは裏に回る間に離し、戻ると開き直す', (tester) async {
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () async => const [_backCamera],
    );
    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(find.byKey(const Key('fake-camera-preview')), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(cameraPlatform.initializeCallCount, 2);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
  });

  testWidgets('権限のダイアログの間 (inactive) も試みを止めず、その答えを出す', (tester) async {
    final listCamerasResult = Completer<List<CameraDescription>>();
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () => listCamerasResult.future,
    );
    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pump();
    // 開いている途中の連打では求め直さない
    await tester.tap(find.byTooltip('撮る'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(listCamerasCallCount, 1);

    listCamerasResult.completeError(_accessDenied);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('capture-camera-permission-denied')),
      findsOneWidget,
    );
    expect(loggedCameraPermissionSteps(), ['requested', 'denied']);
  });

  testWidgets('権限のダイアログの間 (inactive) に許可された時は、カメラを持たずに前に戻った時に開き直す', (
    tester,
  ) async {
    final listCamerasResult = Completer<List<CameraDescription>>();
    var listCamerasAttemptCount = 0;
    await pumpCaptureScreen(
      tester: tester,
      startsCameraOnOpen: false,
      listCameras: () {
        listCamerasAttemptCount++;
        return listCamerasAttemptCount == 1
            ? listCamerasResult.future
            : Future.value(const [_backCamera]);
      },
    );
    await tester.tap(find.byKey(const Key('capture-use-camera')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    listCamerasResult.complete(const [_backCamera]);
    await tester.pump();
    await tester.pump();
    expect(cameraPlatform.initializeCallCount, 1);
    expect(find.byKey(const Key('fake-camera-preview')), findsNothing);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(cameraPlatform.initializeCallCount, 2);
    expect(find.byKey(const Key('fake-camera-preview')), findsOneWidget);
    expect(loggedCameraPermissionSteps(), ['requested', 'granted']);
  });
}
