import 'package:flutter/material.dart';

import 'snapmon_colors.dart';
import 'snapmon_radii.dart';
import 'snapmon_text_styles.dart';

/// アプリ全体の [ThemeData] を返す。色・文字・角丸は lib/theme/ の定義から組む。
ThemeData snapmonThemeData() => ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: SnapmonColors.background,
  fontFamily: bodyFontFamily,
  colorScheme: const ColorScheme.dark(
    primary: SnapmonColors.accent,
    onPrimary: SnapmonColors.textOnCard,
    surface: SnapmonColors.background,
    onSurface: SnapmonColors.textOnBackground,
    error: SnapmonColors.hitPointsLoss,
  ),
  textTheme: const TextTheme(
    bodyMedium: SnapmonTextStyles.body,
    titleMedium: SnapmonTextStyles.label,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: SnapmonColors.background,
    foregroundColor: SnapmonColors.textOnBackground,
    elevation: 0,
    titleTextStyle: SnapmonTextStyles.label,
  ),
  snackBarTheme: const SnackBarThemeData(
    backgroundColor: SnapmonColors.surface,
    contentTextStyle: SnapmonTextStyles.body,
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: SnapmonColors.accent,
      foregroundColor: SnapmonColors.textOnCard,
      disabledBackgroundColor: SnapmonColors.surface,
      disabledForegroundColor: SnapmonColors.textMuted,
      textStyle: SnapmonTextStyles.buttonLarge,
      minimumSize: const Size.fromHeight(56),
      shape: const RoundedRectangleBorder(borderRadius: SnapmonRadii.card),
    ),
  ),
  listTileTheme: const ListTileThemeData(
    textColor: SnapmonColors.textOnBackground,
    iconColor: SnapmonColors.textMuted,
    titleTextStyle: SnapmonTextStyles.label,
    subtitleTextStyle: SnapmonTextStyles.small,
  ),
  dividerColor: SnapmonColors.surface,
);
