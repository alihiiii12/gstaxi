import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../services/storage_service.dart';

class LocalizationController extends GetxController {
  final RxString locale = StorageService.language.obs;

  void changeLanguage(String langCode) {
    locale.value = langCode;
    StorageService.setLanguage(langCode);
    Get.updateLocale(Locale(langCode));
  }
}
