import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/app.dart';
import 'package:snapmon/features/battle/battle_recorder.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/capture/photo_preparation.dart';
import 'package:snapmon/features/capture/subject_mask.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/session/session_store.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/render_widget_png.dart';
import 'package:snapmon/features/share/share_image.dart';
import 'package:snapmon/features/settings/account_store.dart';
import 'package:snapmon/firebase/account.dart';
import 'package:snapmon/firebase/battle_record.dart';
import 'package:snapmon/firebase/dex_firestore.dart';
import 'package:snapmon/firebase/monster_generation.dart';
import 'package:snapmon/firebase/pvp.dart';
import 'package:snapmon/firebase/session.dart';
import 'package:snapmon/firebase/share_art.dart';
import 'package:snapmon/firebase_options.dart';
import 'package:snapmon/sample/sample_data.dart';
import 'package:snapmon/sample/sample_generation.dart';

/// 同梱したフォントの OFL のライセンス本文 (pubspec.yaml の assets) と、そのフォントの名前。
const Map<String, String> _fontLicenseAssetPaths = {
  'Dela Gothic One': 'assets/fonts/dela_gothic_one/OFL.txt',
  'Zen Kaku Gothic New': 'assets/fonts/zen_kaku_gothic_new/OFL.txt',
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in _fontLicenseAssetPaths.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString(entry.value));
    }
  });
  // initializeApp だけでは識別子を作らない (Analytics・Crashlytics の自動収集は既定で無効、App Check と匿名ログインは未開始)。
  // 識別子を作る機能は、ログインと同時に lib/firebase/session.dart から始める。
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  String? resumedUid;
  try {
    resumedUid = await resumeSessionWithFirebase();
  } catch (error) {
    // 再開に失敗しても起動は止めない (ログインしていない時と同じく、ログインの画面からやり直す)。
    debugPrint(error.toString());
  }
  final sampleData = await loadSampleData(bundle: rootBundle);
  // サーバーの master を読むまで (と、ログインを飛ばした DEBUG ビルド) は見本の定義で属性・技を引く
  final dexStore = DexStore(definitions: sampleData.definitions);
  final sessionStore = SessionStore(
    startSession: startSessionWithFirebase,
    endSession: endSessionWithFirebase,
    resumedUid: resumedUid,
  );
  connectDexToFirestoreWhileSignedIn(
    sessionStore: sessionStore,
    dexStore: dexStore,
    localDefinitions: sampleData.definitions,
  );
  runApp(
    SnapmonApp(
      sampleData: sampleData,
      dexStore: dexStore,
      sessionStore: sessionStore,
      openUrl: ({required uri}) =>
          launchUrl(uri, mode: LaunchMode.externalApplication),
      isDeveloperMenuEnabled: kDebugMode,
      battleRecorder: const BattleRecorder(
        startBattleRecord: startBattleRecordWithFirebase,
        completeBattleRecord: completeBattleRecordWithFirebase,
        logEvent: logAnalyticsEvent,
      ),
      pvpClient: const PvpClient(
        fetchOpponents: fetchPvpOpponentsWithFirebase,
        fetchDefinitions: fetchDefinitionsWithFirebase,
        reportMonster: reportMonsterWithFirebase,
        blockUser: blockUserWithFirebase,
        fetchBattleRecord: fetchBattleRecordWithFirebase,
        fetchDisplayName: fetchDisplayNameWithFirebase,
        updateDisplayName: updateDisplayNameWithFirebase,
      ),
      monsterGenerator: MonsterGenerator(
        listCameras: availableCameras,
        openAppSettings: openAppSettings,
        pickAlbumPhoto: pickAlbumPhoto,
        preparePhoto: prepareGenerationPhotoInBackground,
        createSubjectMask: createSubjectMaskWithOs,
        createSquareMask: createSquareMaskInBackground,
        createCutoutPreview: createCutoutPreviewInBackground,
        createRequestId: const Uuid().v4,
        // DEBUG ビルドでログインを飛ばした (「ログインせずに使う」) 時は、写真を送らず見本のモンスターで生成を置き換える
        // (lib/sample/sample_generation.dart)。release ビルドでは kDebugMode が const の false のため、この経路はビルドから除かれる
        uploadPhoto: ({required requestId, required photo}) async {
          if (kDebugMode && sessionStore.uid == null) {
            return;
          }
          await uploadGenerationPhotoWithFirebase(
            requestId: requestId,
            photo: photo,
          );
        },
        uploadMask: ({required requestId, required mask}) async {
          if (kDebugMode && sessionStore.uid == null) {
            return;
          }
          await uploadGenerationMaskWithFirebase(
            requestId: requestId,
            mask: mask,
          );
        },
        requestGeneration:
            ({
              required requestId,
              required maskSource,
              required onCompletedStage,
            }) async {
              if (kDebugMode && sessionStore.uid == null) {
                return generateSampleMonster(
                  dexStore: dexStore,
                  sampleData: sampleData,
                  requestId: requestId,
                );
              }
              return requestGenerationWithFirebase(
                requestId: requestId,
                maskSource: maskSource,
                onCompletedStage: onCompletedStage,
              );
            },
        fetchGeneration: fetchGenerationWithFirebase,
        logEvent: logAnalyticsEvent,
      ),
      cardSharer: const CardSharer(
        loadArtImage: loadArtImageWithFirebase,
        renderPng: renderWidgetToPng,
        shareImage: shareImageWithSharePlus,
        logEvent: logAnalyticsEvent,
      ),
      accountStore: AccountStore(
        sessionStore: sessionStore,
        linkProviderName: accountLinkProviderNameForPlatform,
        readLinkedProviderNames: linkedProviderNamesWithFirebase,
        linkAccount: linkAccountWithFirebase,
        discardCurrentAccount: deleteCurrentAccountOnServerWithFirebase,
        deleteAccount: deleteAccountWithFirebase,
      ),
      logEvent: logAnalyticsEvent,
    ),
  );
}
