import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_endpoints.dart';
import '../../../core/utils/driver_order_display.dart';
import '../../Home/controller/driver_location_controller.dart';

class BookingsController extends GetxController {
  var loading = false.obs;
  var bookings = <Map<String, dynamic>>[].obs;
  var error = ''.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      final headers = await ApiEndpoints.headers();
      final avRes = await http.get(
        Uri.parse(ApiEndpoints.availableBookings),
        headers: headers,
      );
      final avMap = json.decode(avRes.body) as Map<String, dynamic>;
      if (avRes.statusCode != 200 || avMap['success'] != true) {
        error.value = avMap['message']?.toString() ?? 'تعذر تحميل الحجوزات';
        loading.value = false;
        return;
      }
      final availableList = avMap['data'] as List<dynamic>? ?? [];

      final box = GetStorage();
      final driverIdRaw = box.read('driver_id');
      final did = driverIdRaw is int
          ? driverIdRaw
          : int.tryParse(driverIdRaw?.toString() ?? '');

      final byId = <int, Map<String, dynamic>>{};

      for (final e in availableList) {
        final m = Map<String, dynamic>.from(e as Map);
        if (!requestIsScheduled(m)) continue;
        final id = int.tryParse(m['id']?.toString() ?? '') ?? 0;
        if (id > 0) byId[id] = m;
      }

      if (did != null && did > 0) {
        final drRes = await http.get(
          Uri.parse(ApiEndpoints.driverRequests(did)),
          headers: headers,
        );
        final drMap = json.decode(drRes.body) as Map<String, dynamic>;
        if (drRes.statusCode == 200 && drMap['success'] == true) {
          final driverList = drMap['data'] as List<dynamic>? ?? [];
          for (final e in driverList) {
            final m = Map<String, dynamic>.from(e as Map);
            if (!requestIsScheduled(m)) continue;
            final id = int.tryParse(m['id']?.toString() ?? '') ?? 0;
            if (id > 0) byId[id] = m;
          }
        }

        // سجل الحجوزات المسبقة المنتهية
        final tripsRes = await http.get(
          Uri.parse(ApiEndpoints.driverTrips(did)),
          headers: headers,
        );
        final tripsMap = json.decode(tripsRes.body) as Map<String, dynamic>;
        if (tripsRes.statusCode == 200 && tripsMap['success'] == true) {
          final tripsList = tripsMap['data'] as List<dynamic>? ?? [];
          for (final e in tripsList) {
            if (e is! Map) continue;
            final hist = Map<String, dynamic>.from(e);
            final reqRaw = hist['request'];
            if (reqRaw is! Map) continue;
            final m = Map<String, dynamic>.from(reqRaw);
            if (!requestIsScheduled(m)) continue;
            if (normTripStatusForOrder(m) != 'Finished') continue;
            final id = int.tryParse(m['id']?.toString() ?? '') ?? 0;
            if (id <= 0) continue;
            if (hist['finalCost'] != null || hist['final_cost'] != null) {
              m['history'] = {
                'finalCost': hist['finalCost'] ?? hist['final_cost'],
                'distanceTraveledKm':
                    hist['distanceTraveledKm'] ?? hist['distance_traveled_km'],
              };
            }
            byId.putIfAbsent(id, () => m);
          }
        }
      }

      final merged = byId.values.toList()
        ..sort(compareDriverOrdersRecentFirst);
      bookings.assignAll(merged);
    } catch (e) {
      error.value = e.toString();
    }
    loading.value = false;
  }

  /// يعيد نصاً فارغاً عند الفشل، ورسالة الخادم عند النجاح.
  Future<String> accept(int requestId) async {
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.acceptBooking(requestId)),
        headers: await ApiEndpoints.headers(),
        body: jsonEncode(<String, dynamic>{}),
      );
      final map = json.decode(res.body) as Map<String, dynamic>;
      final httpOk = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          map['success'] == true;
      if (httpOk) {
        final raw = map['message']?.toString().trim();
        if (Get.isRegistered<DriverController>()) {
          Get.find<DriverController>().notifyAssignedTripRefresh();
        }
        return (raw != null && raw.isNotEmpty)
            ? raw
            : 'تم قبول الحجز — الموعد مثبت. سيُفعَّل الطلب عند الوقت المحدد.';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// رفض حجز مسبق معلّق — إبلاغ الزبون لاختيار سائق آخر.
  Future<String> decline(int requestId) async {
    try {
      final res = await http.post(
        Uri.parse(ApiEndpoints.driverDeclineScheduled(requestId)),
        headers: await ApiEndpoints.headers(),
        body: jsonEncode(<String, dynamic>{}),
      );
      final map = json.decode(res.body) as Map<String, dynamic>;
      final httpOk = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          map['success'] == true;
      if (httpOk) {
        bookings.removeWhere(
          (b) => (int.tryParse(b['id']?.toString() ?? '') ?? 0) == requestId,
        );
        final raw = map['message']?.toString().trim();
        return (raw != null && raw.isNotEmpty) ? raw : 'تم رفض الحجز';
      }
      return map['message']?.toString() ?? '';
    } catch (_) {
      return '';
    }
  }
}
