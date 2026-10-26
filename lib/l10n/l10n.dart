import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// 画面の文言 (lib/l10n/app_*.arb) を `context.l10n.<キー>` で引くための拡張。
extension L10nBuildContext on BuildContext {
  /// この位置の言語の文言。
  AppLocalizations get l10n => AppLocalizations.of(this);
}
