import 'package:material_ui/material_ui.dart';

import 'vibono_colors.dart';

/// Überschriften: Myriad Pro laut Design-System, als frei verfügbarer Ersatz
/// ist Source Sans 3 eingebettet. Fließtext: Verdana (auf iOS vorhanden),
/// sonst die Systemschrift.
abstract final class VibonoFonts {
  static const display = 'SourceSans3';
  static const body = 'Verdana';
  static const bodyFallback = <String>['DejaVu Sans', 'Roboto', 'sans-serif'];
}

abstract final class VibonoText {
  static const _d = VibonoFonts.display;

  static const hello = TextStyle(
    fontFamily: _d,
    fontSize: 26,
    fontWeight: FontWeight.w600,
    color: VibonoColors.grey900,
    height: 1.15,
  );

  static const screenTitle = TextStyle(
    fontFamily: _d,
    fontSize: 26,
    fontWeight: FontWeight.w300,
    letterSpacing: 1.0,
    color: VibonoColors.grey900,
  );

  /// Kleine grüne Großbuchstaben-Überschrift („DEINE REZEPTE FÜR HEUTE“).
  static const label = TextStyle(
    fontFamily: _d,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.0,
    color: VibonoColors.green700,
  );

  static const cardTitle = TextStyle(
    fontFamily: _d,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: VibonoColors.grey900,
    height: 1.2,
  );

  static const body = TextStyle(
    fontFamily: VibonoFonts.body,
    fontFamilyFallback: VibonoFonts.bodyFallback,
    fontSize: 14,
    color: VibonoColors.grey700,
    height: 1.45,
  );

  static const small = TextStyle(
    fontFamily: VibonoFonts.body,
    fontFamilyFallback: VibonoFonts.bodyFallback,
    fontSize: 12,
    color: VibonoColors.grey500,
    height: 1.35,
  );
}

ThemeData buildVibonoTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: VibonoColors.green,
    primary: VibonoColors.green,
    onPrimary: Colors.white,
    secondary: VibonoColors.green700,
    surface: Colors.white,
    onSurface: VibonoColors.grey800,
    error: const Color(0xFFDC3545),
  );
  final pill = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
  const buttonText = TextStyle(
    fontFamily: VibonoFonts.display,
    fontWeight: FontWeight.w600,
    fontSize: 15,
    letterSpacing: 0.6,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
    fontFamily: VibonoFonts.body,
    fontFamilyFallback: VibonoFonts.bodyFallback,
    textTheme: const TextTheme(
      headlineMedium: VibonoText.screenTitle,
      titleLarge: TextStyle(fontFamily: VibonoFonts.display, fontWeight: FontWeight.w600, color: VibonoColors.grey900),
      titleMedium: VibonoText.cardTitle,
      bodyMedium: VibonoText.body,
      bodySmall: VibonoText.small,
      labelLarge: buttonText,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: VibonoColors.grey900,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: VibonoFonts.display,
        fontSize: 20,
        fontWeight: FontWeight.w300,
        letterSpacing: 0.8,
        color: VibonoColors.grey900,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VibonoColors.green,
        foregroundColor: Colors.white,
        shape: pill,
        minimumSize: const Size(48, 48),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: VibonoColors.green700,
        side: const BorderSide(color: VibonoColors.green, width: 1.5),
        shape: pill,
        minimumSize: const Size(48, 48),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: VibonoColors.green700,
        textStyle: buttonText.copyWith(fontSize: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: VibonoColors.grey050,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VibonoColors.grey200),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VibonoColors.grey200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: VibonoColors.green, width: 2),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white,
      selectedColor: VibonoColors.green,
      side: const BorderSide(color: VibonoColors.grey200, width: 1.5),
      shape: pill,
      labelStyle: const TextStyle(
        fontFamily: VibonoFonts.display,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: VibonoColors.grey800,
      ),
      secondaryLabelStyle: const TextStyle(color: Colors.white),
      checkmarkColor: Colors.white,
    ),
    dividerTheme: const DividerThemeData(color: VibonoColors.grey100, thickness: 1, space: 1),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VibonoColors.grey800,
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: VibonoColors.green,
      inactiveTrackColor: VibonoColors.grey100,
      thumbColor: VibonoColors.green,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: VibonoColors.green),
  );
}
