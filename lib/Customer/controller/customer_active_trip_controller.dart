import 'dart:async';
import '../../core/constants/snack_bar.dart';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:latlong2/latlong.dart';

import '../../core/constants/customer_poll_intervals.dart';
import '../../core/constants/dev_mock_flags.dart';
import '../../core/services/trip_api_service.dart';
import '../../core/services/trip_push_events.dart';
import '../../core/utils/app_alert_sound.dart';
import '../../core/utils/customer_trip_map_state.dart';
import '../../core/utils/customer_trip_status_helpers.dart';
import '../../core/utils/dev_mock_driver_trip.dart';
import '../../core/utils/driver_order_display.dart';

/// طلب نشط، تتبع السائق، وإشعارات الزبون.
class CustomerActiveTripController extends GetxController {
  final activeTrip = Rxn<Map<String, dynamic>>();
  /// حجوزات مسبقة مقبولة لم ينطلق السائق إليها بعد (أيقونة الحجز المسبق).
  final upcomingScheduled = <Map<String, dynamic>>[].obs;
  final driverLivePos = Rxn<LatLng>();
  final liveTripMeter = Rxn<Map<String, dynamic>>();
  final started = false.obs;

  Timer? _activeTripPoll;
  Timer? _trackPoll;
  Timer? _notifPoll;
  Timer? _devMockPhaseTick;
  bool _refreshInFlight = false;
  bool _trackInFlight = false;
  int _consecutivePollErrors = 0;
  final Set<int> _shownNotificationIds = <int>{};
  final Set<int> _autoTripSurveyShownForIds = <int>{};
  final Set<int> _tripCompletionShownForIds = <int>{};
  final Set<int> _acceptSoundPlayedForIds = <int>{};
  final Set<int> _startSoundPlayedForIds = <int>{};
  final Set<int> _arrivedSnackPlayedForIds = <int>{};


  void Function(CustomerTripMapUpdate update)? onMapUpdate;
  void Function()? onScheduleRouteFetch;
  Future<void> Function(Map<String, dynamic> trip)? onTripSurvey;
  Future<void> Function(Map<String, dynamic> trip)? onTripCompleted;
  Future<void> Function()? onBookingUiReset;

  Future<bool?> Function()? showSchedT5ReadyDialog;
  Future<bool?> Function()? showSchedDriverBusyDialog;
  Future<void> Function(int requestId)? onSchedRejectedRechoose;
  Future<void> Function()? onReloadMyRequests;

  @override
  void onInit() {
    super.onInit();
    _scheduleActiveTripPoll();
    _notifPoll = Timer.periodic(
      CustomerPollIntervals.notifications,
      (_) => pollNotifications(),
    );
    Future.microtask(() {
      refreshActiveTrip();
      pollNotifications();
    });
  }

  void _scheduleActiveTripPoll() {
    _activeTripPoll?.cancel();
    var interval = _activeTripPollInterval();
    if (_consecutivePollErrors >= 2) {
      interval = CustomerPollIntervals.errorBackoff;
    }
    _activeTripPoll = Timer.periodic(interval, (_) {
      refreshActiveTrip();
    });
  }

  Duration _activeTripPollInterval() {
    final t = activeTrip.value;
    if (t == null) return CustomerPollIntervals.idle;
    if (CustomerTripStatusHelpers.normTripStatus(t) == 'Running') {
      return CustomerPollIntervals.activeTripRunning;
    }
    return CustomerPollIntervals.activeTrip;
  }

  Duration _driverTrackingInterval() {
    final t = activeTrip.value;
    if (t != null &&
        CustomerTripStatusHelpers.normTripStatus(t) == 'Running') {
      return CustomerPollIntervals.driverTrackingRunning;
    }
    if (t != null &&
        CustomerTripStatusHelpers.normTripStatus(t) == 'Pending') {
      return CustomerPollIntervals.driverTrackingPending;
    }
    return CustomerPollIntervals.driverTracking;
  }

  void _reschedulePollsIfNeeded(String? prevStatus, String? newStatus) {
    if (prevStatus == newStatus) return;
    _scheduleActiveTripPoll();
    _syncTripTracking();
  }

  @override
  void onClose() {
    _activeTripPoll?.cancel();
    _trackPoll?.cancel();
    _notifPoll?.cancel();
    _devMockPhaseTick?.cancel();
    super.onClose();
  }

