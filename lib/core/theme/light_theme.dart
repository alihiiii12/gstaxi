import 'package:flutter/material.dart';
import 'app_text_style.dart';
import 'colors/app_color_light.dart';


class AppThemeLight {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: AppTextStyles.fontFamily,

    scaffoldBackgroundColor: AppColorsLight.background,

    colorScheme: ColorScheme.light(
      primary: AppColorsLight.primary,
      secondary: AppColorsLight.secondary,
      background: AppColorsLight.background,
      surface: AppColorsLight.surface,
      error: AppColorsLight.error,
    ),

    textTheme: TextTheme(
      headlineMedium:
      AppTextStyles.headline.copyWith(color: AppColorsLight.textPrimary),
      titleMedium:
      AppTextStyles.title.copyWith(color: AppColorsLight.textPrimary),
      bodyMedium:
      AppTextStyles.body.copyWith(color: AppColorsLight.textSecondary),
      labelMedium:
      AppTextStyles.label.copyWith(color: AppColorsLight.textSecondary),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColorsLight.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColorsLight.border),
      ),
    ),
  );
}
