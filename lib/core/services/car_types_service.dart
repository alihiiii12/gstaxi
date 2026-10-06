import 'dart:convert';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../network/api_endpoints.dart';
import '../utils/car_category_visual.dart';

/// جلب فئات التسعير (مكيفة، اقتصادي…) للراكب.
class CarTypesService {
  CarTypesService._();

  static const _cacheKey = 'cached_customer_car_types_v3';
  static final _box = GetStorage();

  static List<Map<String, dynamic>> readCached() {
    final raw = _box.read(_cacheKey);
    final list = _parseList(raw);
    if (list.isNotEmpty) sortInPlace(list);
    return list;
  }

  static Future<List<Map<String, dynamic>>> fetch({
    bool preferCache = true,
  }) async {
    if (preferCache) {
      final cached = readCached();
      if (cached.isNotEmpty) return cached;
    }

    final res = await http
        .get(
          Uri.parse(ApiEndpoints.carTypesIndex),
          headers: await ApiEndpoints.headers(),
        )
        .timeout(const Duration(seconds: 15));

    final list = _parseHttpResponse(res.body, res.statusCode);
    if (list.isEmpty) {
      throw CarTypesLoadException(
        'empty',
        'لم تُرجع الواجهة أي فئات (HTTP ${res.statusCode})',
      );
    }

    final filtered = _filterForCustomer(list);
    final out = filtered.isNotEmpty ? filtered : list;
    sortInPlace(out);
    await _box.write(_cacheKey, out);
    return out;
  }

  /// يعرض المخزّن فوراً ثم يحدّث من الشبكة.
  static Future<List<Map<String, dynamic>>> fetchWithCacheFirst() async {
    final cached = readCached();
    try {
      final fresh = await fetch(preferCache: false);
      return fresh;
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  static List<Map<String, dynamic>> _parseHttpResponse(
    String body,
    int statusCode,
  ) {
    if (statusCode < 200 || statusCode >= 300) {
      throw CarTypesLoadException(
        'http',
        'خطأ من الخادم ($statusCode)',
      );
    }
    dynamic decoded;
    try {
      decoded = json.decode(body);
    } catch (_) {
      throw CarTypesLoadException('json', 'استجابة غير صالحة من الخادم');
    }
    if (decoded is! Map) {
      throw CarTypesLoadException('shape', 'شكل الاستجابة غير متوقع');
    }
    final map = Map<String, dynamic>.from(decoded);
    final ok = map['success'] == true ||
        map['success'] == 1 ||
        map['success']?.toString() == 'true';
    if (!ok && map.containsKey('success')) {
      throw CarTypesLoadException(
        'api',
        map['message']?.toString() ?? 'فشل جلب الفئات',
      );
    }
    return _parseList(
      map['carTypes'] ?? map['car_types'] ?? map['data'],
    );
  }

  static List<Map<String, dynamic>> _parseList(dynamic raw) {
    if (raw is! List || raw.isEmpty) return [];
    final out = <Map<String, dynamic>>[];
    for (final e in raw) {
      if (e is Map) {
        out.add(Map<String, dynamic>.from(e));
      }
    }
    return out;
  }

  static List<Map<String, dynamic>> _filterForCustomer(
    List<Map<String, dynamic>> list,
  ) {
    return list
        .where(
          (e) => (e['name']?.toString().trim() ?? '') != 'العداد الحر',
        )
        .toList();
  }

  /// ترتيب العرض: بدّل مواضع الاقتصادي والمكيفة بعد ترتيب sort_order.
  static void sortInPlace(List<Map<String, dynamic>> list) {
    list.sort((a, b) {
      final sa = int.tryParse(a['sort_order']?.toString() ?? '') ??
          int.tryParse(a['sortOrder']?.toString() ?? '') ??
          0;
      final sb = int.tryParse(b['sort_order']?.toString() ?? '') ??
          int.tryParse(b['sortOrder']?.toString() ?? '') ??
          0;
      if (sa != sb) return sa.compareTo(sb);
      final ia = int.tryParse(a['id']?.toString() ?? '') ?? 0;
      final ib = int.tryParse(b['id']?.toString() ?? '') ?? 0;
      return ia.compareTo(ib);
    });

    int? economyIdx;
    int? acIdx;
    for (var i = 0; i < list.length; i++) {
      final e = list[i];
      if (economyIdx == null && CarCategoryVisual.isEconomyCategory(e)) {
        economyIdx = i;
      }
      if (acIdx == null && CarCategoryVisual.isAirConditionedCategory(e)) {
        acIdx = i;
      }
    }
    // تبديل حقيقي بين مواضع الفئتين.
    if (economyIdx != null && acIdx != null && economyIdx != acIdx) {
      final tmp = list[acIdx];
      list[acIdx] = list[economyIdx];
      list[economyIdx] = tmp;
    }
  }
}

class CarTypesLoadException implements Exception {
  CarTypesLoadException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => message;
}
