import 'dart:async';
import '../../../core/constants/snack_bar.dart';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_endpoints.dart';
import '../../../core/network/http_timeouts.dart';
import '../../../core/services/trip_api_service.dart';
import '../../../core/utils/utf8_text.dart';
import '../../../core/utils/driver_order_display.dart';
import '../../Home/controller/driver_location_controller.dart';
import '../../Home/service/driver_server_sync_service.dart';
import 'immediate_accept_result.dart';

/// قائمة طلبات فورية — تُحدَّث من [DriverServerSyncService] (بدون استطلاع مستقل).
class ImmediateBookingsController extends GetxController {
  static const _kIgnoredIds = 'driver_ignored_immediate_ids';

  var loading = false.obs;
  var bookings = <Map<String, dynamic>>[].obs;
  var error = ''.obs;

  final Set<int> _seenIds = <int>{};
  final Set<int> _previousPendingIds = <int>{};
  final Set<int> _ignoredIds = <int>{};
  int? _skipRemovedNoticeOnceForId;

  /// سجل الطلبات الفورية المنتهية — يُدمَج بعد كل مزامنة حية حتى لا تختفي.
  final Map<int, Map<String, dynamic>> _finishedHistoryById = {};
  DateTime? _finishedHistoryFetchedAt;

  @override
  void onInit() {
    super.onInit();
    _loadIgnoredIds();
    unawaited(_refreshFinishedImmediateHistory());
  }

  void _loadIgnoredIds() {
    _ignoredIds.clear();
    final raw = GetStorage().read(_kIgnoredIds);
    if (raw is List) {
      for (final e in raw) {
        final id = e is int ? e : int.tryParse('$e');
        if (id != null && id > 0) _ignoredIds.add(id);
      }
    }
  }

  Future<void> _persistIgnoredIds() async {
    await GetStorage().write(_kIgnoredIds, _ignoredIds.toList());
  }

  bool isIgnored(int requestId) => _ignoredIds.contains(requestId);

  /// تجاهل محلي لهذا السائق فقط — لا يُلغى الطلب ولا يُمنع باقي السائقين.
  Future<void> ignoreImmediateForMe(int requestId) async {
    if (requestId <= 0) return;
    _ignoredIds.add(requestId);
    _skipRemovedNoticeOnceForId = requestId;
    await _persistIgnoredIds();
    bookings.removeWhere(
      (r) => int.tryParse(r['id']?.toString() ?? '') == requestId,
    );
    _finishedHistoryById.remove(requestId);
  }

