import 'package:flutter/material.dart';

import '../core/report.dart';

/// The app's dark palette. Every colour lives here so the three screens stay
/// consistent and a re-theme is a one-file change.
abstract final class AppColors {
  static const Color background = Color(0xFF07080C);
  static const Color surface = Color(0xFF111420);
  static const Color surfaceHigh = Color(0xFF181C2A);
  static const Color outline = Color(0xFF262B3C);
  static const Color accent = Color(0xFF7C6BFF);
  static const Color accentSoft = Color(0xFFA79BFF);
  static const Color mint = Color(0xFF43E0BC);
  static const Color amber = Color(0xFFFFBE5C);
  static const Color danger = Color(0xFFFF6B7A);
  static const Color textPrimary = Color(0xFFF5F6FB);
  static const Color textSecondary = Color(0xFF98A0B8);
  static const Color textTertiary = Color(0xFF6B748C);
}

/// Score bands drive the colour of rings, chips and bars, so a number always
/// reads the same way wherever it appears.
Color scoreColor(double score) {
  if (score >= 72) {
    return AppColors.mint;
  }
  if (score >= 58) {
    return AppColors.accentSoft;
  }
  if (score >= 42) {
    return AppColors.amber;
  }
  return AppColors.danger;
}

/// Evidence strength drives the small chip beside each piece of advice. Colour
/// is the only difference between "fat loss reveals the jawline" (strong) and
/// "mewing may help" (limited), so the labels never get conflated.
Color evidenceColor(EvidenceStrength strength) {
  return switch (strength) {
    EvidenceStrength.strong => AppColors.mint,
    EvidenceStrength.moderate => AppColors.accentSoft,
    EvidenceStrength.emerging => AppColors.amber,
    EvidenceStrength.measurement => AppColors.textSecondary,
  };
}

ThemeData buildAppTheme() {
  const ColorScheme scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: Colors.white,
    secondary: AppColors.mint,
    onSecondary: AppColors.background,
    surface: AppColors.surface,
    onSurface: AppColors.textPrimary,
    error: AppColors.danger,
    onError: Colors.white,
    outline: AppColors.outline,
  );

  final TextTheme base = Typography.whiteMountainView.apply(
    bodyColor: AppColors.textPrimary,
    displayColor: AppColors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    canvasColor: AppColors.background,
    textTheme: base,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      foregroundColor: AppColors.textPrimary,
    ),
    iconTheme: const IconThemeData(color: AppColors.textPrimary),
    dividerTheme: const DividerThemeData(
      color: AppColors.outline,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(56),
        textStyle: const TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accentSoft,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.surfaceHigh,
      contentTextStyle: TextStyle(color: AppColors.textPrimary, fontSize: 13),
      behavior: SnackBarBehavior.floating,
    ),
  );
}
