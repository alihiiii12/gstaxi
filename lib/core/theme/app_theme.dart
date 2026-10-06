import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'app_text_style.dart';

class AppTheme {
  AppTheme._();

  /// ارتفاع زر موحّد (logical px) — Flutter يحوّله حسب كثافة الشاشة.
  static const double buttonHeight = 50;
  static const double buttonRadius = 14;

  static ThemeData light = ThemeData(
    useMaterial3: true,
    fontFamily: AppTextStyles.fontFamily,
    colorScheme: ColorScheme.light(
      primary: AppColors.primary,
      secondary: AppColors.secondary,
      background: AppColors.background,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.secondary,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: AppColors.secondary,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    textTheme: const TextTheme(
      headlineMedium: AppTextStyles.headline,
      titleMedium: AppTextStyles.title,
      bodyMedium: AppTextStyles.body,
      labelMedium: AppTextStyles.label,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.secondary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.secondary.withValues(alpha: 0.45),
        disabledForegroundColor: Colors.white70,
        textStyle: AppTextStyles.title,
        minimumSize: const Size(double.infinity, buttonHeight),
        maximumSize: const Size(double.infinity, 58),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(double.infinity, buttonHeight),
        maximumSize: const Size(double.infinity, 58),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, buttonHeight),
        maximumSize: const Size(double.infinity, 58),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(buttonRadius),
        ),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      extendedPadding: EdgeInsets.symmetric(horizontal: 18),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
    ),
  );
}
