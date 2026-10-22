import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:snapmon/analytics/analytics_events.dart';
import 'package:snapmon/app.dart';
import 'package:snapmon/features/age_gate/age_confirmation.dart';
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
  try {
    await resumeAgeVerifiedSession();
  } catch (error) {
    // 再開に失敗しても起動は止めない (年齢の確認を済ませていない時と同じ状態で始まる)。
    debugPrint(error.toString());
  }
  runApp(
    SnapmonApp(
      sampleData: await loadSampleData(bundle: rootBundle),
      dexStore: DexStore(),
      ageConfirmationStore: AgeConfirmationStore(
        preferences: await SharedPreferences.getInstance(),
        today: DateTime.now,
      ),
      openUrl: ({required uri}) =>
          launchUrl(uri, mode: LaunchMode.externalApplication),
      isDeveloperMenuEnabled: kDebugMode,
      battleRecorder: const BattleRecorder(
        startBattleRecord: startBattleRecordWithFirebase,
        completeBattleRecord: completeBattleRecordWithFirebase,
        logEvent: logAnalyticsEvent,
      ),
    ),
  );
}
