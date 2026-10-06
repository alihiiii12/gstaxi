import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

import 'push_notification_service.dart';

/// طلب الأذونات من داخل التطبيق، مع فتح الإعدادات عند الرفض النهائي
/// حتى لا يعلّق الجهاز على نوافذ النظام المتتالية.
class AppPermissionsService {
  AppPermissionsService._();

  static bool _coreFlowRunning = false;

  /// أذونات أساسية بعد دخول الشاشة الرئيسية (موقع + إشعارات).
  static Future<void> ensureCorePermissions({required bool forDriver}) async {
    if (kIsWeb || _coreFlowRunning) return;
    _coreFlowRunning = true;
    try {
      await ensureNotifications();
      await ensureLocation(
        needAlways: false,
        reason: forDriver
            ? 'نحتاج موقعك لعرضك على الخريطة واستقبال الطلبات القريبة.'
            : 'نحتاج موقعك لعرض نقطة الانطلاق وتتبع الرحلة.',
      );
      if (forDriver) {
        // طلب «طوال الوقت» بخطوة منفصلة مع شرح — يقلل التعليق على بعض الأجهزة.
        await ensureLocation(
          needAlways: true,
          reason:
              'لتبقى متصلاً وتستقبل الطلبات في الخلفية، فعّل الموقع «طوال الوقت».',
        );
        await ensureBatteryUnrestricted();
      }
    } finally {
      _coreFlowRunning = false;
    }
  }

  /// عند تفعيل «متصل» أو العداد — موقع دائم + خدمة الموقع.
  static Future<bool> ensureForDriverTracking() async {
    if (kIsWeb) return true;
    final locOk = await ensureLocation(
      needAlways: true,
      reason:
          'التتبع أثناء الاتصال يحتاج موقع «طوال الوقت» وخدمة الموقع مفعّلة.',
    );
    if (!locOk) return false;
    await ensureNotifications();
    await ensureBatteryUnrestricted();
    return true;
  }