  /// يُستدعى من خدمة المزامنة الموحّدة بعد كل دورة ناجحة.
  Future<void> applyServerSync({
    required List<Map<String, dynamic>> pending,
    required List<Map<String, dynamic>> assignedImmediate,
  }) async {
    error.value = '';
    try {
      final pendingRows = pending
          .map((e) => Map<String, dynamic>.from(e))
          .where((r) {
            final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
            return id <= 0 || !_ignoredIds.contains(id);
          })
          .toList();

      final pendingAllIds = <int>{};
      for (final r in pending) {
        final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
        if (id > 0) pendingAllIds.add(id);
      }

      // قارن مع كل الطلبات القادمة من الخادم (وليس المفلترة بالتجاهل).
      final removedIds = _previousPendingIds
          .where((oldId) => !pendingAllIds.contains(oldId))
          .toList();
      if (removedIds.isNotEmpty) {
        List<Map<String, dynamic>>? cachedNotes;
        var ignoredChanged = false;
        for (final oldId in removedIds) {
          // طلب تجاهله هذا السائق ثم انتهى من الخادم — بلا إشعار.
          if (_ignoredIds.remove(oldId)) {
            ignoredChanged = true;
            continue;
          }
          if (_skipRemovedNoticeOnceForId == oldId) {
            _skipRemovedNoticeOnceForId = null;
            continue;
          }
          if (Get.isRegistered<DriverController>()) {
            Get.find<DriverController>().clearAcceptedTripPreviewIfIdsMatch(oldId);
          }
          cachedNotes ??= await TripApiService.fetchDriverNotifications();
          final takenByOther =
              _notificationIndicatesTakenByOther(cachedNotes, oldId);
          if (takenByOther) {
            AppSnackBar.notify(
              'تم قبول الطلب',
              'تم قبول الطلب #$oldId من سائق آخر',
              duration: const Duration(seconds: 6),
            );
          } else {
            AppSnackBar.notify(
              'تم إلغاء الطلب',
              'أُلغي الطلب الفوري #$oldId أو لم يعد متاحاً',
              duration: const Duration(seconds: 5),
            );
          }
        }
        if (ignoredChanged) unawaited(_persistIgnoredIds());
      }

      _previousPendingIds
        ..clear()
        ..addAll(pendingAllIds);

      final byId = <int, Map<String, dynamic>>{};

      for (final m in assignedImmediate) {
        if (!requestIsImmediate(m)) continue;
        final id = int.tryParse(m['id']?.toString() ?? '') ?? 0;
        if (id > 0 && !_ignoredIds.contains(id)) {
          byId[id] = Map<String, dynamic>.from(m);
        }
      }

      for (final r in pendingRows) {
        final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
        if (id > 0) byId[id] = Map<String, dynamic>.from(r);
      }

      // أعد دمج السجل المنتهي بعد كل مزامنة حية (لا تُمسَح القائمة).
      for (final e in _finishedHistoryById.entries) {
        byId.putIfAbsent(e.key, () => Map<String, dynamic>.from(e.value));
      }

      final merged = byId.values.toList()..sort(compareDriverOrdersRecentFirst);
      bookings.assignAll(merged);

      for (final r in pendingRows) {
        final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
        if (id <= 0) continue;
        if (normTripStatusForOrder(r) != 'Pending') continue;
        _seenIds.add(id);
      }

      // حدّث السجل المنتهي بهدوء كل دقيقة تقريباً.
      final last = _finishedHistoryFetchedAt;
      if (last == null ||
          DateTime.now().difference(last) > const Duration(minutes: 1)) {
        unawaited(_refreshFinishedImmediateHistory(reassignList: true));
      }
    } catch (e) {
      error.value = e.toString();
    }
  }

  static bool _notificationIndicatesTakenByOther(
    List<Map<String, dynamic>> notes,
    int requestId,
  ) {
    for (final n in notes) {
      final kind = n['kind']?.toString() ?? '';
      final ref = int.tryParse(n['reference_id']?.toString() ?? '') ??
          int.tryParse(
            (n['payload'] is Map
                    ? (n['payload'] as Map)['request_id']
                    : null)
                ?.toString() ??
                '',
          ) ??
          0;
      if (kind == 'immediate.taken_by_other' && ref == requestId) {
        return true;
      }
    }
    return false;
  }

  /// للتوافق مع الشاشات التي كانت تستدعي load() — يطلب مزامنة فورية + سجل منتهٍ.
  Future<void> load() async {
    loading.value = true;
    try {
      await _refreshFinishedImmediateHistory(reassignList: false);
      if (Get.isRegistered<DriverServerSyncService>()) {
        await Get.find<DriverServerSyncService>().syncNow(force: true);
      } else {
        _publishMergedBookings(liveById: {});
      }
    } finally {
      loading.value = false;
    }
  }