  void onAppResumed() => refreshActiveTrip();

  /// يُستدعى من FCM عند تغيّر حالة الرحلة — أسرع من انتظار الاستطلاع.
  Future<void> onPushTripEvent(TripPushEvent event) async {
    if (!event.isCustomerRelevant) return;
    await refreshActiveTrip();
    // بعد الإنهاء/الإلغاء أعد تحميل «طلباتي» إن وُجد callback.
    if (event.kind == TripPushEventKind.finished ||
        event.kind == TripPushEventKind.cancelled) {
      await onReloadMyRequests?.call();
    }
  }

  void clearActive() {
    _trackPoll?.cancel();
    _devMockPhaseTick?.cancel();
    final id = int.tryParse(activeTrip.value?['id']?.toString() ?? '') ?? 0;
    if (id > 0) DevMockDriverTrip.clear(id);
    activeTrip.value = null;
    driverLivePos.value = null;
    liveTripMeter.value = null;
    started.value = false;
  }

  /// أثناء شاشة رادار البحث — لا تُلغَ الطلبات Pending تلقائياً.
  bool holdOrphanPendingCleanup = false;

  /// ألغِ طلب فوري معلّق تُرك بعد إغلاق التطبيق (بدون جلسة انتظار نشطة).
  Future<bool> _cleanupOrphanImmediatePending(
    Map<String, dynamic> trip, {
    required Map<String, dynamic>? previousTrip,
  }) async {
    // أثناء وضع المحاكاة لا نُلغِ الطلبات Pending حتى تبقى واجهة الرحلة.
    if (kDevMockInstantDriverFound) return false;
    if (holdOrphanPendingCleanup) return false;
    if (!CustomerTripStatusHelpers.requestIsImmediate(trip)) return false;
    if (CustomerTripStatusHelpers.normTripStatus(trip) != 'Pending') {
      return false;
    }
    // فقط عند اكتشافه من جديد (بعد فتح التطبيق / مسح الجلسة) —
    // وليس أثناء انتظار نشط كان معروفاً مسبقاً في هذه الجلسة.
    if (previousTrip != null) {
      final prevId = int.tryParse(previousTrip['id']?.toString() ?? '') ?? 0;
      final curId = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
      if (prevId > 0 && prevId == curId) return false;
    }

    final id = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return false;

    // طلبات مرسلة من لوحة الإدارة — لا تُلغَ عند إعادة فتح التطبيق
    final locDesc = '${trip['locationDesc'] ?? trip['location_desc'] ?? ''}';
    if (locDesc.contains('لوحة الإدارة') || locDesc.contains('admin_dispatch')) {
      return false;
    }

    var r = await TripApiService.cancelCustomerRequest(
      id,
      reason: 'abandoned_on_reopen',
    );
    if (!r.ok &&
        (r.statusCode >= 500 || r.statusCode == 408 || r.statusCode == 0)) {
      r = await TripApiService.abortActiveTrip(
        id,
        reason: 'abandoned_on_reopen',
      );
    }
    return r.ok;
  }

