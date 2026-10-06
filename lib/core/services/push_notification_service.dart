import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../../Customer/controller/customer_active_trip_controller.dart';
import '../../Driver/Home/controller/driver_assigned_trip_controller.dart';
import '../../Driver/Home/controller/driver_location_controller.dart';
import '../../Driver/Home/service/driver_server_sync_service.dart';
import '../../firebase_options.dart';
import '../network/api_endpoints.dart';
import '../network/api_queue_worker.dart';
import '../services/secure_auth_token.dart';
import '../utils/app_alert_sound.dart';
import 'local_notification_service.dart';
import 'trip_push_events.dart';

/// معالج الرسائل عندما يكون التطبيق في الخلفية (مطلوب كدالة عليا).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM background] ${message.messageId} ${message.data}');
  // عرض في شريط النظام — بعض الأجهزة لا تعرض إشعار FCM النظامي بعد إغلاق التطبيق.
  await LocalNotificationService.showInBackground(message);
}

/// Push أولاً (حالات الرحلة) — الاستطلاع الدوري احتياطي فقط.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  FirebaseMessaging? _messaging;
  String? _lastToken;
  bool _listenersBound = false;

  String? get lastToken => _lastToken;

  Future<void> init() async {
    if (!DefaultFirebaseOptions.isConfigured) {
      debugPrint(
        '[FCM] Skipped: edit lib/firebase_options.dart with your Firebase Android app values.',
      );
      return;
    }

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    _messaging = FirebaseMessaging.instance;
    final messaging = _messaging!;

    await messaging.setAutoInitEnabled(true);

    await LocalNotificationService.ensureInitialized();

    final settings = await messaging.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _syncToken();
    } else {
      // أندرويد 13+: بدون إذن لا تظهر الإشعارات خارج التطبيق.
      final req = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (req.authorizationStatus == AuthorizationStatus.authorized ||
          req.authorizationStatus == AuthorizationStatus.provisional) {
        await _syncToken();
      }
    }

    messaging.onTokenRefresh.listen((t) async {
      _lastToken = t;
      await _sendTokenToBackend(t);
    });

    if (!_listenersBound) {
      _listenersBound = true;
      FirebaseMessaging.onMessage.listen(_onForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);
      // فتح من إشعار والتطبيق مغلق.
      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        _dispatchTripPush(initial.data, showSnack: false);
      }
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    _dispatchTripPush(message.data, showSnack: false);
    unawaited(AppAlertSound.playForPushData(message.data));
    // إشعار واحد فقط — بدون سناك مكرر لنفس الرسالة.
    if (!_shouldSkipDuplicatePush(message.data)) {
      unawaited(
        LocalNotificationService.showFromRemoteMessage(message, silent: true),
      );
    }
    final n = message.notification;
    final title = n?.title ?? message.data['title']?.toString() ?? '';
    final body = n?.body ?? message.data['body']?.toString() ?? '';
    debugPrint('[FCM foreground] $title $body ${message.data}');
  }

  static final Map<String, DateTime> _recentPushKeys = {};

  bool _shouldSkipDuplicatePush(Map<String, dynamic> data) {
    final event = TripPushEvent.parse(data);
    final key =
        '${event.kind.name}:${event.requestId ?? data['title']}:${data['body']}';
    final now = DateTime.now();
    _recentPushKeys.removeWhere(
      (_, t) => now.difference(t) > const Duration(seconds: 45),
    );
    final last = _recentPushKeys[key];
    if (last != null && now.difference(last) < const Duration(seconds: 20)) {
      return true;
    }
    _recentPushKeys[key] = now;
    return false;
  }

  void _onMessageOpened(RemoteMessage message) {
    _dispatchTripPush(message.data, showSnack: false);
  }

  /// نقطة دخول موحّدة لكل payload رحلة (FCM أو اختبار).
  void _dispatchTripPush(
    Map<String, dynamic> data, {
    bool showSnack = false,
  }) {
    final event = TripPushEvent.parse(data);
    debugPrint(
      '[FCM trip] kind=${event.kind} raw=${event.rawKind} rid=${event.requestId}',
    );

    if (event.isDriverRelevant) {
      _refreshDriverFromPush(event);
    }
    if (event.isCustomerRelevant) {
      _refreshCustomerFromPush(event);
    }
  }

  void _refreshDriverFromPush(TripPushEvent event) {
    try {
      final hasDriver = Get.isRegistered<DriverController>();
      if (!hasDriver) return;

      final dc = Get.find<DriverController>();

      // طلب فوري: مزامنة فورية إن كان متصلاً.
      if (event.kind == TripPushEventKind.immediateOffer) {
        if (!dc.isOnline.value) return;
        _enqueueDriverSync(key: 'push_immediate');
        return;
      }

      // باقي أحداث الرحلة: حدّث حتى لو كان offline جزئياً (رحلة جارية).
      _enqueueDriverSync(key: 'push_trip_${event.kind.name}');
      if (Get.isRegistered<DriverAssignedTripController>()) {
        ApiQueueWorker.instance.enqueue(
          () async {
            await Get.find<DriverAssignedTripController>().pollAssignedRequests();
          },
          key: 'push_assigned_${event.kind.name}',
          coalesce: true,
          maxAttempts: 2,
        );
      }
      dc.onAppResumedFromBackground();
    } catch (e) {
      debugPrint('[FCM] driver refresh failed: $e');
    }
  }

  void _enqueueDriverSync({required String key}) {
    if (!Get.isRegistered<DriverServerSyncService>()) return;
    ApiQueueWorker.instance.enqueue(
      () async {
        await Get.find<DriverServerSyncService>().syncNow(force: true);
      },
      key: key,
      coalesce: true,
      maxAttempts: 2,
    );
  }

  void _refreshCustomerFromPush(TripPushEvent event) {
    try {
      if (!Get.isRegistered<CustomerActiveTripController>()) return;
      ApiQueueWorker.instance.enqueue(
        () async {
          await Get.find<CustomerActiveTripController>().onPushTripEvent(event);
        },
        key: 'push_customer_${event.kind.name}',
        coalesce: true,
        maxAttempts: 2,
      );
    } catch (e) {
      debugPrint('[FCM] customer refresh failed: $e');
    }
  }

  /// يُستدعى من [AppPermissionsService] بعد ظهور الواجهة.
  Future<bool> requestPermissionAndSync() async {
    if (!DefaultFirebaseOptions.isConfigured) return false;
    if (_messaging == null) {
      await init();
    }
    final messaging = _messaging;
    if (messaging == null) return false;

    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final ok = settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (ok) await _syncToken();
    return ok;
  }

  Future<void> _syncToken() async {
    final messaging = _messaging;
    if (messaging == null) return;
    try {
      final t = await messaging.getToken();
      if (t == null || t.isEmpty) return;
      _lastToken = t;
      await GetStorage().write('fcm_token', t);
      await _sendTokenToBackend(t);
    } catch (e, st) {
      debugPrint('[FCM] getToken failed: $e $st');
    }
  }

  Future<void> registerTokenIfLoggedIn() async {
    if (!DefaultFirebaseOptions.isConfigured) return;
    if (Firebase.apps.isEmpty) return;

    final token = SecureAuthToken.value;
    if (token == null || token.isEmpty) return;

    String? t = _lastToken;
    t ??= await FirebaseMessaging.instance.getToken();
    if (t == null || t.isEmpty) return;
    await _sendTokenToBackend(t);
  }

  Future<void> _sendTokenToBackend(String t) async {
    final headers = await ApiEndpoints.headers();
    if (!headers.containsKey('Authorization')) return;
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.userFcmToken),
        headers: headers,
        body: jsonEncode({'fcm_token': t}),
      );
      debugPrint('[FCM] register on server: ${res.statusCode} ${res.body}');
    } catch (e) {
      debugPrint('[FCM] register on server failed: $e');
    }
  }
}
