import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:snapmon/app.dart';
import 'package:snapmon/features/age_gate/age_confirmation.dart';
import 'package:snapmon/features/dex/dex_store.dart';
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
  // Firebase Auth・Analytics・App Check (#12) はここで初期化しない。年齢の確認
  // (AgeConfirmationStatus.allowed) の後に初期化する (ADR 0001「対象年齢」)。
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
    ),
  );
}
