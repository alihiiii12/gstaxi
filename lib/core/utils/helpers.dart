import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../constants/app_sizes.dart';
import '../constants/snack_bar.dart';
import '../localization/l.dart';
import '../services/storage_service.dart';

class AppHelpers {
  AppHelpers._();

  // =========================
  // 🧠 LOGGING
  // =========================

  static void logInfo(String message, {String tag = 'INFO'}) {
    log('[$tag] $message');
  }

  static void logError(String message, {String tag = 'ERROR'}) {
    log('[$tag] $message');
  }

  // =========================
  // 📱 DEVICE & SCREEN
  // =========================

  static bool get isLoggedIn => StorageService.isLoggedIn;

  static double get screenWidth => AppSizes.screenWidth;
  static double get screenHeight => AppSizes.screenHeight;

  // =========================
  // 🔔 SNACKBARS (موحّدة)
  // =========================

  static void successSnack(String message) {
    AppSnackBar.success(message, title: L.appName);
  }

  static void errorSnack(String message) {
    AppSnackBar.error(message, title: L.appName);
  }

  // =========================
  // ⏳ LOADING DIALOG
  // =========================

  static void showLoading() {
    if (Get.isDialogOpen == true) return;

    Get.dialog(
      const Center(
        child: CircularProgressIndicator(),
      ),
      barrierDismissible: false,
    );
  }

  static void hideLoading() {
    if (Get.isDialogOpen == true) {
      Get.back();
    }
  }

  // =========================
  // 🧭 NAVIGATION HELPERS
  // =========================

  static void goTo(String route) {
    Get.toNamed(route);
  }

  static void goOffAll(String route) {
    Get.offAllNamed(route);
  }

  static void goBack() {
 Get.back();
  }

  // =========================
  // 🔑 AUTH HELPERS
  // =========================

  static void logout() async {
    await StorageService.logout();
    goOffAll('/login');
  }

  // =========================
  // 🧪 VALIDATION QUICK CHECK
  // =========================

  static bool isEmail(String email) {
    return RegExp(
      r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
    ).hasMatch(email);
  }

  static bool isPhone(String phone) {
    return RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone);
  }

  // =========================
  // 🧩 UI SHORTCUTS
  // =========================

  static Widget spacerH(double px) =>
      SizedBox(height: AppSizes.h(px));

  static Widget spacerW(double px) =>
      SizedBox(width: AppSizes.w(px));
}
