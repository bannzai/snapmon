import 'package:flutter/widgets.dart';

import '../domain/battle/status_condition.dart';
import '../domain/monster/monster_stats.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// 画面の文言 (lib/l10n/app_*.arb) を `context.l10n.<キー>` で引くための拡張。
extension L10nBuildContext on BuildContext {
  /// この位置の言語の文言。
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// [statKind] の画面の名前 (HP・攻撃・防御・素早さ・命中) を、[l10n] の言語で返す。
String statLabel({
  required AppLocalizations l10n,
  required StatKind statKind,
}) => switch (statKind) {
  StatKind.hitPoints => l10n.statHitPoints,
  StatKind.attack => l10n.statAttack,
  StatKind.defense => l10n.statDefense,
  StatKind.speed => l10n.statSpeed,
  StatKind.accuracy => l10n.statAccuracy,
};

/// 状態 [kind] の画面の名前 (どく・まひ 等) を、[l10n] の言語で返す。
String statusConditionLabel({
  required AppLocalizations l10n,
  required StatusConditionKind kind,
}) => switch (kind) {
  StatusConditionKind.poison => l10n.statusConditionPoison,
  StatusConditionKind.paralysis => l10n.statusConditionParalysis,
  StatusConditionKind.stun => l10n.statusConditionStun,
  StatusConditionKind.burn => l10n.statusConditionBurn,
  StatusConditionKind.drowsy => l10n.statusConditionDrowsy,
  StatusConditionKind.sleep => l10n.statusConditionSleep,
  StatusConditionKind.curse => l10n.statusConditionCurse,
  StatusConditionKind.confusion => l10n.statusConditionConfusion,
  StatusConditionKind.dizzy => l10n.statusConditionDizzy,
  StatusConditionKind.excited => l10n.statusConditionExcited,
  StatusConditionKind.frozen => l10n.statusConditionFrozen,
  StatusConditionKind.switchBlocked => l10n.statusConditionSwitchBlocked,
};

/// 遊び方の画面に出す、状態 [kind] の効果の短い説明。効果の正は documents/game-rules.md「状態」と [StatusConditionKind] で、
/// 説明は確率や重なりの上限のような細かい数値を写さずに働き方だけを書く (調整で数値を変えた時に説明が古くならないため)。
String statusConditionHelpDescription({
  required AppLocalizations l10n,
  required StatusConditionKind kind,
}) => switch (kind) {
  StatusConditionKind.poison => l10n.helpStatusPoison,
  StatusConditionKind.paralysis => l10n.helpStatusParalysis,
  StatusConditionKind.stun => l10n.helpStatusStun,
  StatusConditionKind.burn => l10n.helpStatusBurn,
  StatusConditionKind.drowsy => l10n.helpStatusDrowsy,
  StatusConditionKind.sleep => l10n.helpStatusSleep,
  StatusConditionKind.curse => l10n.helpStatusCurse,
  StatusConditionKind.confusion => l10n.helpStatusConfusion,
  StatusConditionKind.dizzy => l10n.helpStatusDizzy,
  StatusConditionKind.excited => l10n.helpStatusExcited,
  StatusConditionKind.frozen => l10n.helpStatusFrozen,
  StatusConditionKind.switchBlocked => l10n.helpStatusSwitchBlocked,
};
