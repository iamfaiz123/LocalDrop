import 'package:flutter/material.dart';

class AppColors {
  static const bg = Color(0xFFF7F6FF);
  static const surface = Colors.white;
  static const primary = Color(0xFF6845D8);
  static const primaryDark = Color(0xFF5132BF);
  static const lavender = Color(0xFFEDE8FF);
  static const text = Color(0xFF17152A);
  static const muted = Color(0xFF77748B);
  static const border = Color(0xFFE9E6F3);
  static const green = Color(0xFF19A875);
  static const red = Color(0xFFE34B59);
  static const amber = Color(0xFF8A5A00);
}

/// Plus Jakarta Sans is bundled in assets/fonts so the app renders
/// identically without internet access.
const appFontFamily = 'PlusJakartaSans';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    fontFamily: appFontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.bg,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
      fontFamily: appFontFamily,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      centerTitle: false,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.border),
      ),
    ),
  );
}
