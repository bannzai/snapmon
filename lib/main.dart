import 'package:firebase_core/firebase_core.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:snapmon/firebase/age_verified_session.dart';
import 'package:snapmon/firebase_options.dart';
import 'package:snapmon/snapmon_game.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // initializeApp だけでは識別子を作らない (Analytics・Crashlytics の自動収集は既定で無効、App Check と匿名ログインは未開始)。
  // 識別子を作る機能は、年齢の確認を通った後に lib/firebase/age_verified_session.dart から始める。
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  try {
    await resumeAgeVerifiedSession();
  } catch (error) {
    // 再開に失敗しても起動は止めない (年齢の確認を済ませていない時と同じ状態で始まる)。
    debugPrint(error.toString());
  }
  runApp(const SnapmonApp());
}

/// アプリのルート。ゲーム画面 ([SnapmonGame]) を全画面に置く。
class SnapmonApp extends StatelessWidget {
  const SnapmonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'snapmon',
      home: Scaffold(body: GameWidget(game: SnapmonGame())),
    );
  }
}
