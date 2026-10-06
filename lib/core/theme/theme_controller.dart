import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/storage_service.dart';
import 'dark_theme.dart';
import 'light_theme.dart';

class ThemeController extends GetxController {
  final Rx<ThemeMode> themeMode = ThemeMode.light.obs;

  @override
  void onInit() {
    super.onInit();

    final saved = StorageService.themeMode;
    themeMode.value =
    saved == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  void toggleTheme() {
    if (themeMode.value == ThemeMode.light) {
      themeMode.value = ThemeMode.dark;
      StorageService.setThemeMode('dark');
    } else {
      themeMode.value = ThemeMode.light;
      StorageService.setThemeMode('light');
    }

    Get.changeThemeMode(themeMode.value);
  }

  ThemeData get lightTheme => AppThemeLight.theme;
  ThemeData get darkTheme => AppThemeDark.theme;
}
