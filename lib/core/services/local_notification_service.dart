import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../constants/android_notification_channels.dart';
import 'trip_push_events.dart';

/// عرض إشعار محلي — ضروري عندما يكون التطبيق في الخلفية/مغلقاً
/// أو عندما تصل رسالة data فقط.
class LocalNotificationService {
  LocalNotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> ensureInitialized() async {
    if (_ready) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    for (final id in AndroidNotificationChannels.legacyIds) {
      try {
        await androidPlugin?.deleteNotificationChannel(id);
      } catch (_) {}
    }
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        AndroidNotificationChannels.fcmId,
        AndroidNotificationChannels.fcmName,
        description: 'طلبات رحلات، حجز مسبق، وتنبيهات التطبيق',
        importance: Importance.high,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(
          AndroidNotificationChannels.notifySound,
        ),
        enableVibration: true,
      ),
    );
    // قناة طلبات فورية — أهمية قصوى حتى يرن على شاشة القفل.
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        AndroidNotificationChannels.rideOffersId,
        AndroidNotificationChannels.rideOffersName,
        description: 'طلبات فورية للسائق — رنين على شاشة القفل',
        importance: Importance.max,
        playSound: true,
        sound: RawResourceAndroidNotificationSound(
          AndroidNotificationChannels.ringtoneSound,
        ),
        enableVibration: true,
      ),
    );
    await androidPlugin?.requestNotificationsPermission();

    _ready = true;
  }

  static bool _isRideOfferData(Map<String, dynamic> data) {
    final event = TripPushEvent.parse(data);
    return event.kind == TripPushEventKind.immediateOffer;
  }

  /// [silent]: بدون صوت من النظام (التطبيق في الواجهة ويشغّل النغمة بنفسه).
  static Future<void> showFromRemoteMessage(
    RemoteMessage message, {
    bool silent = false,
  }) async {
    await ensureInitialized();
    final data = Map<String, dynamic>.from(message.data);
    if (_isRideOfferData(data)) {
      await showRideOffer(
        title: message.notification?.title ??
            data['title']?.toString() ??
            'طلب جديد',
        body: message.notification?.body ??
            data['body']?.toString() ??
            'لديك طلب رحلة فوري',
        requestId: eventRequestId(data),
        payload: data,
        silent: silent,
      );
      return;
    }

    final title = message.notification?.title ??
        data['title']?.toString() ??
        'إشعار';
    final body = message.notification?.body ?? data['body']?.toString() ?? '';
    if (title.isEmpty && body.isEmpty) return;

    final id = message.messageId?.hashCode.abs() ??
        DateTime.now().millisecondsSinceEpoch.remainder(100000);

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          AndroidNotificationChannels.fcmId,
          AndroidNotificationChannels.fcmName,
          channelDescription: 'طلبات رحلات، حجز مسبق، وتنبيهات التطبيق',
          importance: Importance.high,
          priority: Priority.high,
          playSound: !silent,
          silent: silent,
          sound: const RawResourceAndroidNotificationSound(
            AndroidNotificationChannels.notifySound,
          ),
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(data),
    );
  }

  static int? eventRequestId(Map<String, dynamic> data) {
    return TripPushEvent.parse(data).requestId;
  }

  /// إشعار طلب فوري — يرن ويظهر على شاشة القفل.
  static Future<void> showRideOffer({
    required String title,
    required String body,
    int? requestId,
    Map<String, dynamic>? payload,
    bool silent = false,
  }) async {
    await ensureInitialized();
    final id = requestId != null && requestId > 0
        ? (900000 + (requestId % 90000))
        : DateTime.now().millisecondsSinceEpoch.remainder(100000);

    await _plugin.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          AndroidNotificationChannels.rideOffersId,
          AndroidNotificationChannels.rideOffersName,
          channelDescription: 'طلبات فورية للسائق — رنين على شاشة القفل',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          visibility: NotificationVisibility.public,
          playSound: !silent,
          silent: silent,
          sound: const RawResourceAndroidNotificationSound(
            AndroidNotificationChannels.ringtoneSound,
          ),
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
          ticker: 'طلب رحلة جديد',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: jsonEncode(payload ?? {'kind': 'immediate_request'}),
    );
  }

  /// من معالج الخلفية (isolate منفصل).
  static Future<void> showInBackground(RemoteMessage message) async {
    try {
      await ensureInitialized();
      await showFromRemoteMessage(message);
    } catch (e, st) {
      debugPrint('[local-notif bg] $e\n$st');
    }
  }
}
