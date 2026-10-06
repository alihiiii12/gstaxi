import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../network/api_endpoints.dart';
import '../network/http_timeouts.dart';

/// استجابة موحّدة من واجهة الرحلات.
class TripApiResult {
  const TripApiResult({
    required this.ok,
    required this.statusCode,
    this.message,
    this.data,
    this.raw,
  });

  final bool ok;
  final int statusCode;
  final String? message;
  final dynamic data;
  final Map<String, dynamic>? raw;

  List<Map<String, dynamic>> get dataList {
    final d = data;
    if (d is! List) return [];
    return [
      for (final e in d)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }

  Map<String, dynamic>? get dataMap {
    final d = data;
    if (d is Map<String, dynamic>) return d;
    if (d is Map) return Map<String, dynamic>.from(d);
    return null;
  }
}

/// طلبات HTTP المشتركة بين شاشة السائق والعميل.
class TripApiService {
  TripApiService._();

  static bool _preferCustomerActiveLight = true;
  static TripApiResult _parse(http.Response res) {
    Map<String, dynamic>? map;
    try {
      final j = json.decode(res.body);
      if (j is Map<String, dynamic>) map = j;
      if (j is Map) map = Map<String, dynamic>.from(j);
    } catch (_) {}
    final httpOk = res.statusCode >= 200 && res.statusCode < 300;
    final apiOk = map != null &&
        (map['success'] == true ||
            map['state'] == true ||
            map['status'] == true);
    String? message = map?['message']?.toString();
    if ((message == null || message.isEmpty) && map?['errors'] is Map) {
      final errors = Map<String, dynamic>.from(map!['errors'] as Map);
      final first = errors.values.isEmpty ? null : errors.values.first;
      if (first is List && first.isNotEmpty) {
        message = first.first.toString();
      } else if (first != null) {
        message = first.toString();
      }
    }
    if ((message == null || message.isEmpty) && !httpOk) {
      message = 'خطأ من السيرفر (${res.statusCode})';
    }
    return TripApiResult(
      ok: httpOk && apiOk,
      statusCode: res.statusCode,
      message: message,
      data: map?['data'],
      raw: map,
    );
  }

  static const _httpTimeout = HttpTimeouts.api;
  static const _pollTimeout = HttpTimeouts.poll;

  static Future<TripApiResult> _get(
    String url, {
    Duration timeout = _httpTimeout,
  }) async {
    try {
      final res = await http
          .get(Uri.parse(url), headers: await ApiEndpoints.headers())
          .timeout(timeout);
      return _parse(res);
    } on TimeoutException {
      return const TripApiResult(
        ok: false,
        statusCode: 408,
        message: 'انتهت مهلة الاتصال بالخادم',
      );
    } catch (e) {
      return TripApiResult(
        ok: false,
        statusCode: 500,
        message: 'تعذر الاتصال بالخادم',
      );
    }
  }

  static Future<TripApiResult> _post(
    String url, {
    Map<String, dynamic>? body,
    Duration timeout = _httpTimeout,
  }) async {
    try {
      final res = await http
          .post(
            Uri.parse(url),
            headers: await ApiEndpoints.headers(),
            body: jsonEncode(body ?? <String, dynamic>{}),
          )
          .timeout(timeout);
      return _parse(res);
    } on TimeoutException {
      return const TripApiResult(
        ok: false,
        statusCode: 408,
        message: 'انتهت مهلة الاتصال بالخادم',
      );
    } catch (e) {
      return const TripApiResult(
        ok: false,
        statusCode: 500,
        message: 'تعذر الاتصال بالخادم',
      );
    }
  }

  static Future<List<Map<String, dynamic>>> fetchUserRequests(int userId) async {
    final r = await _get(ApiEndpoints.userRequests(userId), timeout: _pollTimeout);
    return r.ok ? r.dataList : [];
  }