  /// بدون قيود البطارية يبقى التتبع في الخلفية على أجهزة أندرويد.
  static Future<bool> ensureBatteryUnrestricted() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final status = await ph.Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return true;
      final proceed = await _promptContinue(
        title: 'تحسين البطارية',
        message:
            'لعمل التطبيق في الخلفية واستقبال الطلبات، اسمح بتجاهل تحسين البطارية لـ GS Taxi في الشاشة التالية.',
      );
      if (!proceed) return false;
      final result = await ph.Permission.ignoreBatteryOptimizations.request();
      if (result.isGranted) return true;
      await _promptOpenSettings(
        title: 'تحسين البطارية',
        message:
            'من إعدادات التطبيق → البطارية اختر «بدون قيود» أو عطّل تحسين البطارية لـ GS Taxi.',
      );
      return (await ph.Permission.ignoreBatteryOptimizations.status).isGranted;
    } catch (_) {
      return true;
    }
  }

  /// موقع الراكب (أثناء الاستخدام يكفي).
  static Future<bool> ensureForCustomerLocation() async {
    if (kIsWeb) return true;
    return ensureLocation(
      needAlways: false,
      reason: 'نحتاج موقعك لعرضك على الخريطة وتحديد نقطة الانطلاق.',
    );
  }

  static Future<bool> ensureNotifications() async {
    if (kIsWeb) return true;

    if (!kIsWeb && Platform.isAndroid) {
      final status = await ph.Permission.notification.status;
      if (status.isGranted) return true;
      if (status.isDenied) {
        final result = await ph.Permission.notification.request();
        if (result.isGranted) {
          await PushNotificationService.instance.requestPermissionAndSync();
          return true;
        }
        if (result.isPermanentlyDenied) {
          await _promptOpenSettings(
            title: 'إذن الإشعارات',
            message:
                'الإشعارات مطلوبة لاستقبال الطلبات والتنبيهات. افتح الإعدادات وفعّل الإشعارات للتطبيق.',
          );
          return (await ph.Permission.notification.status).isGranted;
        }
        return false;
      }
      if (status.isPermanentlyDenied) {
        await _promptOpenSettings(
          title: 'إذن الإشعارات',
          message:
              'الإشعارات مغلقة من الإعدادات. افتح الإعدادات وفعّل الإشعارات لـ GS Taxi.',
        );
        return (await ph.Permission.notification.status).isGranted;
      }
    }

    // iOS / باقي المنصات عبر Firebase
    return PushNotificationService.instance.requestPermissionAndSync();
  }

  static Future<bool> ensureLocation({
    required bool needAlways,
    required String reason,
  }) async {
    if (kIsWeb) return true;

    var serviceOn = await Geolocator.isLocationServiceEnabled();
    if (!serviceOn) {
      await _promptOpenSettings(
        title: 'خدمة الموقع مغلقة',
        message:
            'يجب تشغيل خدمة الموقع (GPS) من إعدادات الجهاز.\n\n$reason',
        openLocationSettings: true,
      );
      serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) return false;
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }

    if (perm == LocationPermission.denied) {
      await _promptOpenSettings(
        title: 'إذن الموقع',
        message: '$reason\n\nلم يتم منح الإذن. افتح الإعدادات وفعّل الموقع للتطبيق.',
      );
      perm = await Geolocator.checkPermission();
    }

    if (perm == LocationPermission.deniedForever) {
      await _promptOpenSettings(
        title: 'إذن الموقع مطلوب',
        message:
            '$reason\n\nالإذن مرفوض نهائياً. افتح إعدادات التطبيق → الأذونات → الموقع وفعّله.',
      );
      perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return false;
      }
    }

    if (!needAlways) {
      return perm == LocationPermission.always ||
          perm == LocationPermission.whileInUse;
    }

    if (perm == LocationPermission.always) return true;

    // شرح قبل طلب «طوال الوقت» حتى لا تتكدّس نوافذ النظام.
    final proceed = await _promptContinue(
      title: 'الموقع طوال الوقت',
      message:
          '$reason\n\nفي الشاشة التالية اختر «السماح طوال الوقت» أو «Always».',
    );
    if (!proceed) return perm == LocationPermission.whileInUse;

    final after = await Geolocator.requestPermission();
    if (after == LocationPermission.always) return true;

    await _promptOpenSettings(
      title: 'تفعيل الموقع طوال الوقت',
      message:
          'من إعدادات التطبيق → الموقع اختر «السماح طوال الوقت» حتى يستمر التتبع في الخلفية.',
    );
    final finalPerm = await Geolocator.checkPermission();
    return finalPerm == LocationPermission.always ||
        finalPerm == LocationPermission.whileInUse;
  }

  /// يطلب إذن الكاميرا فقط عند الحاجة.
  /// اختيار صورة من المعرض يتم عبر Android Photo Picker (image_picker)
  /// دون READ_MEDIA_IMAGES — مطلوب لسياسة Google Play.
  static Future<bool> ensureCameraAndPhotos() async {
    if (kIsWeb) return true;
    var cam = await ph.Permission.camera.status;
    if (cam.isDenied) cam = await ph.Permission.camera.request();
    if (cam.isPermanentlyDenied) {
      await _promptOpenSettings(
        title: 'إذن الكاميرا',
        message: 'لفتح الكاميرا لرفع الصور، فعّل إذن الكاميرا من الإعدادات.',
      );
      cam = await ph.Permission.camera.status;
    }

    // المعرض لا يحتاج إذن صور واسع؛ لا نمنع التدفق إن رُفضت الكاميرا فقط.
    return true;
  }

  static Future<bool> _promptContinue({
    required String title,
    required String message,
  }) async {
    final result = await Get.dialog<bool>(
      AlertDialog(
        title: Text(title, textAlign: TextAlign.right),
        content: Text(message, textAlign: TextAlign.right),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('لاحقاً'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC107),
              foregroundColor: const Color(0xFF11215B),
            ),
            child: const Text('متابعة'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    return result == true;
  }

  static Future<void> _promptOpenSettings({
    required String title,
    required String message,
    bool openLocationSettings = false,
  }) async {
    final go = await Get.dialog<bool>(
      AlertDialog(
        title: Text(title, textAlign: TextAlign.right),
        content: Text(message, textAlign: TextAlign.right),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('لاحقاً'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFC107),
              foregroundColor: const Color(0xFF11215B),
            ),
            child: const Text('فتح الإعدادات'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    if (go != true) return;
    if (openLocationSettings) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
    // امنح المستخدم وقتاً للعودة من الإعدادات
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }
}
