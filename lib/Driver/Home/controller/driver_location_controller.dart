import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:syriataxi/core/constants/driver_poll_intervals.dart';
import 'package:syriataxi/core/constants/snack_bar.dart';
import 'package:syriataxi/core/network/http_timeouts.dart';
import 'package:syriataxi/core/utils/utf8_text.dart';
import 'package:syriataxi/core/network/api_endpoints.dart';
import 'package:syriataxi/core/services/secure_auth_token.dart';
import 'package:syriataxi/core/services/sos_live_reporter.dart';
import 'package:syriataxi/core/services/pricing_zone_map.dart';
import 'package:syriataxi/core/utils/trip_location_helpers.dart';
import 'package:syriataxi/core/services/trip_api_service.dart';
import 'package:syriataxi/core/utils/category_trip_fare_client.dart';
import 'package:syriataxi/core/utils/safe_lat_lng.dart';
import 'package:syriataxi/Driver/Home/service/driver_keepalive_service.dart';
import 'package:syriataxi/Driver/Home/service/driver_online_foreground.dart';
import 'package:syriataxi/Driver/Home/service/driver_server_sync_service.dart';
import 'package:syriataxi/Driver/Home/service/free_meter_engine.dart';
import 'package:syriataxi/core/utils/phone_call_launcher.dart';

class DriverController extends GetxController with WidgetsBindingObserver {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<Position>? _deviceLocationStream;
  StreamSubscription<CompassEvent>? _compassSub;
  double? _compassHeading;
  double? _gpsCourseHeading;

  var isOnline = false.obs;
  var currentPosition = kDefaultMapCenter.obs;
  /// Device heading in degrees (0..360). Used to rotate map.
  final currentHeading = 0.0.obs;
  /// السرعة الحالية كم/س للعرض أثناء التنقّل.
  final currentSpeedKph = 0.0.obs;
  var totalFare = 0.0.obs;
  var isMoving = false.obs;
  Timer? fareTimer;
  double lastLat = 0.0;
  double lastLng = 0.0;
  var elapsedTime = 0.obs;
  Stopwatch stopwatch = Stopwatch();

  /// العداد الحر فقط (يُستعاد من التخزين بعد إعادة فتح التطبيق).
  var isTripActive = false.obs;
  /// عداد رحلة التطبيق — منفصل عن العداد الحر.
  var isAppTripMeterActive = false.obs;

  bool get isAnyMeterActive =>
      isTripActive.value || isAppTripMeterActive.value;

  /// الأجرة المعروضة والمرسلة = [meterBaseCost] × معامل منطقة التسعير.
  var meterCost = 0.0.obs;
  /// أجرة محرّك العداد قبل معامل المنطقة.
  final meterBaseCost = 0.0.obs;
  final meterZoneMultiplier = 1.0.obs;
  /// «تسعيرة مدينة دمشق ← الريف ×1.25» أو فارغ إن كان المعامل 1.
  final meterZoneLabel = ''.obs;
  /// نقطة بداية العداد لتحديد منطقة الانطلاق.
  LatLng? _meterZoneStart;
  static const _kMeterZoneStartLat = 'meter_zone_start_lat';
  static const _kMeterZoneStartLng = 'meter_zone_start_lng';
  var distanceTraveled = 0.0.obs;
  var waitingSeconds = 0.obs;
  /// ثوانٍ منذ بدء العداد (للعرض MM:SS).
  var meterElapsedSeconds = 0.obs;
  /// دقائق وقوف مُضافة للتكلفة.
  var meterBilledMinutes = 0.obs;
  var connectionStatus = 'connected'.obs;
  /// آخر مزامنة ناجحة لأسعار العداد من لوحة التحكم.
  final meterPricingSynced = false.obs;
  final meterPricingUpdatedAt = Rxn<DateTime>();
  /// طلب التطبيق الذي يعمل عليه العداد (Running).
  final appTripMeterRequestId = Rxn<int>();
  /// معرّف طلب العداد الحر على السيرفر.
  final freeMeterRequestId = Rxn<int>();

  /// من إعدادات لوحة التحكم (`/admin/free-meter-settings` → `/drivers/me/free-meter-pricing`).
  final baseFare = 0.0.obs;
  final pricePerKm = 0.0.obs;
  final pricePerMinute = 0.0.obs;

  static const _kOpen = 'free_meter_open';
  static const _kKm = 'free_meter_km';
  static const _kTime = 'free_meter_time';
  /// كان السائق متصلاً قبل العداد الحر — يُستأنف بعد الإيقاف.
  static const _kResumeOnlineAfterFreeMeter = 'free_meter_resume_online';
  /// إنهاء عداد حر معلّق (انقطع النت عند الإيقاف) — يُرفع عند عودة الاتصال.
  static const _kPendingFreeMeterFinish = 'pending_free_meter_finish';
  bool _flushingPendingFreeMeterFinish = false;

  /// نطاق استقبال الطلبات عن الزبون (1 / 2 / 3 كم).
  final receiveRadiusKm = 1.obs;
  static const _kReceiveRadius = 'driver_receive_radius_km';
  static const receiveRadiusOptions = [1, 2, 3];

  FreeMeterEngine? _meter;

  DateTime? lastUpdateTime;

  Timer? waitingTimer;
  StreamSubscription<Position>? positionStream;
  /// تتبع مع خدمة أمامية عند «متصل» — يبقى نشطاً في الخلفية.
  StreamSubscription<Position>? _onlineLocationStream;
  Position? lastPosition;
  Timer? _tripTimer;
  /// يبقي مفتاح Redis `driver:*:online` حياً حتى لو توقف GPS عن إرسال تحديثات (سائق ثابت).
  Timer? _onlineLocationHeartbeat;
  Timer? _immediateSyncAfterLocationDebounce;
  DateTime? _lastLocationTriggeredSync;
  Timer? _meterPricingRefreshTimer;
  Timer? _appMeterUploadDebounce;
  DateTime? _lastAppMeterUploadAt;
  double _lastUploadedMeterCost = -1;
  double _lastUploadedMeterKm = -1;
  int _lastUploadedWaitMin = -1;
  int _lastUploadedWaitSec = -1;

  static const Duration _meterPricingRefreshInterval = Duration(seconds: 45);

  RxString token = "".obs;
  final box = GetStorage();

  /// يُزاد بعد قبول طلب من شاشة «الطلبات» أو الحوار لتُحدَّث الخريطة والطلب المعيّن فوراً.
  final assignRefreshSignal = 0.obs;

  /// قبول فوري من الخادم قد يُنشئ عرضاً فقط (`awaiting_passenger_choice`) دون `driverId` على الطلب؛
  /// تا أن يظهر الطلب في `driverRequests` نعرض موقع الراكب من نسخة الطلب المحلية.
  final Rx<Map<String, dynamic>?> acceptedTripPreview = Rx<Map<String, dynamic>?>(null);

  /// يُعيَّن من [DriverHomeScreen] لاستدعاء `_pollAssignedRequests` مباشرة (أقوى من الاعتماد على `ever` فقط).
  VoidCallback? onAssignedTripUiRefresh;

  /// تحديث الخريطة فوراً من شاشة الطلبات — لا يعتمد على نجاح `driverRequests` أو وجود `driver_id`.
  void Function(Map<String, dynamic>)? onApplyTripPreviewUi;

  void notifyAssignedTripRefresh() {
    assignRefreshSignal.value++;
  }

  void setAcceptedTripPreview(Map<String, dynamic> order) {
    final copy = Map<String, dynamic>.from(order);
    acceptedTripPreview.value = copy;
    onApplyTripPreviewUi?.call(copy);
    notifyAssignedTripRefresh();
  }

