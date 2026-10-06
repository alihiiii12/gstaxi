import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/services/app_permissions_service.dart';

/// إعدادات تتبع الموقع للسائق.
/// بدون إشعار Geolocator الظاهر — الاعتماد على [DriverKeepaliveService] الصامت
/// لاستمرار العملية في الخلفية.
class DriverOnlineForeground {
  static LocationSettings onlineLocationSettings() {
    // بدون foregroundNotificationConfig: لا إشعار «متصل / موقع».
    return _liveMapSettings();
  }

  static LocationSettings mapLocationSettings() => _liveMapSettings();

  /// على أندرويد يجب تمرير intervalDuration صراحةً — الافتراضي 5 ثوانٍ فتقفز السيارة.
  static LocationSettings _liveMapSettings() {
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 1,
        pauseLocationUpdatesAutomatically: false,
        activityType: ActivityType.automotiveNavigation,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 1,
    );
  }

  /// تتبع العداد الحر — بدون إشعار ظاهر للعداد.
  static LocationSettings meterLocationSettings() {
    // distanceFilter يمنع إغراق العداد باهتزاز GPS عند التوقف التام.
    if (!kIsWeb && Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        intervalDuration: const Duration(seconds: 1),
      );
    }
    if (!kIsWeb && Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
        showBackgroundLocationIndicator: false,
        activityType: ActivityType.automotiveNavigation,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 5,
    );
  }

  static Future<bool> ensureMeterPermissions() =>
      AppPermissionsService.ensureForDriverTracking();

  static Future<bool> ensureLocationPermissions({bool forOnline = false}) async {
    if (forOnline) {
      return AppPermissionsService.ensureForDriverTracking();
    }
    return AppPermissionsService.ensureLocation(
      needAlways: false,
      reason: 'نحتاج موقعك لعرضك على الخريطة.',
    );
  }
}
