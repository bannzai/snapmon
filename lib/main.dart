import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'package:snapmon/snapmon_game.dart';

void main() {
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
