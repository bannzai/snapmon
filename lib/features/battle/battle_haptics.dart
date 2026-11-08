import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// バトルの演出に合わせた触覚のフィードバック。iOS / Android の端末だけで鳴らし、Web とデスクトップでは何もしない
/// (Flutter の HapticFeedback は iOS / Android 以外では何も起こさないが、呼び出し自体も省く。#224)。
class BattleHaptics {
  /// バトルの触覚のフィードバックを作る。[isEnabled] は端末が iOS / Android か (省くとビルドの対象の環境から決める)。
  BattleHaptics({bool? isEnabled})
    : isEnabled =
          isEnabled ??
          (!kIsWeb &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.android));

  /// フィードバックを鳴らすか。
  final bool isEnabled;

  /// 技が当たった時 (中くらいの衝撃)。
  Future<void> hit() => _run(HapticFeedback.mediumImpact);

  /// モンスターが倒れた時 (強い衝撃)。
  Future<void> faint() => _run(HapticFeedback.heavyImpact);

  /// 状態が付いた・ステータスが変わった時 (弱い衝撃)。
  Future<void> statusChanged() => _run(HapticFeedback.lightImpact);

  Future<void> _run(Future<void> Function() feedback) async {
    if (!isEnabled) {
      return;
    }
    try {
      await feedback();
    } catch (error) {
      // 触覚のフィードバックの失敗 (対応しない端末等) でバトルを止めない
      debugPrint('haptic: $error');
    }
  }
}
