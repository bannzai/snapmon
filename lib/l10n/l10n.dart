import 'package:flutter/widgets.dart';

import '../domain/monster/monster_stats.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// 画面の文言 (lib/l10n/app_*.arb) を `context.l10n.<キー>` で引くための拡張。
extension L10nBuildContext on BuildContext {
  /// この位置の言語の文言。
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// [statKind] の画面の名前 (HP・攻撃・防御・素早さ) を、[l10n] の言語で返す。
String statLabel({
  required AppLocalizations l10n,
  required StatKind statKind,
}) => switch (statKind) {
  StatKind.hitPoints => l10n.statHitPoints,
  StatKind.attack => l10n.statAttack,
  StatKind.defense => l10n.statDefense,
  StatKind.speed => l10n.statSpeed,
};
