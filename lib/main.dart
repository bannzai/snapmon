import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/app.dart';
import 'package:snapmon/features/age_gate/age_confirmation.dart';
import 'package:snapmon/features/age_gate/age_verified_session_store.dart';
import 'package:snapmon/features/battle/battle_recorder.dart';
import 'package:snapmon/features/capture/monster_generator.dart';
import 'package:snapmon/features/capture/photo_preparation.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/features/opponent/pvp_client.dart';
import 'package:snapmon/features/share/card_sharer.dart';
import 'package:snapmon/features/share/render_widget_png.dart';
import 'package:snapmon/features/share/share_image.dart';
import 'package:snapmon/features/settings/account_store.dart';
import 'package:snapmon/firebase/account.dart';
import 'package:snapmon/firebase/age_verified_session.dart';
import 'package:snapmon/firebase/battle_record.dart';
import 'package:snapmon/firebase/dex_firestore.dart';
import 'package:snapmon/firebase/monster_generation.dart';
import 'package:snapmon/firebase/pvp.dart';
import 'package:snapmon/firebase/share_art.dart';
import 'package:snapmon/firebase_options.dart';
import 'package:snapmon/sample/sample_data.dart';

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
  // 識別子を作る機能は、年齢の確認を通った後に lib/firebase/age_verified_session.dart から始める。
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final ageConfirmationStore = AgeConfirmationStore(
    preferences: await SharedPreferences.getInstance(),
    // Functions の confirmAge (functions/src/age.ts) と同じく UTC の年月で数える。端末の地域の時刻で数えると、
    // 日本時間の月初 0〜9 時に端末だけが通して confirmAge が拒否し、最初の判定だけが有効なためその uid では使えなくなる
    today: () => DateTime.now().toUtc(),
  );
  String? resumedUid;
  try {
    resumedUid = await resumeAgeVerifiedSession(
      hasAllowedAge:
          ageConfirmationStore.status == AgeConfirmationStatus.allowed,
    );
  } catch (error) {
    // 再開に失敗しても起動は止めない (ログインしていない時と同じく、年齢の確認の後のログインからやり直す)。
    debugPrint(error.toString());
  }
  final sampleData = await loadSampleData(bundle: rootBundle);
  // サーバーの master を読むまで (と、ログインを飛ばした DEBUG ビルド) は見本の定義で属性・技を引く
  final dexStore = DexStore(definitions: sampleData.definitions);
  final ageVerifiedSessionStore = AgeVerifiedSessionStore(
    startSession: startAgeVerifiedSessionWithFirebase,
    endSession: endAgeVerifiedSessionWithFirebase,
    resumedUid: resumedUid,
  );
  connectDexToFirestoreWhileSignedIn(
    sessionStore: ageVerifiedSessionStore,
    dexStore: dexStore,
    localDefinitions: sampleData.definitions,
  );
  runApp(
    SnapmonApp(
      sampleData: sampleData,
      dexStore: dexStore,
      ageConfirmationStore: ageConfirmationStore,
      ageVerifiedSessionStore: ageVerifiedSessionStore,
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
        pickAlbumPhoto: pickAlbumPhoto,
        preparePhoto: prepareGenerationPhotoInBackground,
        createRequestId: const Uuid().v4,
        uploadPhoto: uploadGenerationPhotoWithFirebase,
        requestGeneration: requestGenerationWithFirebase,
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
        sessionStore: ageVerifiedSessionStore,
        ageConfirmationStore: ageConfirmationStore,
        linkProviderName: accountLinkProviderNameForPlatform,
        readLinkedProviderNames: linkedProviderNamesWithFirebase,
        linkAccount: linkAccountWithFirebase,
        discardCurrentAccount: deleteCurrentAccountOnServerWithFirebase,
        deleteAccount: deleteAccountWithFirebase,
      ),
    ),
  );
}
