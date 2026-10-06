import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../../../core/network/api_endpoints.dart';

class TripsHistoryController extends GetxController {
  final box = GetStorage();
  var loading = false.obs;
  var trips = <Map<String, dynamic>>[].obs;
  var error = ''.obs;

  static bool isFreeMeterTrip(Map<String, dynamic> hist) {
    final req = hist['request'];
    if (req is! Map) return false;
    final billing = '${req['billing_kind'] ?? req['billingKind'] ?? ''}'
        .trim()
        .toLowerCase();
    if (billing.contains('free_meter') || billing.contains('freemeter')) {
      return true;
    }
    final isApp = req['is_app_request'] ?? req['isAppRequest'];
    if (isApp == false || isApp == 0 || isApp == '0' || isApp == 'false') {
      return true;
    }
    final desc = '${req['description'] ?? ''}'.toLowerCase();
    if (desc.contains('عداد') ||
        desc.contains('free_meter') ||
        desc.contains('freemeter')) {
      return true;
    }
    final path = '${req['path_label'] ?? req['pathLabel'] ?? ''}'.toLowerCase();
    return path.contains('عداد') || path.contains('free');
  }

  List<Map<String, dynamic>> get appTrips =>
      trips.where((t) => !isFreeMeterTrip(t)).toList(growable: false);

  List<Map<String, dynamic>> get freeMeterTrips =>
      trips.where(isFreeMeterTrip).toList(growable: false);

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final driverId = box.read('driver_id');
    if (driverId == null) {
      error.value = 'لا يوجد معرف سائق — أعد تسجيل الدخول';
      return;
    }

    loading.value = true;
    error.value = '';
    try {
      final id = driverId is int ? driverId : int.parse(driverId.toString());
      final res = await http.get(
        Uri.parse(ApiEndpoints.driverTrips(id)),
        headers: await ApiEndpoints.headers(),
      );
      final map = json.decode(res.body) as Map<String, dynamic>;
      if (res.statusCode == 200 && map['success'] == true) {
        final list = map['data'] as List<dynamic>? ?? [];
        final normalized = <Map<String, dynamic>>[];
        for (final e in list) {
          final hist = Map<String, dynamic>.from(e as Map);
          final reqRaw = hist['request'];
          if (reqRaw is! Map) continue;
          final r = Map<String, dynamic>.from(reqRaw);
          final status = (r['status'] ?? '').toString();
          // سجل الرحلات المنفَّذة فقط
          if (status != 'Finished') continue;
          normalized.add({
            'request': {
              ...r,
              'history': {
                'finalCost': hist['finalCost'] ?? hist['final_cost'],
                'distanceTraveledKm':
                    hist['distanceTraveledKm'] ?? hist['distance_traveled_km'],
              },
            },
            'finalCost': hist['finalCost'] ?? hist['final_cost'],
            'created_at': hist['created_at'] ??
                hist['createdAt'] ??
                r['request_date'] ??
                r['requestDate'] ??
                r['created_at'] ??
                r['createdAt'],
          });
        }

        trips.assignAll(normalized);
      } else {
        error.value = map['message']?.toString() ?? 'تعذر تحميل السجل';
      }
    } catch (e) {
      error.value = e.toString();
    }
    loading.value = false;
  }
}
