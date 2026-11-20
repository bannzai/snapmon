import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import 'session.dart';

// DEBUG ビルドを Firebase Local Emulator Suite につなぐ切り替え。
// 本番に出す前の Functions・Rules を、手元か GitHub Actions のランナーの Emulator で、アプリの画面から通して確かめるために使う
// (例: 人との対戦を 2 人の利用者で最後まで進める。`.github/workflows/browser-session.yml` の `firebase_emulator`)。
// 開発者メニューではなくビルドの時の値で切り替えるのは、Firebase の最初の呼び出し (起動の時のログインの再開) より前に
// つなぎ先を決める必要があるため。

/// `--dart-define=FIREBASE_EMULATOR_HOST=<ホスト>` で渡す、Emulator が動いているホスト (例: `127.0.0.1`)。渡さなければ空で、本番につなぐ。
const _firebaseEmulatorHost = String.fromEnvironment('FIREBASE_EMULATOR_HOST');

/// Emulator のプロジェクト ID。Functions の Emulator のテスト (`functions/package.json` の `test:emulator`) と同じ値で、
/// `demo-` で始まるプロジェクトは Emulator に無いサービスを本番に取りに行かない
/// ( https://firebase.google.com/docs/emulator-suite/connect_firestore#choose_a_firebase_project )。
const _firebaseEmulatorProjectID = 'demo-snapmon';

/// Emulator につなぐビルドか。release ビルドでは kDebugMode が const の false のため常に false で、つなぐ経路はビルドから除かれる。
const bool usesFirebaseEmulator = kDebugMode && _firebaseEmulatorHost != '';

/// Emulator につなぐビルドでは、[options] のプロジェクト ID を Emulator のプロジェクトに替えた設定を返す。それ以外は [options] をそのまま返す。
/// Functions の Emulator は URL のプロジェクト ID で関数を引くため、本番のプロジェクト ID のままでは呼び出しが届かない。
FirebaseOptions firebaseOptionsForEmulator({
  required FirebaseOptions options,
}) => usesFirebaseEmulator
    ? options.copyWith(projectId: _firebaseEmulatorProjectID)
    : options;

/// Emulator につなぐビルドでは、Auth・Firestore・Functions・Storage のつなぎ先を Emulator にする。それ以外は何もしない。
/// `Firebase.initializeApp` の後、Firebase の他の呼び出しより前に 1 回だけ呼ぶ。ポートは `firebase.json` の `emulators` と同じ。
Future<void> connectFirebaseEmulators() async {
  if (!usesFirebaseEmulator) {
    return;
  }
  await FirebaseAuth.instance.useAuthEmulator(_firebaseEmulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(_firebaseEmulatorHost, 8080);
  FirebaseFunctions.instanceFor(
    region: functionsRegion,
  ).useFunctionsEmulator(_firebaseEmulatorHost, 5001);
  await FirebaseStorage.instance.useStorageEmulator(
    _firebaseEmulatorHost,
    9199,
  );
}
