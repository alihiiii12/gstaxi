import 'dart:async';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/driver_poll_intervals.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/network/http_timeouts.dart';
import '../../../core/services/trip_api_service.dart';
import '../../../core/utils/driver_order_display.dart';
import '../../../core/utils/utf8_text.dart';
import '../controller/driver_assigned_trip_controller.dart';
import '../controller/driver_location_controller.dart';
import '../../Order/controller/immediate_bookings_controller.dart';

/// استطلاع موحّد للسائق: طلب واحد (أو اثنان بالتوازي) بدل تكرار
/// `immediate-pending` + `requests/driver/{id}` كل ثانيتين من أكثر من controller.
class DriverServerSyncService extends GetxController {
  Timer? _timer;
  Timer? _reconfigureDebounce;
  bool _inFlight = false;
  bool _pendingForceSync = false;
  DateTime? _lastSyncStarted;
  bool _useCombinedEndpoint = true;
  int _consecutiveErrors = 0;

  final immediatePending = <Map<String, dynamic>>[].obs;
  final driverRequests = <Map<String, dynamic>>[].obs;
  final syncError = ''.obs;
  final syncing = false.obs;

  DriverController? get _driver =>
      Get.isRegistered<DriverController>() ? Get.find<DriverController>() : null;

  DriverAssignedTripController? get _trip =>
      Get.isRegistered<DriverAssignedTripController>()
          ? Get.find<DriverAssignedTripController>()
          : null;

  ImmediateBookingsController? get _immediate =>
      Get.isRegistered<ImmediateBookingsController>()
          ? Get.find<ImmediateBookingsController>()
          : null;

  @override
  void onInit() {
    super.onInit();
    if (_driver != null) {
      ever(_driver!.isOnline, (_) => _reconfigureTimer());
      ever(_driver!.isTripActive, (_) => _reconfigureTimer());
    }
  }

  @override
  void onReady() {
    super.onReady();
    final t = _trip;
    if (t != null) {
      ever(t.assignedRequest, (_) => _reconfigureTimer());
      ever(t.upcomingScheduled, (_) => _reconfigureTimer());
    }
    final d = _driver;
    if (d != null) {
      ever(d.acceptedTripPreview, (_) => _reconfigureTimer());
    }
    _reconfigureTimer();
  }

  @override
  void onClose() {
    _timer?.cancel();
    _reconfigureDebounce?.cancel();
    super.onClose();
  }

  void onAppResumed() => syncNow(force: true);

  bool get _shouldPoll {
    final d = _driver;
    if (d == null || !d.isOnline.value) return false;
    // أثناء العداد الحر لا تُستقبل طلبات التطبيق.
    if (d.isTripActive.value) return false;
    return true;
  }

  bool get _hasActiveTripContext {
    final t = _trip;
    if (t == null) return false;
    if (t.assignedRequest.value != null) return true;
    final upcoming = t.upcomingScheduled.value;
    if (upcoming != null && scheduledGoWindowOpen(upcoming)) return true;
    final preview = _driver?.acceptedTripPreview.value;
    return preview != null;
  }

  Duration get _interval {
    if (_consecutiveErrors >= 2) return DriverPollIntervals.errorBackoff;
    return _hasActiveTripContext
        ? DriverPollIntervals.activeTrip
        : DriverPollIntervals.idleOnline;
  }

  void _reconfigureTimer() {
    _reconfigureDebounce?.cancel();
    _reconfigureDebounce = Timer(const Duration(milliseconds: 350), _applyTimerConfig);
  }

  void _applyTimerConfig() {
    _timer?.cancel();
    _timer = null;
    if (!_shouldPoll) return;

    final interval = _interval;
    unawaited(syncNow(force: true));
    _timer = Timer.periodic(interval, (_) => syncNow());
  }