  Future<void> refreshActiveTrip() async {
    if (_refreshInFlight) return;
    final box = GetStorage();
    final uid = box.read('user_id');
    final userId = uid is int ? uid : int.tryParse('$uid');
    if (userId == null) return;
    _refreshInFlight = true;
    try {
      final previousTrip = activeTrip.value;
      final prevSt = previousTrip != null
          ? CustomerTripStatusHelpers.normTripStatus(previousTrip)
          : null;

      Map<String, dynamic>? active;
      List<Map<String, dynamic>> fullList = const [];
      final prevUpcomingIds = {
        for (final u in upcomingScheduled)
          int.tryParse(u['id']?.toString() ?? '') ?? 0,
      };

      // مسار خفيف أولاً — يقلّل حجم الرد ووقت الاستجابة.
      final light = await TripApiService.fetchCustomerActiveTripLight();
      if (light.ok) {
        active = light.trip;
        upcomingScheduled.assignAll(light.upcoming);
        _consecutivePollErrors = 0;
      } else {
        fullList = await TripApiService.fetchUserRequests(userId);
        if (fullList.isEmpty && previousTrip == null) {
          _consecutivePollErrors++;
          if (_consecutivePollErrors == 2) _scheduleActiveTripPoll();
        } else {
          _consecutivePollErrors = 0;
        }
        for (final r in fullList) {
          if (CustomerTripStatusHelpers.shouldShowAsMapActiveTrip(r)) {
            active = r;
            break;
          }
        }
        if (fullList.isNotEmpty) {
          upcomingScheduled.assignAll(fullList.where(scheduledInWaitingPhase));
        }
      }

      // عند اختفاء الرحلة بعد نشاط سابق: جلب القائمة مرة للتحقق من الإنهاء.
      if (previousTrip != null && active == null && fullList.isEmpty) {
        fullList = await TripApiService.fetchUserRequests(userId);
        for (final r in fullList) {
          if (CustomerTripStatusHelpers.shouldShowAsMapActiveTrip(r)) {
            active = r;
            break;
          }
        }
      }

      if (active != null &&
          kDevMockInstantDriverFound &&
          CustomerTripStatusHelpers.requestIsImmediate(active) &&
          CustomerTripStatusHelpers.normTripStatus(active) == 'Pending') {
        active = DevMockDriverTrip.apply(active);
      }

      if (active != null &&
          await _cleanupOrphanImmediatePending(
            active,
            previousTrip: previousTrip,
          )) {
        active = null;
        clearActive();
        unawaited(Future(() async {
          await onBookingUiReset?.call();
          await onReloadMyRequests?.call();
        }));
      }

      if (previousTrip != null && active == null) {
        final pid = int.tryParse(previousTrip['id']?.toString() ?? '') ?? 0;
        if (pid > 0 && fullList.isEmpty) {
          fullList = await TripApiService.fetchUserRequests(userId);
        }
      }

      activeTrip.value = active;
      if (active != null) {
        started.value = true;
        onMapUpdate?.call(CustomerTripMapUpdate.fromTrip(active));
        onScheduleRouteFetch?.call();
        final newSt = CustomerTripStatusHelpers.normTripStatus(active);
        _reschedulePollsIfNeeded(prevSt, newSt);
        if (kDevMockInstantDriverFound) {
          _applyDevMockUiExtras(active, previousStatus: prevSt);
          _scheduleDevMockPhaseTick(active);
        }
      } else if (prevSt != null) {
        _reschedulePollsIfNeeded(prevSt, null);
        _devMockPhaseTick?.cancel();
      }
      // انتهاء الرحلة: لا نُبقي خريطة/لوحة الحجز — فقط شاشة النتيجة ثم إعادة الواجهة الأولى.
      _syncTripTracking();
      _maybePromptAutoTripSurvey(
        previousTrip: previousTrip,
        newActive: active,
        fullList: fullList,
      );
      if (active != null) {
        final curSt = CustomerTripStatusHelpers.normTripStatus(active);
        final prevStSound = previousTrip != null
            ? CustomerTripStatusHelpers.normTripStatus(previousTrip)
            : '';
        final curId = int.tryParse(active['id']?.toString() ?? '') ?? 0;
        // حجز مسبق انطلق إليه السائق للتو (كان أيقونة ثم صار رحلة حية).
        final schedJustStarted = prevStSound.isEmpty &&
            CustomerTripStatusHelpers.requestIsScheduled(active) &&
            prevUpcomingIds.contains(curId);
        if (curSt == 'Reserved' &&
            (prevStSound == 'Pending' || schedJustStarted) &&
            curId > 0 &&
            _acceptSoundPlayedForIds.add(curId)) {
          unawaited(AppAlertSound.playTripAccepted());
        }
        if (curSt == 'Running' &&
            prevStSound != 'Running' &&
            curId > 0 &&
            _startSoundPlayedForIds.add(curId)) {
          unawaited(AppAlertSound.playTripStarted());
        }
      }
    } catch (_) {
      _consecutivePollErrors++;
      if (_consecutivePollErrors == 2) _scheduleActiveTripPoll();
    } finally {
      _refreshInFlight = false;
    }
  }

  void _maybePromptAutoTripSurvey({
    required Map<String, dynamic>? previousTrip,
    required Map<String, dynamic>? newActive,
    required List<Map<String, dynamic>> fullList,
  }) {
    if (previousTrip == null) return;
    final pid = int.tryParse(previousTrip['id']?.toString() ?? '') ?? 0;
    if (pid <= 0) return;
    final naId = newActive == null
        ? null
        : int.tryParse(newActive['id']?.toString() ?? '');
    if (naId == pid) return;
    Map<String, dynamic>? row;
    for (final r in fullList) {
      if ((int.tryParse(r['id']?.toString() ?? '') ?? 0) == pid) {
        row = r;
        break;
      }
    }
    if (row == null) return;
    if (CustomerTripStatusHelpers.normTripStatus(row) == 'Finished') {
      _scheduleTripCompletionThenSurvey(row);
    }
  }