  /// يُربَط من [DriverAssignedTripController] لمسح واجهة طلب التطبيق عند بدء العداد الحر.
  void Function()? clearAppTripUiForFreeMeter;

  void clearAcceptedTripPreview() {
    acceptedTripPreview.value = null;
  }

  void clearAcceptedTripPreviewIfIdsMatch(int requestId) {
    final p = acceptedTripPreview.value;
    final pid = int.tryParse(p?['id']?.toString() ?? '') ?? 0;
    if (pid == requestId) {
      acceptedTripPreview.value = null;
    }
  }

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    SosLiveReporter.instance.resumeIfActive();
    unawaited(PricingZoneMap.instance.refresh());
    setupConnectionListener();
    _loadCachedPricing();
    _loadReceiveRadiusLocal();
    _loadState();
    _setupPersistence();
    unawaited(fetchPricingFromServer());
    unawaited(fetchReceiveRadiusFromServer());
    _startMeterPricingSyncLoop();
    _startLiveDeviceLocation();
    _startCompassHeading();
  }

  void _loadReceiveRadiusLocal() {
    final raw = box.read(_kReceiveRadius);
    final km = int.tryParse('$raw') ?? 1;
    receiveRadiusKm.value = receiveRadiusOptions.contains(km) ? km : 1;
  }

  Future<void> fetchReceiveRadiusFromServer() async {
    try {
      final r = await TripApiService.fetchDriverReceiveRadius();
      if (!r.ok) return;
      final data = r.dataMap ?? {};
      final km = int.tryParse('${data['receive_radius_km']}') ??
          receiveRadiusKm.value;
      if (receiveRadiusOptions.contains(km)) {
        receiveRadiusKm.value = km;
        box.write(_kReceiveRadius, km);
      }
    } catch (_) {}
  }

  /// تبديل سريع: 1 → 2 → 3 → 1
  Future<void> cycleReceiveRadius() async {
    final opts = receiveRadiusOptions;
    final i = opts.indexOf(receiveRadiusKm.value);
    final next = opts[(i < 0 ? 0 : i + 1) % opts.length];
    await setReceiveRadiusKm(next);
  }

  Future<bool> setReceiveRadiusKm(int km) async {
    if (!receiveRadiusOptions.contains(km)) return false;
    final prev = receiveRadiusKm.value;
    receiveRadiusKm.value = km;
    box.write(_kReceiveRadius, km);
    final r = await TripApiService.updateDriverReceiveRadius(km);
    if (!r.ok) {
      receiveRadiusKm.value = prev;
      box.write(_kReceiveRadius, prev);
      AppSnackBar.notify(
        'نطاق الاستقبال',
        r.message ?? 'تعذر حفظ النطاق',
      );
      return false;
    }
    AppSnackBar.notify(
      'نطاق الاستقبال',
      'ستصلك الطلبات ضمن $km كم من الزبون',
    );
    return true;
  }

  /// بوصلة الجهاز — مثل سهم Google Maps (تدوز مع تدوير الهاتف حتى عند التوقف).
  void _startCompassHeading() {
    _compassSub?.cancel();
    final events = FlutterCompass.events;
    if (events == null) return;
    _compassSub = events.listen((event) {
      final h = event.heading;
      if (h == null || !h.isFinite) return;
      _compassHeading = (h + 360) % 360;
      _publishBlendedHeading();
    });
  }

  void _publishBlendedHeading() {
    final speedMps = currentSpeedKph.value / 3.6;
    // أثناء الحركة نعتمد اتجاه المسار؛ عند التوقف/البطء نعتمد البوصلة.
    if (speedMps > 1.4 &&
        _gpsCourseHeading != null &&
        _gpsCourseHeading!.isFinite) {
      currentHeading.value = _gpsCourseHeading!;
    } else if (_compassHeading != null && _compassHeading!.isFinite) {
      currentHeading.value = _compassHeading!;
    } else if (_gpsCourseHeading != null && _gpsCourseHeading!.isFinite) {
      currentHeading.value = _gpsCourseHeading!;
    }
  }

  DateTime? _lastLocationPostAt;
  static const Duration _locationPostMinGap = Duration(seconds: 2);

  void _applyPositionToUi(Position pos, {bool postToServer = false}) {
    if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;
    final next = LatLng(pos.latitude, pos.longitude);
    final prev = currentPosition.value;
    currentPosition.value = next;

    final h = pos.heading;
    final sp = pos.speed;
    if (sp.isFinite && sp >= 0) {
      currentSpeedKph.value = sp * 3.6;
    }
    // اتجاه الحركة من GPS عند السرعة الكافية.
    if (h.isFinite && h >= 0 && h <= 360 && sp.isFinite && sp > 0.35) {
      _gpsCourseHeading = h;
    } else if (isFiniteLatLng(prev) &&
        (prev.latitude != next.latitude || prev.longitude != next.longitude)) {
      final moved = Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        next.latitude,
        next.longitude,
      );
      if (moved >= 2.5) {
        final bearing = Geolocator.bearingBetween(
          prev.latitude,
          prev.longitude,
          next.latitude,
          next.longitude,
        );
        if (bearing.isFinite) {
          _gpsCourseHeading = (bearing + 360) % 360;
        }
      }
    }
    _publishBlendedHeading();

    if (postToServer && isOnline.value) {
      final now = DateTime.now();
      final last = _lastLocationPostAt;
      if (last == null || now.difference(last) >= _locationPostMinGap) {
        _lastLocationPostAt = now;
        unawaited(updateLocationOnServer(pos));
      }
    }
    if (isAnyMeterActive) {
      _onMeterGps(pos);
    }
  }

  Future<void> _startLiveDeviceLocation() async {
    if (isOnline.value || isAnyMeterActive) return;
    try {
      final ok = await DriverOnlineForeground.ensureLocationPermissions();
      if (!ok) return;

      await bootstrapCurrentLocation();
      // العداد له تدفّقه الخاص (يغذي الخريطة أيضاً).
      if (isOnline.value || isAnyMeterActive) return;

      _deviceLocationStream?.cancel();
      _deviceLocationStream = Geolocator.getPositionStream(
        locationSettings: DriverOnlineForeground.mapLocationSettings(),
      ).listen((pos) => _applyPositionToUi(pos));
    } catch (e) {
      debugPrint('_startLiveDeviceLocation: $e');
    }
  }

  /// قراءة فورية للموقع عند فتح التطبيق (آخر معروف ثم الحالي).
  Future<void> bootstrapCurrentLocation() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null &&
          last.latitude.isFinite &&
          last.longitude.isFinite) {
        currentPosition.value = LatLng(last.latitude, last.longitude);
      }
    } catch (_) {}
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (pos.latitude.isFinite && pos.longitude.isFinite) {
        _applyPositionToUi(pos);
      }
    } catch (e) {
      debugPrint('bootstrapCurrentLocation: $e');
    }
  }

  Future<void> _startOnlineLocationTracking() async {
    if (isAnyMeterActive) {
      await _startMeterLocationTracking();
      return;
    }
    try {
      final ok = await DriverOnlineForeground.ensureLocationPermissions(
        forOnline: true,
      );
      if (!ok) {
        AppSnackBar.notify(
          'الموقع',
          'يُرجى السماح بالوصول إلى الموقع لتفعيل وضع «متصل»',
        );
        isOnline.value = false;
        _onlineLocationHeartbeat?.cancel();
        _onlineLocationHeartbeat = null;
        return;
      }

      _deviceLocationStream?.cancel();
      _deviceLocationStream = null;
      _onlineLocationStream?.cancel();
      _onlineLocationStream = Geolocator.getPositionStream(
        locationSettings: DriverOnlineForeground.onlineLocationSettings(),
      ).listen((pos) => _applyPositionToUi(pos, postToServer: true));

      final perm = await Geolocator.checkPermission();
      if (!kIsWeb &&
          Platform.isAndroid &&
          perm == LocationPermission.whileInUse) {
        AppSnackBar.notify(
          'للعمل في الخلفية',
          'فعّل الموقع «طوال الوقت» من الإعدادات',
          duration: const Duration(seconds: 8),
          mainButton: TextButton(
            onPressed: () => Geolocator.openAppSettings(),
            child: const Text(
              'فتح الإعدادات',
              style: TextStyle(color: Color(0xFFFFC107)),
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('_startOnlineLocationTracking: $e');
    }
  }

  void _stopOnlineLocationTracking() {
    _onlineLocationStream?.cancel();
    _onlineLocationStream = null;
    unawaited(_startLiveDeviceLocation());
  }

  void _loadCachedPricing() {
    final open = box.read(_kOpen);
    final km = box.read(_kKm);
    final time = box.read(_kTime);
    if (open is num) baseFare.value = open.toDouble();
    if (km is num && km.toDouble() > 0) pricePerKm.value = km.toDouble();
    if (time is num && time.toDouble() > 0) pricePerMinute.value = time.toDouble();
    final updatedAtRaw = box.read('free_meter_updated_at');
    if (updatedAtRaw is String && updatedAtRaw.isNotEmpty) {
      meterPricingUpdatedAt.value = DateTime.tryParse(updatedAtRaw);
    }
    meterPricingSynced.value = hasValidMeterPricing;
  }

  void _persistPricing() {
    box.write(_kOpen, baseFare.value);
    box.write(_kKm, pricePerKm.value);
    box.write(_kTime, pricePerMinute.value);
    final updatedAt = meterPricingUpdatedAt.value;
    if (updatedAt != null) {
      box.write('free_meter_updated_at', updatedAt.toIso8601String());
    }
  }

  void _applyPricingMap(Map<String, double> p) {
    final changed = baseFare.value != p['openPrice']! ||
        pricePerKm.value != p['kmPrice']! ||
        pricePerMinute.value != p['timePrice']!;
    baseFare.value = p['openPrice']!;
    if (p['kmPrice']! > 0) pricePerKm.value = p['kmPrice']!;
    if (p['timePrice']! > 0) pricePerMinute.value = p['timePrice']!;
    meterPricingUpdatedAt.value = DateTime.now();
    _persistPricing();
    meterPricingSynced.value = hasValidMeterPricing;
    if (changed) {
      _rebuildMeterEngineIfActive();
    }
  }

  void _startMeterPricingSyncLoop() {
    _meterPricingRefreshTimer?.cancel();
    _meterPricingRefreshTimer = Timer.periodic(
      _meterPricingRefreshInterval,
      (_) {
        final token = SecureAuthToken.value;
        if (token == null || token.isEmpty) return;
        unawaited(fetchPricingFromServer());
      },
    );
  }

  bool get hasValidMeterPricing => FreeMeterEngine.hasUsablePricing(
        kmPrice: pricePerKm.value,
        timePrice: pricePerMinute.value,
      );

  void _rebuildMeterEngineIfActive() {
    if (!isAnyMeterActive || !hasValidMeterPricing) return;
    final prevKm = distanceTraveled.value;
    final prevCost = meterBaseCost.value;
    final prevMeter = _meter;
    final now = DateTime.now();
    _meter = FreeMeterEngine(
      openPrice: baseFare.value,
      kmPrice: pricePerKm.value,
      timePrice: pricePerMinute.value,
    )
      ..cost = prevCost
      ..distanceKm = prevKm
      ..waitingSeconds = waitingSeconds.value
      ..billedWaitingMinutes = meterBilledMinutes.value
      ..isMoving = isMoving.value
      ..startedAt = prevMeter?.startedAt ?? now
      ..lastSampleAt = prevMeter?.lastSampleAt ?? now
      ..lastMovementAt = prevMeter?.lastMovementAt
      ..lastWaitingTickAt = prevMeter?.lastWaitingTickAt ?? now
      ..pendingMeters = prevMeter?.pendingMeters ?? 0;
  }

  /// جلب أسعار **فئة السيارة** للعداد أثناء رحلة التطبيق.
  Future<bool> fetchCategoryPricingFromServer({bool showError = false}) async {
    final token = SecureAuthToken.value;
    if (token == null || token.isEmpty) {
      if (showError) {
        AppSnackBar.notify('عداد الرحلة', 'سجّل الدخول أولاً');
      }
      return hasValidMeterPricing;
    }

    try {
      final res = await http
          .get(
            Uri.parse(ApiEndpoints.driverPricing),
            headers: await ApiEndpoints.headers(),
          )
          .timeout(HttpTimeouts.api);
      if (res.statusCode != 200) {
        if (showError) {
          AppSnackBar.notify(
            'عداد الرحلة',
            'تعذر جلب أسعار الفئة (${res.statusCode})',
          );
        }
        return hasValidMeterPricing;
      }
      final decoded = decodeJsonUtf8(res);
      if (decoded is! Map) {
        if (showError) {
          AppSnackBar.notify('عداد الرحلة', 'أسعار فئة السيارة غير مكتملة');
        }
        return hasValidMeterPricing;
      }
      final map = Map<String, dynamic>.from(decoded);
      final parsed = FreeMeterEngine.parsePricingResponse(map);
      if (parsed == null) {
        if (showError) {
          AppSnackBar.notify('عداد الرحلة', 'أسعار فئة السيارة غير مكتملة');
        }
        return hasValidMeterPricing;
      }
      _applyPricingMap(parsed);
      return true;
    } catch (e) {
      debugPrint('fetchCategoryPricingFromServer: $e');
      if (showError) {
        AppSnackBar.notify('عداد الرحلة', 'خطأ شبكة — تحقق من الاتصال');
      }
      return hasValidMeterPricing;
    }
  }

  Map<String, double>? _pricingFromOrder(Map<String, dynamic> order) {
    final ct = requestCarTypeFromOrder(order);
    if (ct == null) return null;
    final open = FreeMeterEngine.readPrice(ct, const [
          'openPrice',
          'open_price',
          'OpenPrice',
          'openingPrice',
        ]) ??
        0;
    final km = FreeMeterEngine.readPrice(ct, const [
      'KMPrice',
      'kmPrice',
      'km_price',
      'pricePerKm',
    ]);
    final time = FreeMeterEngine.readPrice(ct, const [
      'timePrice',
      'time_price',
      'pricePerMinute',
      'waitingPrice',
    ]);
    if (km == null || time == null || km <= 0 || time <= 0) return null;
    return {'openPrice': open, 'kmPrice': km, 'timePrice': time};
  }

  /// تشغيل عداد رحلة التطبيق بأسعار فئة السيارة (عند Running).
  /// نفس منطق العداد الحر: يبدأ بالسعر الافتتاحي ثم كم + وقوف.
  Future<bool> startAppTripMeter(Map<String, dynamic> order) async {
    final id = int.tryParse(order['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return false;
    if (appTripMeterRequestId.value == id && isAppTripMeterActive.value) {
      return true;
    }

    if (isTripActive.value) {
      // لا تُعد الاتصال هنا؛ رحلة التطبيق تتولى الحالة.
      await endTrip(showErrors: false, restoreOnline: false);
    }

    // جلب أسعار الفئة من السيرفر (يشمل السعر الافتتاحي).
    await fetchCategoryPricingFromServer(showError: false);

    final fromOrder = _pricingFromOrder(order);
    if (fromOrder != null) {
      final open = (fromOrder['openPrice'] ?? 0) > 0
          ? fromOrder['openPrice']!
          : baseFare.value;
      _applyPricingMap({
        'openPrice': open,
        'kmPrice': fromOrder['kmPrice']!,
        'timePrice': fromOrder['timePrice']!,
      });
    } else {
      final ok = await fetchCategoryPricingFromServer(showError: true);
      if (!ok || !hasValidMeterPricing) return false;
    }

    if (!hasValidMeterPricing) return false;

    _initMeterEngine();
    _meter!.resetForNewTrip(now: DateTime.now());
    _setMeterZoneStart(TripLocationHelpers.extractLocation(order, 'startLocation') ??
        (isFiniteLatLng(currentPosition.value) ? currentPosition.value : null));
    _syncMeterFromEngine();

    appTripMeterRequestId.value = id;
    isAppTripMeterActive.value = true;
    lastPosition = null;
    if (isOnline.value) {
      _onlineLocationStream?.cancel();
      _onlineLocationStream = null;
    }
    _startTripTimer();
    unawaited(_startMeterLocationTracking());
    unawaited(_seedMeterStartPosition());
    unawaited(_uploadAppTripMeter(id));
    unawaited(
      DriverKeepaliveService.syncWithDriverState(
        isOnline: isOnline.value,
        meterActive: true,
      ),
    );
    return true;
  }

  /// أجرة القاعدة + نقطة الإنهاء — السيرفر يعيد حساب معامل المنطقة منها.
  Map<String, dynamic> _meterZoneFinishFields() {
    final end = _meterEndPoint();
    return {
      'meter_base_cost': meterBaseCost.value,
      'zone_multiplier': meterZoneMultiplier.value,
      if (end != null) 'end_latitude': end.latitude,
      if (end != null) 'end_longitude': end.longitude,
    };
  }

  LatLng? _meterEndPoint() {
    final p = lastPosition;
    if (p != null && p.latitude.isFinite && p.longitude.isFinite) {
      return LatLng(p.latitude, p.longitude);
    }
    final c = currentPosition.value;
    return isFiniteLatLng(c) ? c : null;
  }

  Map<String, dynamic> buildAppTripFinishPayload() => {
        'billing_kind': 'app_request',
        ..._meterZoneFinishFields(),
        'finalCost': meterCost.value,
        'distanceTraveledKm': distanceTraveled.value,
        'billedWaitingMinutes': meterBilledMinutes.value,
        'meterElapsedSeconds': meterElapsedSeconds.value,
        'openPrice': baseFare.value,
        'kmPrice': pricePerKm.value,
        'timePrice': pricePerMinute.value,
      };

  void _scheduleAppMeterUpload() {
    final rid = appTripMeterRequestId.value;
    if (rid == null || !isAppTripMeterActive.value) return;

    final cost = meterCost.value;
    final km = distanceTraveled.value;
    final wait = meterBilledMinutes.value;
    final waitSec = waitingSeconds.value;
    final now = DateTime.now();
    final minGap = DriverPollIntervals.liveMeterUploadMin;
    final last = _lastAppMeterUploadAt;
    final valuesChanged = (cost - _lastUploadedMeterCost).abs() >= 0.5 ||
        (km - _lastUploadedMeterKm).abs() >= 0.03 ||
        wait != _lastUploadedWaitMin ||
        waitSec != _lastUploadedWaitSec;
    // ارفع على الأقل كل minGap حتى لو التكلفة ثابتة (لزمن العداد عند الراكب).
    final due = last == null || now.difference(last) >= minGap;
    if (!due && !valuesChanged) return;

    _appMeterUploadDebounce?.cancel();
    final debounce =
        last == null ? Duration.zero : const Duration(milliseconds: 400);
    _appMeterUploadDebounce = Timer(debounce, () {
      unawaited(_uploadAppTripMeter(rid));
    });
  }

  Future<void> _uploadAppTripMeter(int requestId) async {
    if (!isAppTripMeterActive.value ||
        appTripMeterRequestId.value != requestId) {
      return;
    }
    final now = DateTime.now();
    final last = _lastAppMeterUploadAt;
    if (last != null &&
        now.difference(last) < DriverPollIntervals.liveMeterUploadMin) {
      return;
    }
    try {
      final r = await TripApiService.reportLiveMeter(
        requestId,
        body: {
          'finalCost': meterCost.value,
          'distanceTraveledKm': distanceTraveled.value,
          'billedWaitingMinutes': meterBilledMinutes.value,
          'waitingSeconds': waitingSeconds.value,
          'meterElapsedSeconds': meterElapsedSeconds.value,
          'isMoving': isMoving.value,
          'openPrice': baseFare.value,
          'kmPrice': pricePerKm.value,
          'timePrice': pricePerMinute.value,
          'zoneMultiplier': meterZoneMultiplier.value,
          'zoneLabel': meterZoneLabel.value,
        },
      );
      if (r.ok) {
        _lastAppMeterUploadAt = now;
        _lastUploadedMeterCost = meterCost.value;
        _lastUploadedMeterKm = distanceTraveled.value;
        _lastUploadedWaitMin = meterBilledMinutes.value;
        _lastUploadedWaitSec = waitingSeconds.value;
      }
    } catch (e) {
      debugPrint('_uploadAppTripMeter: $e');
    }
  }

  /// جلب أسعار العداد من لوحة التحكم (يتطلب توكن سائق فقط).
  /// يعيد المحاولة تلقائياً؛ إن نجحت القيم المخزّنة لا يُظهر خطأ مزعجاً.
  Future<bool> fetchPricingFromServer({
    bool showError = false,
    int maxAttempts = 2,
    Duration? timeout,
  }) async {
    final token = SecureAuthToken.value;
    if (token == null || token.isEmpty) {
      _loadCachedPricing();
      if (showError && !hasValidMeterPricing) {
        AppSnackBar.notify('العداد الحر', 'سجّل الدخول أولاً لتحميل الأسعار');
      }
      return hasValidMeterPricing;
    }

    _loadCachedPricing();
    final attempts = maxAttempts.clamp(1, 3);
    final wait = timeout ?? HttpTimeouts.pricing;
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final uri = Uri.parse(ApiEndpoints.driverFreeMeterPricing).replace(
          queryParameters: {
            't': DateTime.now().millisecondsSinceEpoch.toString(),
            'a': attempt.toString(),
          },
        );
        final res = await http
            .get(
              uri,
              headers: await ApiEndpoints.headers(),
            )
            .timeout(wait);
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode}';
          debugPrint(
            'fetchPricingFromServer: attempt $attempt HTTP ${res.statusCode}',
          );
          if (attempt < attempts) {
            await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
            continue;
          }
          break;
        }
        final decoded = decodeJsonUtf8(res);
        if (decoded is! Map) {
          lastError = 'invalid body';
          debugPrint('fetchPricingFromServer: invalid body $decoded');
          if (attempt < attempts) {
            await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
            continue;
          }
          break;
        }
        final map = Map<String, dynamic>.from(decoded);
        final parsed = FreeMeterEngine.parsePricingResponse(map);
        if (parsed == null) {
          lastError = 'parse failed';
          debugPrint('fetchPricingFromServer: invalid body $map');
          if (attempt < attempts) {
            await Future<void>.delayed(Duration(milliseconds: 200 * attempt));
            continue;
          }
          break;
        }
        _applyPricingMap(parsed);
        return true;
      } catch (e) {
        lastError = e;
        debugPrint('fetchPricingFromServer: attempt $attempt $e');
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 250 * attempt));
        }
      }
    }

    if (hasValidMeterPricing) {
      debugPrint(
        'fetchPricingFromServer: using cached pricing after failure ($lastError)',
      );
      return true;
    }

    if (showError) {
      AppSnackBar.notify(
        'العداد الحر',
        'تعذر جلب الأسعار — تحقق من الاتصال وإعدادات العداد في لوحة التحكم',
        duration: const Duration(seconds: 5),
      );
    }
    return false;
  }

  Future<void> updateLocationOnServer(Position pos) async {
    try {
      final headers = await ApiEndpoints.headers();
      final response = await http
          .post(
            Uri.parse(ApiEndpoints.updateLocation),
            headers: headers,
            body: jsonEncode({
              'latitude': pos.latitude,
              'longitude': pos.longitude,
            }),
          )
          .timeout(HttpTimeouts.poll);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _scheduleImmediateSyncAfterLocationUpdate();
      } else if (response.statusCode >= 400) {
        debugPrint('⚠️ updateLocation: ${response.statusCode} ${response.body}');
        if (response.statusCode == 503) {
          AppSnackBar.error(
            'تعذر تحديث موقعك على السيرفر — تحقق من Redis. لن تصلك الطلبات حتى يُصلَح.',
          );
        } else if (response.statusCode == 403) {
          try {
            final map = jsonDecode(response.body) as Map<String, dynamic>;
            final code = map['code']?.toString();
            final msg = map['message']?.toString() ?? '';
            if (code == 'subscription_blocked' ||
                msg.contains('قم بالدفع')) {
              if (isOnline.value) {
                setDriverAvailability(false);
              }
              AppSnackBar.error(
                msg.isNotEmpty ? msg : 'قم بالدفع — تجديد الاشتراك الشهري',
              );
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('❌ updateLocation network: $e');
    }
  }

  /// إرسال فوري للخادم (GEO + مفتاح أونلاين) — مهم لظهور السائق في قائمة «القريبون» قبل أي حركة.
  Future<void> pushCurrentLocationToServerNow() async {
    if (!isOnline.value) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (pos.latitude.isFinite && pos.longitude.isFinite) {
        currentPosition.value = LatLng(pos.latitude, pos.longitude);
      }
      await updateLocationOnServer(pos);
    } catch (e) {
      debugPrint('pushCurrentLocationToServerNow: $e');
    }
  }

  void _syncImmediateRequestsAfterLocation() {
    if (!isOnline.value) return;
    if (!Get.isRegistered<DriverServerSyncService>()) return;
    final now = DateTime.now();
    if (_lastLocationTriggeredSync != null &&
        now.difference(_lastLocationTriggeredSync!) <
            DriverPollIntervals.locationSyncMin) {
      return;
    }
    _lastLocationTriggeredSync = now;
    unawaited(Get.find<DriverServerSyncService>().syncNow());
  }

  void _scheduleImmediateSyncAfterLocationUpdate() {
    if (!isOnline.value) return;
    _immediateSyncAfterLocationDebounce?.cancel();
    _immediateSyncAfterLocationDebounce =
        Timer(const Duration(milliseconds: 900), _syncImmediateRequestsAfterLocation);
  }

  void setDriverAvailability(bool online) {
    isOnline.value = online;
    box.write('driver_online_pref', online);
    _onlineLocationHeartbeat?.cancel();
    _onlineLocationHeartbeat = null;
    if (!online) {
      _stopOnlineLocationTracking();
      unawaited(_notifyServerGoOffline());
      if (isAnyMeterActive) {
        unawaited(_startMeterLocationTracking());
      }
      unawaited(
        DriverKeepaliveService.syncWithDriverState(
          isOnline: false,
          meterActive: isAnyMeterActive,
        ),
      );
      return;
    }
    unawaited(_startOnlineLocationTracking());
    unawaited(
      DriverKeepaliveService.syncWithDriverState(
        isOnline: true,
        meterActive: isAnyMeterActive,
      ),
    );
    unawaited(() async {
      await pushCurrentLocationToServerNow();
      _syncImmediateRequestsAfterLocation();
    }());
    if (isAnyMeterActive) {
      unawaited(_startMeterLocationTracking());
    }
    _onlineLocationHeartbeat = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!isOnline.value) {
        _onlineLocationHeartbeat?.cancel();
        _onlineLocationHeartbeat = null;
        return;
      }
      unawaited(pushCurrentLocationToServerNow());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _handleAppBackgrounded();
        break;
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.detached:
        _handleAppBackgrounded(flushOnly: true);
        break;
    }
  }

  /// يُستدعى من FCM أو شاشات أخرى لتحديث العداد بعد العودة.
  void onAppResumedFromBackground() => _handleAppResumed();

  /// عند الخروج للخلفية (مكالمة، تطبيق آخر): تثبيت العداد واستمرار GPS.
  void _handleAppBackgrounded({bool flushOnly = false}) {
    if (!isAnyMeterActive || _meter == null) return;
    _meter!.catchUpWaitingTicks(now: DateTime.now());
    _syncMeterFromEngine();
    _flushMeterStateToStorage();
    if (!flushOnly) {
      unawaited(_startMeterLocationTracking());
    }
  }

  /// عند العودة: تعويض الوقوف/المسافة ثم إعادة المؤقت وتتبع الموقع.
  void _handleAppResumed() {
    if (isAnyMeterActive) {
      _meter?.catchUpWaitingTicks(now: DateTime.now());
      _syncMeterFromEngine();
      _flushMeterStateToStorage();
      if (isAppTripMeterActive.value) {
        unawaited(fetchCategoryPricingFromServer());
      } else {
        unawaited(fetchPricingFromServer());
      }
      _startTripTimer();
      unawaited(_startMeterLocationTracking());
    }
    unawaited(flushPendingFreeMeterFinish());
    if (!isOnline.value) return;
    unawaited(() async {
      await pushCurrentLocationToServerNow();
      _syncImmediateRequestsAfterLocation();
    }());
    notifyAssignedTripRefresh();
  }

  void _flushMeterStateToStorage() {
    if (!isTripActive.value) return;
    box.write('meterCost', meterCost.value);
    box.write('meterBaseCost', meterBaseCost.value);
    box.write('distanceTraveled', distanceTraveled.value);
    box.write('free_meter_waiting_sec', waitingSeconds.value);
    box.write('free_meter_billed_min', meterBilledMinutes.value);
    box.write('isTripActive', true);
    _persistMeterClocks();
  }

  Future<void> _notifyServerGoOffline() async {
    try {
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.driverGoOffline),
            headers: await ApiEndpoints.headers(),
            body: jsonEncode(<String, dynamic>{}),
          )
          .timeout(HttpTimeouts.api);
      if (res.statusCode < 200 || res.statusCode >= 300) {
        debugPrint('driverGoOffline: ${res.statusCode} ${res.body}');
      }
    } catch (e) {
      debugPrint('driverGoOffline: $e');
    }
  }

  void makePhoneCall(String phoneNumber) {
    unawaited(launchPhoneCall(phoneNumber));
  }

  void _persistMeterClocks() {
    final m = _meter;
    if (m == null) return;
    void w(String k, DateTime? v) {
      if (v != null) {
        box.write(k, v.toIso8601String());
      }
    }

    w('free_meter_started_at', m.startedAt);
    w('free_meter_last_sample_at', m.lastSampleAt);
    w('free_meter_last_movement_at', m.lastMovementAt);
    w('free_meter_last_waiting_tick_at', m.lastWaitingTickAt);
  }

  DateTime? _readStoredDate(String key) {
    final raw = box.read(key);
    if (raw is String && raw.isNotEmpty) {
      return DateTime.tryParse(raw);
    }
    return null;
  }

  void _restoreMeterClocks(FreeMeterEngine m) {
    m.startedAt = _readStoredDate('free_meter_started_at') ?? m.startedAt;
    m.lastSampleAt = _readStoredDate('free_meter_last_sample_at') ?? m.lastSampleAt;
    m.lastMovementAt = _readStoredDate('free_meter_last_movement_at');
    m.lastWaitingTickAt =
        _readStoredDate('free_meter_last_waiting_tick_at') ?? m.lastWaitingTickAt;
  }

  void _clearMeterClockStorage() {
    box.remove('free_meter_started_at');
    box.remove('free_meter_last_sample_at');
    box.remove('free_meter_last_movement_at');
    box.remove('free_meter_last_waiting_tick_at');
  }

  void _setupPersistence() {
    ever(meterCost, (val) {
      if (isTripActive.value) box.write('meterCost', val);
    });
    ever(meterBaseCost, (val) {
      if (isTripActive.value) box.write('meterBaseCost', val);
    });
    ever(distanceTraveled, (val) {
      if (isTripActive.value) box.write('distanceTraveled', val);
    });
    ever(waitingSeconds, (val) {
      if (isTripActive.value) box.write('free_meter_waiting_sec', val);
    });
    ever(meterBilledMinutes, (val) {
      if (isTripActive.value) box.write('free_meter_billed_min', val);
    });
    ever(isTripActive, (val) => box.write('isTripActive', val));
  }

  void _loadState() {
    isTripActive.value = box.read('isTripActive') ?? false;
    final storedFreeId = int.tryParse('${box.read('free_meter_request_id') ?? ''}');
    if (storedFreeId != null && storedFreeId > 0) {
      freeMeterRequestId.value = storedFreeId;
    }
    if (isTripActive.value) {
      meterCost.value = (box.read('meterCost') as num?)?.toDouble() ?? baseFare.value;
      meterBaseCost.value =
          (box.read('meterBaseCost') as num?)?.toDouble() ?? meterCost.value;
      final zLat = (box.read(_kMeterZoneStartLat) as num?)?.toDouble();
      final zLng = (box.read(_kMeterZoneStartLng) as num?)?.toDouble();
      if (zLat != null && zLng != null) {
        _meterZoneStart = LatLng(zLat, zLng);
        unawaited(PricingZoneMap.instance.refresh().then((_) => _syncMeterFromEngine()));
      }
      distanceTraveled.value =
          (box.read('distanceTraveled') as num?)?.toDouble() ?? 0.0;
      waitingSeconds.value = box.read('free_meter_waiting_sec') ?? 0;
      final billedRaw = box.read('free_meter_billed_min');
      if (billedRaw is int) {
        meterBilledMinutes.value = billedRaw;
      } else if (billedRaw is num) {
        meterBilledMinutes.value = billedRaw.toInt();
      }
      if (hasValidMeterPricing) {
        _initMeterEngine();
        _restoreMeterClocks(_meter!);
        _meter!.catchUpWaitingTicks();
        _syncMeterFromEngine();
      }
      unawaited(fetchPricingFromServer());
      _startTripTimer();
      unawaited(_startMeterLocationTracking());
    }

    if (box.read('driver_online_pref') == true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!isOnline.value) {
          setDriverAvailability(true);
        }
      });
    }

    if (!isTripActive.value) {
      unawaited(flushPendingFreeMeterFinish());
    }
  }

  void _initMeterEngine() {
    final now = DateTime.now();
    final storedMove = _readStoredDate('free_meter_last_movement_at');
    _meter = FreeMeterEngine(
      openPrice: baseFare.value,
      kmPrice: pricePerKm.value,
      timePrice: pricePerMinute.value,
    )
      ..cost = meterBaseCost.value
      ..distanceKm = distanceTraveled.value
      ..waitingSeconds = waitingSeconds.value
      ..billedWaitingMinutes = meterBilledMinutes.value
      ..isMoving = isMoving.value
      ..startedAt = _readStoredDate('free_meter_started_at') ?? now
      ..lastSampleAt = _readStoredDate('free_meter_last_sample_at') ?? now
      // لا تُصفَّر آخر حركة عند إعادة البناء — وإلا يتوقف عدّ الثواني.
      ..lastMovementAt = storedMove ?? (isMoving.value ? now : null)
      ..lastWaitingTickAt =
          _readStoredDate('free_meter_last_waiting_tick_at') ?? now;
  }

  void _setMeterZoneStart(LatLng? start) {
    _meterZoneStart = start;
    if (start != null && isTripActive.value) {
      box.write(_kMeterZoneStartLat, start.latitude);
      box.write(_kMeterZoneStartLng, start.longitude);
    }
    unawaited(PricingZoneMap.instance.refresh().then((_) => _syncMeterFromEngine()));
  }

  /// منطقة البداية ← منطقة موقع السيارة الحالي (نفس قواعد لوحة التحكم).
  void _updateMeterZone() {
    final start = _meterZoneStart;
    final here = _meterEndPoint();
    if (start == null || here == null || !PricingZoneMap.instance.hasZones) {
      meterZoneMultiplier.value = 1.0;
      meterZoneLabel.value = '';
      return;
    }
    final q = PricingZoneMap.instance.quote(
      start.latitude,
      start.longitude,
      here.latitude,
      here.longitude,
    );
    meterZoneMultiplier.value = q.multiplier;
    meterZoneLabel.value = q.label;
  }

  void _syncMeterFromEngine() {
    final m = _meter;
    if (m == null) return;
    meterBaseCost.value = m.cost;
    _updateMeterZone();
    meterCost.value = m.cost * meterZoneMultiplier.value;
    distanceTraveled.value = m.distanceKm;
    waitingSeconds.value = m.waitingSeconds;
    meterBilledMinutes.value = m.billedWaitingMinutes;
    isMoving.value = m.isMoving;
    final start = m.startedAt;
    if (start != null) {
      meterElapsedSeconds.value =
          DateTime.now().difference(start).inSeconds.clamp(0, 999999);
    }
    _persistMeterClocks();
    if (isAppTripMeterActive.value) {
      _scheduleAppMeterUpload();
    }
  }

  /// تنسيق الزمن المنقضي للعداد (MM:SS أو H:MM:SS).
  static String formatMeterElapsed(int totalSeconds) {
    final sec = totalSeconds.clamp(0, 999999);
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  double get meterKmCostComponent =>
      distanceTraveled.value * pricePerKm.value;

  double get meterWaitingCostComponent =>
      meterBilledMinutes.value * pricePerMinute.value;

  /// ثواني الوقوف للعرض (0:00 → 0:59 → 1:00 ثم +سعر الدقيقة).
  int get meterWaitingDisplaySeconds =>
      meterBilledMinutes.value * 60 + waitingSeconds.value;

  Future<bool> startTrip() async {
    if (isAppTripMeterActive.value) {
      AppSnackBar.notify(
        'العداد الحر',
        'لا يمكن تشغيل العداد الحر أثناء عداد الرحلة',
      );
      return false;
    }

    // لا نعلّق التشغيل على الشبكة: استخدم الكاش فوراً وحدّث الأسعار بالخلفية.
    _loadCachedPricing();
    if (!hasValidMeterPricing) {
      final ok = await fetchPricingFromServer(
        showError: true,
        maxAttempts: 1,
        timeout: const Duration(seconds: 8),
      );
      if (!hasValidMeterPricing) {
        AppSnackBar.notify(
          'العداد الحر',
          ok
              ? 'حدّد أسعار الفتح والكيلو والدقيقة من لوحة التحكم ثم أعد المحاولة'
              : 'تعذر تحميل الأسعار — تحقق من الاتصال وإعدادات العداد',
          duration: const Duration(seconds: 5),
        );
        return false;
      }
    } else {
      unawaited(
        fetchPricingFromServer(
          showError: false,
          maxAttempts: 1,
          timeout: const Duration(seconds: 6),
        ),
      );
    }

    final pos = currentPosition.value;
    final started = await TripApiService.startFreeMeter(
      latitude: isFiniteLatLng(pos) ? pos.latitude : null,
      longitude: isFiniteLatLng(pos) ? pos.longitude : null,
    );
    if (!started.ok) {
      AppSnackBar.notify(
        'العداد الحر',
        started.message ?? 'تعذر تسجيل رحلة العداد الحر على السيرفر',
        duration: const Duration(seconds: 5),
      );
      return false;
    }
    final rid = int.tryParse(
          '${started.dataMap?['id'] ?? ''}',
        ) ??
        int.tryParse('${started.raw?['request_id'] ?? ''}') ??
        int.tryParse('${started.raw?['data']?['id'] ?? ''}');
    if (rid == null || rid <= 0) {
      AppSnackBar.notify(
        'العداد الحر',
        started.message?.isNotEmpty == true
            ? started.message!
            : 'لم يُرجع السيرفر رقم الرحلة (${started.statusCode})',
      );
      return false;
    }
    freeMeterRequestId.value = rid;
    box.write('free_meter_request_id', rid);

    _initMeterEngine();
    _meter!.resetForNewTrip(now: DateTime.now());
    // أول تكة فورية: الزمن + الوقوف يشتغلان وأنت واقف من ثانية التشغيل.
    _meter!.tickWaitingSecond(now: DateTime.now());
    _syncMeterFromEngine();

    isTripActive.value = true;
    // نفس نقطة البداية المحفوظة على السيرفر (يستخدم وسط دمشق إن لم يصله موقع).
    _setMeterZoneStart(isFiniteLatLng(pos) ? pos : const LatLng(33.5138, 36.2765));
    lastPosition = null;
    // لا استقبال طلبات التطبيق أثناء العداد الحر.
    clearAppTripUiForFreeMeter?.call();
    clearAcceptedTripPreview();
    // احفظ حالة الاتصال لاستعادتها بعد إيقاف العداد (شريط «اسحب للإيقاف»).
    final wasOnline = isOnline.value;
    box.write(_kResumeOnlineAfterFreeMeter, wasOnline);
    if (wasOnline) {
      setDriverAvailability(false);
    }
    _startTripTimer();
    unawaited(_startMeterLocationTracking());
    unawaited(
      DriverKeepaliveService.syncWithDriverState(
        isOnline: isOnline.value,
        meterActive: true,
      ),
    );
    // ثبّت نقطة البداية فوراً حتى تُحسب أول حركة بدقة (بدون اعتبارها قيادة).
    unawaited(_seedMeterStartPosition());
    return true;
  }

  Future<void> _seedMeterStartPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
        ),
      );
      if (!isAnyMeterActive) return;
      if (!pos.latitude.isFinite || !pos.longitude.isFinite) return;
      lastPosition = pos;
      currentPosition.value = LatLng(pos.latitude, pos.longitude);
    } catch (_) {}
  }

  void _startTripTimer() {
    _tripTimer?.cancel();
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!isAnyMeterActive || _meter == null) {
        timer.cancel();
        return;
      }
      _meter!.tickWaitingSecond(now: DateTime.now());
      _syncMeterFromEngine();
    });
  }

  Future<void> _startMeterLocationTracking() async {
    if (!isAnyMeterActive) return;

    final permOk = await DriverOnlineForeground.ensureMeterPermissions();
    if (!permOk) {
      AppSnackBar.notify(
        'الموقع',
        'يُرجى السماح بالوصول إلى الموقع (ويفضّل «طوال الوقت») لتشغيل العداد في الخلفية',
        duration: const Duration(seconds: 6),
      );
      return;
    }

    if (!kIsWeb && Platform.isAndroid) {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.whileInUse) {
        AppSnackBar.notify(
          'العداد في الخلفية',
          'فعّل الموقع «طوال الوقت» من الإعدادات',
          duration: const Duration(seconds: 8),
          mainButton: TextButton(
            onPressed: () => Geolocator.openAppSettings(),
            child: const Text(
              'فتح الإعدادات',
              style: TextStyle(color: Color(0xFFFFC107)),
            ),
          ),
        );
      }
    }

    positionStream?.cancel();
    _onlineLocationStream?.cancel();
    _onlineLocationStream = null;
    // مصدر GPS واحد للعداد — تدفّقان متداخلان يولّدان مقاطع وهمية والسيارة واقفة.
    _deviceLocationStream?.cancel();
    _deviceLocationStream = null;

    positionStream = Geolocator.getPositionStream(
      locationSettings: DriverOnlineForeground.meterLocationSettings(),
    ).listen((pos) => _applyPositionToUi(pos, postToServer: isOnline.value));
  }

  void _onMeterGps(Position currentPos) {
    if (!isAnyMeterActive || _meter == null) return;
    if (!currentPos.latitude.isFinite || !currentPos.longitude.isFinite) {
      return;
    }

    final sampleAt = currentPos.timestamp;
    _meter!.catchUpWaitingTicks(now: sampleAt);

    if (!FreeMeterEngine.accuracyOkForDistance(currentPos.accuracy)) {
      _meter!.isMoving = _meter!.isCurrentlyMoving(now: sampleAt);
      _syncMeterFromEngine();
      // حدّث المرجع حتى لا تُحسب قفزة كبيرة عند عودة الدقة.
      lastPosition = currentPos;
      return;
    }

    final segment = FreeMeterEngine.segmentMeters(lastPosition, currentPos);
    final speed = currentPos.speed.isFinite && currentPos.speed >= 0
        ? currentPos.speed
        : null;

    if (segment != null && segment > 0) {
      _meter!.applySegment(
        distanceMeters: segment,
        speedMps: speed,
        sampleAt: sampleAt,
        accuracyMeters: currentPos.accuracy,
      );
        } else {
      _meter!.isMoving = _meter!.isCurrentlyMoving(now: sampleAt);
        }
    _syncMeterFromEngine();
      lastPosition = currentPos;
  }

  Future<bool> endTrip({
    bool showErrors = true,
    bool restoreOnline = true,
  }) async {
    if (!isTripActive.value) return true;

    final rid = freeMeterRequestId.value ??
        int.tryParse('${box.read('free_meter_request_id') ?? ''}');
    if (rid != null && rid > 0) {
      final body = <String, dynamic>{
        'billing_kind': 'free_meter',
        ..._meterZoneFinishFields(),
        'finalCost': meterCost.value,
        'distanceTraveledKm': distanceTraveled.value,
        'billedWaitingMinutes': meterBilledMinutes.value,
        'waitingSeconds': waitingSeconds.value,
        'meterElapsedSeconds': meterElapsedSeconds.value,
        'free_meter_had_movement': distanceTraveled.value > 0.05,
      };
      final r = await TripApiService.finishTrip(rid, body: body);
      if (!r.ok) {
        final msg = (r.message ?? '').toLowerCase();
        // السيرفر أنهى الرحلة مسبقاً (مهلة/إعادة محاولة) — اعتبره نجاحاً محلياً.
        final alreadyDone = r.statusCode == 400 &&
            (msg.contains('cannot finish') ||
                msg.contains('منتهية') ||
                msg.contains('حالتها الحالية') ||
                msg.contains('finished'));
        if (!alreadyDone) {
          // انقطع النت أو فشل الحفظ — أنهِ محلياً وارفع لاحقاً عند عودة الاتصال.
          _savePendingFreeMeterFinish(rid, body);
        }
      } else {
        _clearPendingFreeMeterFinishIfMatches(rid);
      }
    }

    final shouldResumeOnline = restoreOnline &&
        (box.read(_kResumeOnlineAfterFreeMeter) == true);

    isTripActive.value = false;
    freeMeterRequestId.value = null;
    box.remove('meterCost');
    box.remove('meterBaseCost');
    box.remove(_kMeterZoneStartLat);
    box.remove(_kMeterZoneStartLng);
    box.remove('distanceTraveled');
    box.remove('isTripActive');
    box.remove('free_meter_waiting_sec');
    box.remove('free_meter_billed_min');
    box.remove('free_meter_request_id');
    box.remove(_kResumeOnlineAfterFreeMeter);
    _stopSharedMeterIfIdle();

    // بعد إيقاف العداد الحر: أعد «اسحب للإيقاف» واستقبال الطلبات كما كان.
    if (shouldResumeOnline) {
      setDriverAvailability(true);
    }
    return true;
  }

  void _savePendingFreeMeterFinish(int requestId, Map<String, dynamic> body) {
    box.write(_kPendingFreeMeterFinish, {
      'request_id': requestId,
      'body': body,
      'saved_at': DateTime.now().toIso8601String(),
    });
  }

  void _clearPendingFreeMeterFinish() {
    box.remove(_kPendingFreeMeterFinish);
  }

  void _clearPendingFreeMeterFinishIfMatches(int requestId) {
    final raw = box.read(_kPendingFreeMeterFinish);
    if (raw is! Map) return;
    final pendingId = int.tryParse('${raw['request_id'] ?? ''}') ?? 0;
    if (pendingId == requestId) {
      _clearPendingFreeMeterFinish();
    }
  }

  /// رفع إنهاء عداد حر معلّق بعد انقطاع النت.
  Future<void> flushPendingFreeMeterFinish() async {
    if (_flushingPendingFreeMeterFinish) return;
    if (isTripActive.value) return;
    final raw = box.read(_kPendingFreeMeterFinish);
    if (raw is! Map) return;

    final rid = int.tryParse('${raw['request_id'] ?? ''}') ?? 0;
    if (rid <= 0) {
      _clearPendingFreeMeterFinish();
      return;
    }
    final bodyRaw = raw['body'];
    final body = bodyRaw is Map
        ? Map<String, dynamic>.from(bodyRaw)
        : <String, dynamic>{'billing_kind': 'free_meter'};

    _flushingPendingFreeMeterFinish = true;
    try {
      final r = await TripApiService.finishTrip(rid, body: body);
      if (r.ok) {
        _clearPendingFreeMeterFinish();
        return;
      }
      final msg = (r.message ?? '').toLowerCase();
      final alreadyDone = r.statusCode == 400 &&
          (msg.contains('cannot finish') ||
              msg.contains('منتهية') ||
              msg.contains('حالتها الحالية') ||
              msg.contains('finished'));
      if (alreadyDone) {
        _clearPendingFreeMeterFinish();
      }
    } catch (_) {
      // يبقى معلّقاً لإعادة المحاولة لاحقاً.
    } finally {
      _flushingPendingFreeMeterFinish = false;
    }
  }

  void endAppTripMeter() {
    if (!isAppTripMeterActive.value) return;
    isAppTripMeterActive.value = false;
    appTripMeterRequestId.value = null;
    _appMeterUploadDebounce?.cancel();
    _appMeterUploadDebounce = null;
    _lastAppMeterUploadAt = null;
    _lastUploadedMeterCost = -1;
    _lastUploadedMeterKm = -1;
    _lastUploadedWaitMin = -1;
    _lastUploadedWaitSec = -1;
    _stopSharedMeterIfIdle();
  }

  void _stopSharedMeterIfIdle() {
    if (isAnyMeterActive) return;

    _tripTimer?.cancel();
    positionStream?.cancel();
    positionStream = null;
    _meter = null;
    _clearMeterClockStorage();

    meterCost.value = 0.0;
    meterBaseCost.value = 0.0;
    meterZoneMultiplier.value = 1.0;
    meterZoneLabel.value = '';
    _meterZoneStart = null;
    distanceTraveled.value = 0.0;
    waitingSeconds.value = 0;
    meterElapsedSeconds.value = 0;
    meterBilledMinutes.value = 0;
    isMoving.value = false;
    lastPosition = null;

    if (isOnline.value) {
      unawaited(_startOnlineLocationTracking());
    } else {
      unawaited(_startLiveDeviceLocation());
    }
    unawaited(
      DriverKeepaliveService.syncWithDriverState(
        isOnline: isOnline.value,
        meterActive: isAnyMeterActive,
      ),
    );
  }

  void setupConnectionListener() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription =
        Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.none)) {
        connectionStatus.value = 'weak';
      } else {
        connectionStatus.value = 'connected';
        unawaited(flushPendingFreeMeterFinish());
      }
    });
  }

  Future<void> sendSOS() async {
    final driverId = box.read('driver_id');
    if (driverId == null) {
      AppSnackBar.notify("تنبيه", "معرف السائق غير محفوظ — أعد تسجيل الدخول");
      return;
    }

    try {
      final headers = await ApiEndpoints.headers();
      final response = await http
          .post(
            Uri.parse(ApiEndpoints.emergencySos),
            headers: headers,
            body: jsonEncode({
              'latitude': currentPosition.value.latitude,
              'longitude': currentPosition.value.longitude,
            }),
          )
          .timeout(HttpTimeouts.api);
      final decoded = decodeJsonUtf8(response);
      final map = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      if (response.statusCode == 200 && map['state'] == true) {
        SosLiveReporter.instance.start();
        AppSnackBar.notify(
          "تنبيه طوارئ",
          map['message']?.toString() ?? "تم إبلاغ الإدارة",
          backgroundColor: Colors.red,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
        );
      } else {
        AppSnackBar.notify(
          "فشل الإرسال",
          map['message']?.toString() ?? "خطأ ${response.statusCode}",
          backgroundColor: Colors.orange.shade800,
          colorText: Colors.white,
        );
      }
    } catch (e) {
      AppSnackBar.notify("خطأ", "تعذر إرسال SOS: $e");
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _immediateSyncAfterLocationDebounce?.cancel();
    // لا نُرسِل go-offline عند إغلاق التطبيق — يبقى «متصل» حتى يُغلق يدوياً أو تسجيل الخروج.
    _meterPricingRefreshTimer?.cancel();
    _onlineLocationHeartbeat?.cancel();
    _connectivitySubscription?.cancel();
    _deviceLocationStream?.cancel();
    _compassSub?.cancel();
    _onlineLocationStream?.cancel();
    positionStream?.cancel();
    _tripTimer?.cancel();
    fareTimer?.cancel();
    waitingTimer?.cancel();
    super.onClose();
  }
}






