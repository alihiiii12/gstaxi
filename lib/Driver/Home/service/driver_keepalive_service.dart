import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/shared_pref.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/services/local_notification_service.dart';
import '../../../core/services/secure_auth_token.dart';
import '../../../core/utils/utf8_text.dart';

/// خدمة أمامية صامتة قدر الإمكان (أندرويد يفرض إشعاراً للخدمة الأمامية).
/// لا تُحدَّث بنص «آخر تحديث» ولا تعتمد على إشعار Geolocator الظاهر.
class DriverKeepaliveService {
  DriverKeepaliveService._();

  static const _kToken = 'driver_keepalive_token';
  static const _kApiBase = 'driver_keepalive_api_base';
  static const _kMode = 'driver_keepalive_mode';
  static const _kLastOfferId = 'driver_keepalive_last_offer_id';
  static const serviceId = 2601;

  /// قناة جديدة بأهمية منخفضة — القنوات القديمة تبقى بأهميتها السابقة على الجهاز.
  static const _silentChannelId = 'syriataxi_driver_silent_v2';

  static bool _initialized = false;

  static Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (_initialized) return;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _silentChannelId,
        channelName: 'تشغيل خلفي',
        channelDescription: 'مطلوب من النظام لاستمرار الموقع دون إزعاج',
        channelImportance: NotificationChannelImportance.MIN,
        priority: NotificationPriority.MIN,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        showBadge: false,
        onlyAlertOnce: true,
        visibility: NotificationVisibility.VISIBILITY_SECRET,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
        allowAutoRestart: true,
        stopWithTask: false,
      ),
    );
    _initialized = true;
  }

  static Future<void> ensureRunning({required bool meterActive}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    await init();

    // أندرويد 13+: بدون إذن الإشعار قد تُرفض الخدمة — نطلبه بهدوء دون الاعتماد عليه للعرض.
    final permission =
        await FlutterForegroundTask.checkNotificationPermission();
    if (permission != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    final token = await _resolveAuthToken();
    if (token == null || token.isEmpty) {
      debugPrint('DriverKeepaliveService: no token — skip start');
      return;
    }

    await FlutterForegroundTask.saveData(key: _kToken, value: token);
    await FlutterForegroundTask.saveData(
      key: _kApiBase,
      value: ApiEndpoints.baseUrl,
    );
    await FlutterForegroundTask.saveData(
      key: _kMode,
      value: meterActive ? 'meter' : 'online',
    );

    // نص ثابت قصير — بدون «آخر تحديث» وبدون إزعاج متكرر.
    const title = 'GS Taxi';
    const text = ' ';

    if (await FlutterForegroundTask.isRunningService) {
      FlutterForegroundTask.sendDataToTask(
        meterActive ? 'mode:meter' : 'mode:online',
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: serviceId,
      serviceTypes: [ForegroundServiceTypes.location],
      notificationTitle: title,
      notificationText: text,
      callback: driverKeepaliveStartCallback,
    );
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('DriverKeepaliveService.stop: $e');
    }
  }

  static Future<void> syncWithDriverState({
    required bool isOnline,
    required bool meterActive,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (isOnline || meterActive) {
      await ensureRunning(meterActive: meterActive);
    } else {
      await stop();
    }
  }

  static Future<String?> _resolveAuthToken() async {
    final secure = SecureAuthToken.value;
    if (secure != null && secure.isNotEmpty) return secure;
    try {
      final box = GetStorage();
      final fromBox = box.read<String>('token');
      if (fromBox != null && fromBox.isNotEmpty) return fromBox;
    } catch (_) {}
    try {
      final fromPrefs = await MyInfoPrefs.getInfo(name: 'token');
      if (fromPrefs != null && fromPrefs.isNotEmpty) return fromPrefs;
    } catch (_) {}
    return null;
  }
}

@pragma('vm:entry-point')
void driverKeepaliveStartCallback() {
  FlutterForegroundTask.setTaskHandler(_DriverKeepaliveTaskHandler());
}

class _DriverKeepaliveTaskHandler extends TaskHandler {
  String _mode = 'online';
  int _tick = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();
    final mode = await FlutterForegroundTask.getData<String>(
      key: DriverKeepaliveService._kMode,
    );
    if (mode != null && mode.isNotEmpty) _mode = mode;
    await _pushLocationOnce();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(_pushLocationOnce());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}

  @override
  void onReceiveData(Object data) {
    if (data is String && data.startsWith('mode:')) {
      _mode = data.substring(5);
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }

  Future<void> _pushLocationOnce() async {
    try {
      final token = await FlutterForegroundTask.getData<String>(
        key: DriverKeepaliveService._kToken,
      );
      final apiBase = await FlutterForegroundTask.getData<String>(
        key: DriverKeepaliveService._kApiBase,
      );
      if (token == null ||
          token.isEmpty ||
          apiBase == null ||
          apiBase.isEmpty) {
        return;
      }

      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
      if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;

      final uri = Uri.parse('$apiBase/drivers/updateLocation');
      final res = await http
          .post(
            uri,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'latitude': pos.latitude,
              'longitude': pos.longitude,
              'heading': pos.heading.isFinite ? pos.heading : 0,
              'speed': pos.speed.isFinite ? pos.speed : 0,
              'keepalive': true,
              'mode': _mode,
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint(
          'keepalive updateLocation: ${res.statusCode} ${res.body}',
        );
      }

      // كل ~30 ثانية: استطلاع طلبات فورية وإشعار محلي (حتى والجهاز مقفول).
      _tick++;
      if (_mode == 'online' && _tick % 2 == 0) {
        await _pollImmediateOffers(apiBase: apiBase, token: token);
      }
    } catch (e) {
      debugPrint('keepalive push: $e');
    }
  }

  Future<void> _pollImmediateOffers({
    required String apiBase,
    required String token,
  }) async {
    try {
      final res = await http
          .get(
            Uri.parse('$apiBase/requests/immediate-pending'),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode < 200 || res.statusCode >= 300) return;

      final decoded = decodeJsonUtf8(res);
      if (decoded is! Map || decoded['success'] != true) return;
      final raw = decoded['data'];
      if (raw is! List || raw.isEmpty) return;

      Map<String, dynamic>? first;
      for (final e in raw) {
        if (e is Map) {
          first = Map<String, dynamic>.from(e);
          break;
        }
      }
      if (first == null) return;

      final rid = int.tryParse(first['id']?.toString() ?? '') ?? 0;
      if (rid <= 0) return;

      final last = await FlutterForegroundTask.getData<String>(
        key: DriverKeepaliveService._kLastOfferId,
      );
      // قائمة معرفات مُنبَّه عنها مفصولة بفاصلة — لمنع التكرار.
      final notified = <int>{
        for (final p in (last ?? '').split(','))
          if (int.tryParse(p.trim()) != null) int.parse(p.trim()),
      };
      if (notified.contains(rid)) return;
      notified.add(rid);
      while (notified.length > 40) {
        notified.remove(notified.first);
      }
      await FlutterForegroundTask.saveData(
        key: DriverKeepaliveService._kLastOfferId,
        value: notified.join(','),
      );

      final pickup = first['startLocationName']?.toString() ??
          first['pickup_name']?.toString() ??
          'موقع الانطلاق';
      await LocalNotificationService.showRideOffer(
        title: 'طلب جديد',
        body: pickup,
        requestId: rid,
        payload: {
          'kind': 'immediate_request',
          'request_id': rid,
          'title': 'طلب جديد',
          'body': pickup,
        },
      );
    } catch (e) {
      debugPrint('keepalive poll offers: $e');
    }
  }
}
