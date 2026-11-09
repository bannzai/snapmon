import 'package:flutter/material.dart';

/// シーンを切り替える時のフェードの長さ。MaterialPageRoute の既定の遷移の長さ (300ms) に合わせ、
/// 以前の横スライドから見え方だけを変えて待ち時間は変えないため。
const Duration sceneTransitionDuration = Duration(milliseconds: 300);

/// 画面をゲームのシーンのようにフェードで重ねて開く route を作る (#264)。OS 標準の横スライドの遷移
/// (MaterialPageRoute) と違い、iOS の端のスワイプでは閉じない。閉じるのは画面の「閉じる」「もどる」のボタンと
/// Android の戻る操作だけになる。[builder] は開く画面を作る。
PageRoute<T> sceneRoute<T>({required WidgetBuilder builder}) =>
    PageRouteBuilder<T>(
      transitionDuration: sceneTransitionDuration,
      reverseTransitionDuration: sceneTransitionDuration,
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
