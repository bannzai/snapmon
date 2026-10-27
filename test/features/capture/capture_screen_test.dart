import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';

import 'package:snapmon/features/capture/capture_screen.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/theme/snapmon_theme.dart';

import '../../battle_recorder_fixture.dart';
import '../../card_sharer_fixture.dart';
import '../../monster_generator_fixture.dart';
import '../../pvp_client_fixture.dart';
import '../../sample_data_fixture.dart';

void main() {
  testWidgets('カメラを開いている途中にアプリが裏に回ると、その試みの結果を捨てて戻った時の試みの結果を出す', (tester) async {
    final firstListCameras = Completer<List<CameraDescription>>();
    var listCamerasCallCount = 0;
    final generator = fakeMonsterGenerator(
      calls: RecordedGenerationCalls(),
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
                return listCamerasCallCount == 1
                    ? firstListCameras.future
                    : Future.error(StateError('戻った後の試みの結果'));
              },
              pickAlbumPhoto: generator.pickAlbumPhoto,
              preparePhoto: generator.preparePhoto,
              createSubjectMask: generator.createSubjectMask,
              createSquareMask: generator.createSquareMask,
              createCutoutPreview: generator.createCutoutPreview,
              createRequestId: generator.createRequestId,
              uploadPhoto: generator.uploadPhoto,
              uploadMask: generator.uploadMask,
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
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(listCamerasCallCount, 2);
    expect(find.textContaining('戻った後の試みの結果'), findsOneWidget);

    firstListCameras.completeError(StateError('裏に回る前の試みの結果'));
    await tester.pumpAndSettle();
    expect(find.textContaining('裏に回る前の試みの結果'), findsNothing);
    expect(find.textContaining('戻った後の試みの結果'), findsOneWidget);
  });
}