  /// تحديث فوري بعد قبول/رفض/وصول — مع احترام [DriverPollIntervals.minGap].
  Future<void> syncNow({bool force = false}) async {
    if (!_shouldPoll && !force) return;
    if (_inFlight) {
      if (force) _pendingForceSync = true;
      return;
    }

    final now = DateTime.now();
    if (!force &&
        _lastSyncStarted != null &&
        now.difference(_lastSyncStarted!) < DriverPollIntervals.minGap) {
      return;
    }

    _inFlight = true;
    syncing.value = true;
    syncError.value = '';
    _lastSyncStarted = now;

    try {
      List<Map<String, dynamic>> pending;
      List<Map<String, dynamic>> assigned;

      if (_useCombinedEndpoint) {
        final snap = await TripApiService.fetchDriverPollSnapshot();
        if (snap.ok) {
          final d = snap.dataMap;
          pending = _rows(d?['immediate_pending']);
          assigned = _rows(d?['driver_requests']);
          _onSyncSuccess();
        } else if (snap.statusCode == 404) {
          _useCombinedEndpoint = false;
          final pair = await _fetchLegacyParallel();
          pending = pair.$1;
          assigned = pair.$2;
          _onSyncSuccess();
        } else {
          syncError.value = snap.message ?? 'تعذر المزامنة';
          _onSyncError();
          return;
        }
      } else {
        final pair = await _fetchLegacyParallel();
        pending = pair.$1;
        assigned = pair.$2;
        _onSyncSuccess();
      }

      immediatePending.assignAll(pending);
      driverRequests.assignAll(assigned);

      await Future.wait<void>([
        if (_immediate != null)
          _immediate!.applyServerSync(
            pending: pending,
            assignedImmediate: assigned,
          )
        else
          Future<void>.value(),
        if (_trip != null)
          _trip!.pollAssignedRequests(prefetched: assigned)
        else
          Future<void>.value(),
      ]);
    } catch (e) {
      syncError.value = e.toString();
      _onSyncError();
    } finally {
      _inFlight = false;
      syncing.value = false;
      if (_pendingForceSync) {
        _pendingForceSync = false;
        unawaited(syncNow(force: true));
      }
    }
  }

  void _onSyncSuccess() {
    if (_consecutiveErrors > 0) {
      _consecutiveErrors = 0;
      _reconfigureTimer();
    }
  }

  void _onSyncError() {
    _consecutiveErrors++;
    if (_consecutiveErrors == 2) {
      _reconfigureTimer();
    }
  }

  Future<(List<Map<String, dynamic>>, List<Map<String, dynamic>>)>
      _fetchLegacyParallel() async {
    final box = GetStorage();
    final driverIdRaw = box.read('driver_id');
    final did = driverIdRaw is int
        ? driverIdRaw
        : int.tryParse(driverIdRaw?.toString() ?? '');

    final headers = await ApiEndpoints.headers();
    final pendingFuture = http
        .get(
          Uri.parse(ApiEndpoints.immediatePendingRequests),
          headers: headers,
        )
        .timeout(HttpTimeouts.poll);

    Future<http.Response>? assignedFuture;
    if (did != null && did > 0) {
      assignedFuture = http
          .get(
            Uri.parse(ApiEndpoints.driverRequests(did)),
            headers: headers,
          )
          .timeout(HttpTimeouts.poll);
    }

    final pendingRes = await pendingFuture;
    final pendingDecoded = decodeJsonUtf8(pendingRes);
    final pending = (pendingRes.statusCode == 200 &&
            pendingDecoded is Map &&
            pendingDecoded['success'] == true)
        ? _rows(pendingDecoded['data'])
        : <Map<String, dynamic>>[];

    var assigned = <Map<String, dynamic>>[];
    if (assignedFuture != null) {
      final assignedRes = await assignedFuture;
      final assignedDecoded = decodeJsonUtf8(assignedRes);
      if (assignedRes.statusCode == 200 &&
          assignedDecoded is Map &&
          assignedDecoded['success'] == true) {
        assigned = _rows(assignedDecoded['data']);
      }
    }

    return (pending, assigned);
  }

  static List<Map<String, dynamic>> _rows(dynamic raw) {
    if (raw is! List) return [];
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }
}
