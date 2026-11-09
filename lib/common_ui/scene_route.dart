import 'package:flutter/material.dart';

/// シーンを切り替える時のフェードの長さ。MaterialPageRoute の既定の遷移の長さ (300ms) に合わせ、
/// 以前の横スライドから見え方だけを変えて待ち時間は変えないため。
const Duration sceneTransitionDuration = Duration(milliseconds: 300);

/// 1 つの画面の中でシーンを入れ替える時の [AnimatedSwitcher.layoutBuilder]。前のシーンは切り替えた時点で外し、
/// 新しいシーンのフェードインだけにする。前のシーンを重ねて残すと、撮る → 図鑑 → 撮る を素早く押した時に撮る画面が
/// 2 つ同時にあってカメラを 2 回開くなど、2 つの画面が同時に BGM・カメラ・ログインを動かすため (#264)。
/// [currentChild] は新しいシーンで、[previousChildren] (フェードアウト中の前のシーン) は使わない。
Widget sceneSwitcherLayoutBuilder(
  Widget? currentChild,
  List<Widget> previousChildren,
) => currentChild ?? const SizedBox.shrink();

/// 画面をゲームのシーンのようにフェードで重ねて開く route を作る (#264)。OS 標準の横スライドの遷移
/// (MaterialPageRoute) と違い、iOS の端のスワイプでは閉じない。閉じるのは画面の「閉じる」「もどる」のボタンと
/// Android の戻る操作だけになる。[builder] は開く画面を作る。
PageRoute<T> sceneRoute<T>({
  required WidgetBuilder builder,
}) => PageRouteBuilder<T>(
  transitionDuration: sceneTransitionDuration,
  reverseTransitionDuration: sceneTransitionDuration,
  // MaterialPageRoute の buildPage と同じく画面単位の Semantics で包み、TalkBack・VoiceOver に新しい画面を知らせる
  // (PageRouteBuilder はこの包みを足さないため)
  pageBuilder: (context, animation, secondaryAnimation) => Semantics(
    scopesRoute: true,
    explicitChildNodes: true,
    child: builder(context),
  ),
  transitionsBuilder: (context, animation, secondaryAnimation, child) =>
      FadeTransition(opacity: animation, child: child),
);