  /// طلب نشط خفيف للراكب — يُفضَّل على جلب كل الطلبات عند الاستطلاع.
  /// يُرجع `(ok: true, trip: null)` عند عدم وجود رحلة نشطة.
  /// يُرجع `ok: false` إن تعذّر المسار (fallback لقائمة كاملة).
  static Future<
      ({
        bool ok,
        Map<String, dynamic>? trip,
        bool noActive,
        List<Map<String, dynamic>> upcoming,
      })> fetchCustomerActiveTripLight() async {
    const none = <Map<String, dynamic>>[];
    if (!_preferCustomerActiveLight) {
      return (ok: false, trip: null, noActive: false, upcoming: none);
    }
    final r = await _get(
      ApiEndpoints.customerActiveTrip,
      timeout: _pollTimeout,
    );
    if (r.statusCode == 404) {
      // المسار غير متوفر على السيرفر — لا نعيد المحاولة كل دورة.
      _preferCustomerActiveLight = false;
      return (ok: false, trip: null, noActive: false, upcoming: none);
    }
    final upRaw = r.raw?['upcoming_scheduled'];
    final upcoming = <Map<String, dynamic>>[
      if (upRaw is List)
        for (final e in upRaw)
          if (e is Map) Map<String, dynamic>.from(e),
    ];
    if (!r.ok) {
      // بعض السيرفرات تُرجع success مع data=null عندما لا توجد رحلة.
      if (r.statusCode >= 200 &&
          r.statusCode < 300 &&
          (r.data == null || (r.data is List && (r.data as List).isEmpty))) {
        return (ok: true, trip: null, noActive: true, upcoming: upcoming);
      }
      return (ok: false, trip: null, noActive: false, upcoming: none);
    }
    final map = r.dataMap;
    if (map != null && map.isNotEmpty) {
      return (ok: true, trip: map, noActive: false, upcoming: upcoming);
    }
    if (r.data is List) {
      final list = r.dataList;
      if (list.isNotEmpty) {
        return (ok: true, trip: list.first, noActive: false, upcoming: upcoming);
      }
    }
    return (ok: true, trip: null, noActive: true, upcoming: upcoming);
  }

  static Future<List<Map<String, dynamic>>> fetchDriverRequests(int driverId) async {
    final r = await _get(
      ApiEndpoints.driverRequests(driverId),
      timeout: _pollTimeout,
    );
    if (!r.ok) return [];
    return r.dataList;
  }

  /// استطلاع موحّد للسائق (طلب واحد بدل immediate-pending + driver/{id}).
  static Future<TripApiResult> fetchDriverPollSnapshot() =>
      _get(ApiEndpoints.driverPollSnapshot, timeout: _pollTimeout);

  static Future<TripApiResult> fetchDrivingSummary({
    required LatLng from,
    required LatLng to,
  }) =>
      _post(
        ApiEndpoints.drivingSummary,
        body: {
          'from_lat': from.latitude,
          'from_lng': from.longitude,
          'to_lat': to.latitude,
          'to_lng': to.longitude,
        },
      );

  static Future<TripApiResult> fetchCustomerTripTracking(int requestId) =>
      _get(
        ApiEndpoints.customerTripTracking(requestId),
        timeout: HttpTimeouts.poll,
      );

  static Future<TripApiResult> driverArrived(int requestId) =>
      _post(ApiEndpoints.driverArrived(requestId));

  static Future<TripApiResult> startTrip(int requestId) =>
      _post(ApiEndpoints.startTrip(requestId));

  static Future<TripApiResult> finishTrip(
    int requestId, {
    Map<String, dynamic>? body,
  }) =>
      _post(
        ApiEndpoints.finishTrip(requestId),
        body: body,
        timeout: HttpTimeouts.finishTrip,
      );

  static Future<TripApiResult> startFreeMeter({
    double? latitude,
    double? longitude,
  }) {
    final body = <String, dynamic>{};
    if (latitude != null && longitude != null) {
      body['latitude'] = latitude;
      body['longitude'] = longitude;
      body['startLocationName'] = 'عداد حر — نقطة البداية';
    }
    return _post(
      ApiEndpoints.startFreeMeter,
      body: body,
      timeout: HttpTimeouts.finishTrip,
    );
  }

  static Future<TripApiResult> reportLiveMeter(
    int requestId, {
    required Map<String, dynamic> body,
  }) =>
      _post(ApiEndpoints.reportLiveMeter(requestId), body: body);

  static Future<TripApiResult> driverCancelScheduled(
    int requestId, {
    required String apology,
  }) =>
      _post(
        ApiEndpoints.driverCancelScheduled(requestId),
        body: {'apology': apology},
      );

  static Future<TripApiResult> driverCancelEnRoute(
    int requestId, {
    String reason = '',
  }) =>
      _post(
        ApiEndpoints.driverCancelEnRoute(requestId),
        body: reason.trim().isEmpty ? {} : {'reason': reason.trim()},
      );

