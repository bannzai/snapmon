import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/app.dart';
import 'package:snapmon/features/age_gate/age_confirmation.dart';
import 'package:snapmon/features/age_gate/age_verified_session_store.dart';
import 'package:snapmon/features/battle/battle_recorder.dart';
import 'package:snapmon/features/dex/dex_store.dart';
import 'package:snapmon/firebase/age_verified_session.dart';
import 'package:snapmon/firebase/battle_record.dart';
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
    today: DateTime.now,
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
  runApp(
    SnapmonApp(
      sampleData: await loadSampleData(bundle: rootBundle),
      dexStore: DexStore(),
      ageConfirmationStore: ageConfirmationStore,
      ageVerifiedSessionStore: AgeVerifiedSessionStore(
        startSession: startAgeVerifiedSessionWithFirebase,
        endSession: endAgeVerifiedSessionWithFirebase,
        resumedUid: resumedUid,
      ),
      openUrl: ({required uri}) =>
          launchUrl(uri, mode: LaunchMode.externalApplication),
      isDeveloperMenuEnabled: kDebugMode,
      battleRecorder: BattleRecorder(
        // 図鑑を Firestore に繋ぐ (#14) までは、サーバーにモンスターが無く startBattle が not-found で拒否するため、
        // 記録を始めない (端末の計算のレベルを反映する)。#14 で startBattleRecordWithFirebase に戻す
        startBattleRecord: ({required partyMonsterIds}) async => null,
        completeBattleRecord: completeBattleRecordWithFirebase,
        logEvent: logAnalyticsEvent,
      ),
    ),
  );
}
