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
import 'package:snapmon/audio/audio_settings_preferences.dart';
import 'package:snapmon/audio/flame_game_audio.dart';
import 'package:snapmon/audio/game_audio.dart';
import 'package:snapmon/features/action_card/action_card_client.dart';
import 'package:snapmon/features/action_card/action_card_store.dart';
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
import 'package:snapmon/firebase/action_cards.dart';
import 'package:snapmon/firebase/battle_record.dart';
import 'package:snapmon/firebase/dex_firestore.dart';
import 'package:snapmon/firebase/monster_generation.dart';
import 'package:snapmon/firebase/purchases.dart';
import 'package:snapmon/firebase/pvp.dart';
import 'package:snapmon/firebase/session.dart';
import 'package:snapmon/firebase/share_art.dart';
import 'package:snapmon/firebase_options.dart';
import 'package:snapmon/sample/sample_action_cards.dart';
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
    yield LicenseEntryWithLineBreaks(
      ['PixelFX'],
      [
        await rootBundle.loadString('assets/images/move_effects/LICENSE'),
        await rootBundle.loadString('assets/images/move_effects/NOTICE.md'),
      ].join('\n\n'),
    );
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
  await initializeFlameAudio();
  final gameAudio = GameAudio(
    playBackgroundMusicAsset: playBackgroundMusicWithFlameAudio,
    stopBackgroundMusicAsset: stopBackgroundMusicWithFlameAudio,
    playSoundEffectAsset: playSoundEffectWithFlameAudio,
    saveSetting: saveAudioSettingToPreferences,
    isBackgroundMusicEnabled: await readAudioSettingFromPreferences(
      key: AudioSettingKey.backgroundMusic,
    ),
    isSoundEffectsEnabled: await readAudioSettingFromPreferences(
      key: AudioSettingKey.soundEffects,
    ),
    waitsForUserInteractionBeforeBackgroundMusic: kIsWeb,
  );
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
  connectPurchasesWhileSignedIn(sessionStore: sessionStore);
  // DEBUG ビルドでログインを飛ばした (「ログインせずに使う」) 時は、Action Card を端末だけの見本で置き換える (lib/sample/sample_action_cards.dart)。
  // release ビルドでは kDebugMode が const の false のため、見本は作らずこの経路はビルドから除かれる
  final sampleActionCards = kDebugMode
      ? SampleActionCards(
          actionCardMoveIDsOf: ({required monsterID}) =>
              dexStore.monsters
                  .where((monster) => monster.definition.id == monsterID)
                  .firstOrNull
                  ?.actionCardMoveIDs ??
              const [],
        )
      : null;
  bool isSample() => sampleActionCards != null && sessionStore.uid == null;
  final sampleActionCardClient = sampleActionCards?.client();
  final actionCardStore = ActionCardStore(
    sessionChanges: sessionStore,
    sampleActionCards: sampleActionCards,
    client: ActionCardClient(
      isPurchaseSupported: () => isSample() || isPurchasesEnabled(),
      watchActionCardsVisible: () => isSample()
          ? sampleActionCardClient!.watchActionCardsVisible()
          : watchActionCardsVisibleWithFirebase(),
      fetchActionCardPackages: () => isSample()
          ? sampleActionCardClient!.fetchActionCardPackages()
          : fetchActionCardPackagesWithRevenueCat(),
      purchaseActionCardPackage: ({required package}) => isSample()
          ? sampleActionCardClient!.purchaseActionCardPackage(package: package)
          : purchaseTicketPackageWithRevenueCat(package: package),
      watchActionCardPurchases: () => isSample()
          ? sampleActionCardClient!.watchActionCardPurchases()
          : watchActionCardPurchasesWithFirebase(),
      watchActionCardProductIDByMoveID: () => isSample()
          ? sampleActionCardClient!.watchActionCardProductIDByMoveID()
          : watchActionCardProductIDByMoveIDWithFirebase(),
      reserveActionCardMove: ({required moveID, required productID}) =>
          isSample()
          ? sampleActionCardClient!.reserveActionCardMove(
              moveID: moveID,
              productID: productID,
            )
          : reserveActionCardMoveWithFirebase(
              moveID: moveID,
              productID: productID,
            ),
      assignActionCardMove:
          ({required actionCardPurchaseID, required moveID}) => isSample()
          ? sampleActionCardClient!.assignActionCardMove(
              actionCardPurchaseID: actionCardPurchaseID,
              moveID: moveID,
            )
          : assignActionCardMoveWithFirebase(
              actionCardPurchaseID: actionCardPurchaseID,
              moveID: moveID,
            ),
      teachActionCardMove: ({required monsterID, required moveID}) => isSample()
          ? sampleActionCardClient!.teachActionCardMove(
              monsterID: monsterID,
              moveID: moveID,
            )
          : teachActionCardMoveWithFirebase(
              monsterID: monsterID,
              moveID: moveID,
            ),
      forgetActionCardMove: ({required monsterID, required moveID}) =>
          isSample()
          ? sampleActionCardClient!.forgetActionCardMove(
              monsterID: monsterID,
              moveID: moveID,
            )
          : forgetActionCardMoveWithFirebase(
              monsterID: monsterID,
              moveID: moveID,
            ),
    ),
  );
  runApp(
    SnapmonApp(
      sampleData: sampleData,
      dexStore: dexStore,
      sessionStore: sessionStore,
      gameAudio: gameAudio,
      openURL: ({required uri}) =>
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
        fetchProfile: fetchProfileWithFirebase,
        updateDisplayName: updateDisplayNameWithFirebase,
        updateIcon: updateProfileIconWithFirebase,
      ),
      monsterGenerator: MonsterGenerator(
        listCameras: availableCameras,
        openAppSettings: openAppSettings,
        pickAlbumPhoto: pickAlbumPhoto,
        preparePhoto: prepareGenerationPhotoInBackground,
        createSubjectMask: createSubjectMaskWithOs,
        createSquareMask: createSquareMaskInBackground,
        createCutoutPreview: createCutoutPreviewInBackground,
        createRequestID: const Uuid().v4,
        // DEBUG ビルドでログインを飛ばした (「ログインせずに使う」) 時は、写真を送らず見本のモンスターで生成を置き換える
        // (lib/sample/sample_generation.dart)。release ビルドでは kDebugMode が const の false のため、この経路はビルドから除かれる
        uploadPhoto: ({required requestID, required photo}) async {
          if (kDebugMode && sessionStore.uid == null) {
            return;
          }
          await uploadGenerationPhotoWithFirebase(
            requestID: requestID,
            photo: photo,
          );
        },
        uploadMask: ({required requestID, required mask}) async {
          if (kDebugMode && sessionStore.uid == null) {
            return;
          }
          await uploadGenerationMaskWithFirebase(
            requestID: requestID,
            mask: mask,
          );
        },
        requestGeneration:
            ({
              required requestID,
              required maskSource,
              required onCompletedStage,
            }) async {
              if (kDebugMode && sessionStore.uid == null) {
                return generateSampleMonster(
                  dexStore: dexStore,
                  sampleData: sampleData,
                  requestID: requestID,
                );
              }
              return requestGenerationWithFirebase(
                requestID: requestID,
                maskSource: maskSource,
                onCompletedStage: onCompletedStage,
              );
            },
        fetchGeneration: fetchGenerationWithFirebase,
        fetchTicketPackages: fetchTicketPackagesWithRevenueCat,
        purchaseTicketPackage: purchaseTicketPackageWithRevenueCat,
        syncTicketPurchases: syncTicketPurchasesWithRevenueCat,
        watchGenerationTickets: watchGenerationTicketsWithFirebase,
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
      actionCardStore: actionCardStore,
    ),
  );
}