  static Future<TripApiResult> confirmDriverArrived(int requestId) =>
      _post(ApiEndpoints.confirmDriverArrived(requestId));

  static Future<TripApiResult> cancelCustomerRequest(
    int requestId, {
    String reason = '',
  }) =>
      _post(
        ApiEndpoints.cancelCustomerRequest(requestId),
        body: {'reason': reason},
      );

  /// إلغاء طلب عالق — يعمل للسائق والراكب.
  static Future<TripApiResult> abortActiveTrip(
    int requestId, {
    String reason = '',
  }) =>
      _post(
        ApiEndpoints.abortActiveTrip(requestId),
        body: reason.trim().isEmpty ? {} : {'reason': reason.trim()},
      );

  static Future<TripApiResult> scheduledPassengerReady(
    int requestId,
    bool ready,
  ) =>
      _post(
        ApiEndpoints.scheduledPassengerReady(requestId),
        body: {'ready': ready},
      );

  static Future<TripApiResult> scheduledPassengerWaitOrCancel(
    int requestId, {
    required bool wait,
  }) =>
      _post(
        ApiEndpoints.scheduledPassengerWaitOrCancel(requestId),
        body: {'action': wait ? 'wait' : 'cancel'},
      );

  static Future<TripApiResult> scheduledDriverResponse(
    int requestId,
    String action,
  ) =>
      _post(
        ApiEndpoints.scheduledDriverResponse(requestId),
        body: {'action': action},
      );

  static Future<int> customerNotificationsUnreadCount() async {
    final r = await _get(ApiEndpoints.customerNotificationsUnread);
    if (!r.ok) return 0;
    final wrap = r.dataMap;
    final cnt = wrap?['count'];
    if (cnt is int) return cnt;
    return int.tryParse('$cnt') ?? 0;
  }

  static Future<List<Map<String, dynamic>>> fetchCustomerNotifications() async {
    final r = await _get(ApiEndpoints.customerNotifications);
    return r.ok ? r.dataList : [];
  }

  static Future<int> driverNotificationsUnreadCount() async {
    final r = await _get(ApiEndpoints.driverNotificationsUnread);
    if (r.statusCode == 404) return 0;
    if (!r.ok) return 0;
    final wrap = r.dataMap;
    final cnt = wrap?['count'];
    if (cnt is int) return cnt;
    return int.tryParse('$cnt') ?? 0;
  }

  static Future<List<Map<String, dynamic>>> fetchDriverNotifications() async {
    final r = await _get(ApiEndpoints.driverNotifications);
    if (r.statusCode == 404) return [];
    return r.ok ? r.dataList : [];
  }

  static Future<TripApiResult> fetchDriverWallet() =>
      _get(ApiEndpoints.driverWallet);

  static Future<TripApiResult> fetchCustomerWallet() =>
      _get(ApiEndpoints.customerWallet);

  static Future<TripApiResult> fetchTripPayment(int requestId) =>
      _get(ApiEndpoints.tripPayment(requestId), timeout: _pollTimeout);

  /// `method`: wallet | cash
  static Future<TripApiResult> payTrip(int requestId, String method) =>
      _post(ApiEndpoints.tripPay(requestId), body: {'method': method});

  static Future<TripApiResult> fetchDriverReceiveRadius() =>
      _get(ApiEndpoints.driverReceiveRadius);

  static Future<TripApiResult> updateDriverReceiveRadius(int km) =>
      _post(
        ApiEndpoints.driverReceiveRadius,
        body: {'receive_radius_km': km},
      );

  static Future<void> markCustomerNotificationRead(int id) async {
    await _post(ApiEndpoints.customerNotificationMarkRead(id));
  }

  static Future<void> markDriverNotificationRead(int id) async {
    await _post(ApiEndpoints.driverNotificationMarkRead(id));
  }

  static Future<bool> requestHasComplaint(int requestId) async {
    final r = await _get(ApiEndpoints.complaintsForRequest(requestId));
    if (!r.ok) return false;
    final d = r.data;
    return d is List && d.isNotEmpty;
  }

  static Future<TripApiResult> storeComplaint({
    required int requestId,
    required int driverId,
    required String detail,
    required int rating,
  }) =>
      _post(
        ApiEndpoints.complaintsStore,
        body: {
          'requestId': requestId,
          'driverId': driverId,
          'detail': detail,
          'rating': rating,
        },
      );
}
