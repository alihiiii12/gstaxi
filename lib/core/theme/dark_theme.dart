import 'package:flutter/material.dart';

import 'app_text_style.dart';
import 'colors/app_color_dark.dart';


class AppThemeDark {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: AppTextStyles.fontFamily,

    scaffoldBackgroundColor: AppColorsDark.background,

    colorScheme: ColorScheme.dark(
      primary: AppColorsDark.primary,
      secondary: AppColorsDark.secondary,
      background: AppColorsDark.background,
      surface: AppColorsDark.surface,
      error: AppColorsDark.error,
    ),

    textTheme: TextTheme(
      headlineMedium:
      AppTextStyles.headline.copyWith(color: AppColorsDark.textPrimary),
      titleMedium:
      AppTextStyles.title.copyWith(color: AppColorsDark.textPrimary),
      bodyMedium:
      AppTextStyles.body.copyWith(color: AppColorsDark.textSecondary),
      labelMedium:
      AppTextStyles.label.copyWith(color: AppColorsDark.textSecondary),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColorsDark.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColorsDark.border),
      ),
    ),
  );
}