  void _scheduleTripCompletionThenSurvey(Map<String, dynamic> trip) {
    final id = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return;
    Future.microtask(() async {
      if (!_tripCompletionShownForIds.contains(id)) {
        _tripCompletionShownForIds.add(id);
        await onTripCompleted?.call(trip);
      }
      if (_autoTripSurveyShownForIds.contains(id)) return;
      _autoTripSurveyShownForIds.add(id);
      await onTripSurvey?.call(trip);
      await onBookingUiReset?.call();
    });
  }

  void _syncTripTracking() {
    _trackPoll?.cancel();
    final t = activeTrip.value;
    if (t == null) {
      driverLivePos.value = null;
      liveTripMeter.value = null;
      return;
    }
    final st = CustomerTripStatusHelpers.normTripStatus(t);
    final id = int.tryParse(t['id']?.toString() ?? '') ?? 0;
    if (id <= 0 || !CustomerTripStatusHelpers.isActiveStatus(st)) {
      driverLivePos.value = null;
      liveTripMeter.value = null;
      return;
    }
    _trackPoll = Timer.periodic(
      _driverTrackingInterval(),
      (_) => _fetchDriverTrack(id),
    );
    _fetchDriverTrack(id);
  }

  static double? _coordDyn(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static LatLng? _latLngFromLooseMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<dynamic, dynamic>.from(raw);
    final lat = _coordDyn(m['lat'] ?? m['latitude']);
    final lng = _coordDyn(m['lng'] ?? m['longitude'] ?? m['lon']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  static double? _meterNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static int? _epochMs(dynamic ms, dynamic iso) {
    final n = _meterNum(ms);
    if (n != null && n > 0) return n.toInt();
    if (iso == null) return null;
    return DateTime.tryParse(iso.toString())?.millisecondsSinceEpoch;
  }

  /// لقطة السائق كما هي + `_anchorMs`: الوقت المحلي الذي كانت فيه اللقطة صحيحة.
  /// عمر اللقطة من ساعة السيرفر فقط (server_ts − updated_at) لتجنّب فرق ساعات الأجهزة.
  void _applyLiveMeterSnapshot(
    Map<String, dynamic> lm, {
    dynamic serverTsMs,
    dynamic serverTs,
    DateTime? receivedAt,
  }) {
    final recv = (receivedAt ?? DateTime.now()).millisecondsSinceEpoch;
    final updatedMs = _epochMs(lm['updated_at_ms'], lm['updated_at']);
    final serverMs = _epochMs(serverTsMs, serverTs);
    var ageMs = 0;
    if (updatedMs != null && serverMs != null) {
      ageMs = (serverMs - updatedMs).clamp(0, 180000);
    }
    liveTripMeter.value = {
      ...lm,
      '_anchorMs': recv - ageMs,
    };
  }

  Future<void> _fetchDriverTrack(int requestId) async {
    if (_trackInFlight) return;
    if (kDevMockInstantDriverFound) {
      final t = activeTrip.value;
      if (t != null &&
          (int.tryParse(t['id']?.toString() ?? '') ?? 0) == requestId) {
        _applyDevMockUiExtras(t);
      }
      return;
    }
    _trackInFlight = true;
    try {
      final sentAt = DateTime.now();
      final r = await TripApiService.fetchCustomerTripTracking(requestId);
      final receivedAt = DateTime.fromMillisecondsSinceEpoch(
        (sentAt.millisecondsSinceEpoch + DateTime.now().millisecondsSinceEpoch) ~/
            2,
      );
      if (!r.ok) return;
      final data = r.data;
      if (data is! Map) {
        driverLivePos.value = null;
        return;
      }
      final dm = Map<String, dynamic>.from(data);
      LatLng? found;
      final pos = dm['driver_position'] ?? dm['driverPosition'];
      if (pos is Map) found = _latLngFromLooseMap(pos);
      found ??= _latLngFromLooseMap(dm);
      if (found == null) {
        final drv = dm['driver'];
        if (drv is Map) {
          final dmap = Map<String, dynamic>.from(drv);
          final lp = dmap['last_position'] ?? dmap['lastPosition'];
          if (lp is Map) found = _latLngFromLooseMap(lp);
        }
      }
      driverLivePos.value = found;

      final stNow = CustomerTripStatusHelpers.normTripStatus(
        activeTrip.value ?? const {},
      );
      if (stNow == 'Running') {
        final lm = dm['live_meter'] ?? dm['liveMeter'];
        if (lm is Map) {
          _applyLiveMeterSnapshot(
            Map<String, dynamic>.from(lm),
            serverTsMs: dm['server_ts_ms'],
            serverTs: dm['server_ts'],
            receivedAt: receivedAt,
          );
        }
      } else {
        liveTripMeter.value = null;
      }
    } catch (_) {
    } finally {
      _trackInFlight = false;
    }
  }

  void _applyDevMockUiExtras(
    Map<String, dynamic> trip, {
    String? previousStatus,
  }) {
    final id = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
    final st = CustomerTripStatusHelpers.normTripStatus(trip);
    final near = DevMockDriverTrip.mockDriverNearPickup(trip);
    if (near != null) driverLivePos.value = near;

    if (st == 'Running') {
      _applyLiveMeterSnapshot(
        DevMockDriverTrip.mockLiveMeter(
          elapsedSec: DevMockDriverTrip.runningElapsedSeconds(id),
        ),
      );
      if (previousStatus != null &&
          previousStatus != 'Running' &&
          id > 0 &&
          _startSoundPlayedForIds.add(id)) {
        unawaited(AppAlertSound.playTripStarted());
        AppSnackBar.notify('الرحلة', 'بدأت الرحلة — عداد التكلفة يعمل');
      }
    } else {
      liveTripMeter.value = null;
    }

    if (st == 'DriverArrived' &&
        previousStatus != null &&
        previousStatus != 'DriverArrived' &&
        previousStatus != 'Running' &&
        id > 0 &&
        _arrivedSnackPlayedForIds.add(id)) {
      AppSnackBar.notify('السائق', 'وصل السائق إليك');
    }
  }

  void _scheduleDevMockPhaseTick(Map<String, dynamic> trip) {
    _devMockPhaseTick?.cancel();
    final id = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
    if (id <= 0) return;
    final wait = DevMockDriverTrip.nextTickAfter(id);
    if (wait == null) {
      _devMockPhaseTick = Timer.periodic(const Duration(seconds: 2), (_) {
        final cur = activeTrip.value;
        if (cur == null) {
          _devMockPhaseTick?.cancel();
          return;
        }
        final curId = int.tryParse(cur['id']?.toString() ?? '') ?? 0;
        if (curId != id) {
          _devMockPhaseTick?.cancel();
          return;
        }
        if (CustomerTripStatusHelpers.normTripStatus(cur) == 'Running') {
          liveTripMeter.value = DevMockDriverTrip.mockLiveMeter(
            elapsedSec: DevMockDriverTrip.runningElapsedSeconds(id),
          );
        }
      });
      return;
    }
    _devMockPhaseTick = Timer(wait, () {
      final cur = activeTrip.value;
      if (cur == null) return;
      final curId = int.tryParse(cur['id']?.toString() ?? '') ?? 0;
      if (curId != id) return;
      final prevSt = CustomerTripStatusHelpers.normTripStatus(cur);
      final next = DevMockDriverTrip.apply(cur);
      final newSt = CustomerTripStatusHelpers.normTripStatus(next);
      if (newSt == prevSt) {
        _scheduleDevMockPhaseTick(next);
        return;
      }
      activeTrip.value = next;
      started.value = true;
      onMapUpdate?.call(CustomerTripMapUpdate.fromTrip(next));
      onScheduleRouteFetch?.call();
      _reschedulePollsIfNeeded(prevSt, newSt);
      _applyDevMockUiExtras(next, previousStatus: prevSt);
      _scheduleDevMockPhaseTick(next);
    });
  }

  static Map<String, dynamic>? _notificationDataMap(Map<String, dynamic> row) {
    final d = row['data'];
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    if (d is String && d.trim().isNotEmpty) {
      try {
        final j = json.decode(d);
        if (j is Map) return Map<String, dynamic>.from(j);
      } catch (_) {}
    }
    return null;
  }

  static int? _notificationRequestId(Map<String, dynamic>? data) {
    if (data == null) return null;
    final v = data['request_id'] ?? data['requestId'];
    if (v is int) return v;
    return int.tryParse(v?.toString() ?? '');
  }

  Future<void> _postScheduledPassengerReady(int requestId, bool ready) async {
    try {
      final r = await TripApiService.scheduledPassengerReady(requestId, ready);
      AppSnackBar.notify(
        r.ok ? 'تم' : 'تنبيه',
        r.ok ? (r.message ?? 'تم') : (r.message ?? 'تعذر الإرسال'),
      );
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
  }

  Future<void> _postScheduledPassengerWaitOrCancel(
    int requestId, {
    required bool wait,
  }) async {
    try {
      final r = await TripApiService.scheduledPassengerWaitOrCancel(
        requestId,
        wait: wait,
      );
      AppSnackBar.notify(
        r.ok ? 'تم' : 'تنبيه',
        r.ok ? (r.message ?? 'تم') : (r.message ?? 'تعذر الإرسال'),
      );
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
  }

  Future<void> _handleNotificationRow(Map<String, dynamic> row) async {
    final data = _notificationDataMap(row);
    final kind = data?['kind']?.toString() ?? '';
    final rid = _notificationRequestId(data);

    if (kind == 'sched_t5_ready' && rid != null && rid > 0) {
      final yes = await showSchedT5ReadyDialog?.call();
      await _postScheduledPassengerReady(rid, yes == true);
      return;
    }

    if (kind == 'sched_t30') {
      unawaited(AppAlertSound.playNotification());
      AppSnackBar.notify(
        row['title']?.toString() ?? 'تذكير بالرحلة',
        row['body']?.toString() ?? 'رحلتك المجدولة بعد حوالي 30 دقيقة.',
        duration: const Duration(seconds: 8),
      );
      return;
    }

    if (kind == 'sched_at_time_passenger') {
      unawaited(AppAlertSound.playNotification());
      AppSnackBar.notify(
        row['title']?.toString() ?? 'حان موعد رحلتك',
        row['body']?.toString() ?? 'السائق سيبدأ التوجه إليك قريباً.',
        duration: const Duration(seconds: 8),
      );
      return;
    }

    if (kind == 'sched_driver_busy' && rid != null && rid > 0) {
      final wait = await showSchedDriverBusyDialog?.call();
      await _postScheduledPassengerWaitOrCancel(
        rid,
        wait: wait == true,
      );
      return;
    }

    if (kind == 'sched_rejected' && rid != null && rid > 0) {
      AppSnackBar.notify(
        row['title']?.toString() ?? 'اعتذر السائق',
        row['body']?.toString() ?? 'اختر سائقاً آخر للحجز المسبق',
        duration: const Duration(seconds: 8),
      );
      await onSchedRejectedRechoose?.call(rid);
      return;
    }

    final title = row['title']?.toString() ?? 'إشعار';
    final body = row['body']?.toString() ?? '';
    AppSnackBar.notify(title, body, duration: const Duration(seconds: 6));
  }

  Future<void> pollNotifications() async {
    final box = GetStorage();
    if (box.read('user_roll')?.toString() != 'Customer') return;
    try {
      final n = await TripApiService.customerNotificationsUnreadCount();
      if (n <= 0) return;
      final rows = await TripApiService.fetchCustomerNotifications();
      for (final row in rows) {
        final nid = int.tryParse(row['id']?.toString() ?? '') ?? 0;
        if (nid <= 0) continue;
        if (row['read_at'] != null) continue;
        if (_shownNotificationIds.contains(nid)) continue;
        _shownNotificationIds.add(nid);
        await _handleNotificationRow(row);
        await TripApiService.markCustomerNotificationRead(nid);
        await refreshActiveTrip();
      }
    } catch (_) {}
  }

  Future<void> confirmDriverArrived(int requestId) async {
    try {
      final r = await TripApiService.confirmDriverArrived(requestId);
      if (r.ok) {
        AppSnackBar.notify('تم', 'تم تأكيد وصول السائق');
        await onReloadMyRequests?.call();
        await refreshActiveTrip();
      } else {
        AppSnackBar.notify('فشل', r.message ?? 'تعذر التأكيد');
      }
    } catch (e) {
      AppSnackBar.notify('خطأ', '$e');
    }
  }
}