  /// يحمّل الطلبات الفورية المنتهية ويخزّنها للدمج مع المزامنة الحية.
  Future<void> _refreshFinishedImmediateHistory({
    bool reassignList = false,
  }) async {
    try {
      final box = GetStorage();
      final driverIdRaw = box.read('driver_id');
      final did = driverIdRaw is int
          ? driverIdRaw
          : int.tryParse(driverIdRaw?.toString() ?? '');
      if (did == null || did <= 0) return;

      final res = await http
          .get(
            Uri.parse(ApiEndpoints.driverTrips(did)),
            headers: await ApiEndpoints.headers(),
          )
          .timeout(HttpTimeouts.api);
      final decoded = decodeJsonUtf8(res);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      if (res.statusCode != 200 || map['success'] != true) return;

      final list = map['data'] as List<dynamic>? ?? [];
      final next = <int, Map<String, dynamic>>{};
      for (final e in list) {
        if (e is! Map) continue;
        final hist = Map<String, dynamic>.from(e);
        final reqRaw = hist['request'];
        if (reqRaw is! Map) continue;
        final r = Map<String, dynamic>.from(reqRaw);
        if (!requestIsImmediate(r)) continue;
        if (normTripStatusForOrder(r) != 'Finished') continue;
        final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
        if (id <= 0 || _ignoredIds.contains(id)) continue;
        if (hist['finalCost'] != null || hist['final_cost'] != null) {
          r['history'] = {
            'finalCost': hist['finalCost'] ?? hist['final_cost'],
            'distanceTraveledKm':
                hist['distanceTraveledKm'] ?? hist['distance_traveled_km'],
          };
        }
        next[id] = r;
      }

      _finishedHistoryById
        ..clear()
        ..addAll(next);
      _finishedHistoryFetchedAt = DateTime.now();

      if (reassignList) {
        final liveById = <int, Map<String, dynamic>>{};
        for (final r in bookings) {
          final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
          if (id <= 0) continue;
          // لا تستبدل صفوف السجل الحيّة (غير Finished) من الكاش.
          if (normTripStatusForOrder(r) == 'Finished') continue;
          liveById[id] = Map<String, dynamic>.from(r);
        }
        _publishMergedBookings(liveById: liveById);
      }
    } catch (_) {}
  }

  void _publishMergedBookings({
    required Map<int, Map<String, dynamic>> liveById,
  }) {
    final byId = <int, Map<String, dynamic>>{
      for (final e in liveById.entries) e.key: e.value,
    };
    for (final e in _finishedHistoryById.entries) {
      byId.putIfAbsent(e.key, () => Map<String, dynamic>.from(e.value));
    }
    final merged = byId.values.toList()..sort(compareDriverOrdersRecentFirst);
    bookings.assignAll(merged);
  }

  Future<ImmediateAcceptResult> acceptWithResult(int requestId) async {
    try {
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.acceptBooking(requestId)),
            headers: await ApiEndpoints.headers(),
            body: jsonEncode(<String, dynamic>{}),
          )
          .timeout(HttpTimeouts.api);
      final decoded = decodeJsonUtf8(res);
      final map = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
      final httpOk = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          map['success'] == true;
      if (httpOk) {
        _skipRemovedNoticeOnceForId = requestId;
        _ignoredIds.remove(requestId);
        unawaited(_persistIgnoredIds());
        if (Get.isRegistered<DriverServerSyncService>()) {
          unawaited(Get.find<DriverServerSyncService>().syncNow(force: true));
        }
        final raw = map['message']?.toString().trim();
        return ImmediateAcceptResult(
          ok: true,
          message: (raw != null && raw.isNotEmpty) ? raw : 'تم',
        );
      }
      final code = map['code']?.toString() ?? '';
      final msg = map['message']?.toString().trim() ?? '';
      final taken = code == 'TAKEN_BY_OTHER' || msg.contains('سائق آخر');
      return ImmediateAcceptResult(
        ok: false,
        message: msg.isNotEmpty ? msg : 'تعذر القبول',
        takenByOther: taken,
      );
    } on TimeoutException {
      return const ImmediateAcceptResult(
        ok: false,
        message: 'انتهت مهلة الاتصال بالخادم',
      );
    } catch (_) {
      return const ImmediateAcceptResult(ok: false, message: 'تعذر الاتصال');
    }
  }

  Future<String> accept(int requestId) async {
    final r = await acceptWithResult(requestId);
    return r.ok ? r.message : '';
  }
}
