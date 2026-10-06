import 'package:latlong2/latlong.dart';

/// مراحل محاكاة رحلة الزبون (مؤقتة للتطوير).
enum DevMockTripStage { reserved, arrived, running }

/// يحوّل طلب Pending إلى رحلة وهمية متدرجة للواجهات.
class DevMockDriverTrip {
  DevMockDriverTrip._();

  static final Map<int, DateTime> _acceptedAt = {};

  /// ثوانٍ بعد القبول → «وصلت للراكب».
  static const int arrivedAfterSeconds = 5;

  /// ثوانٍ بعد القبول → بدء الرحلة (عداد حي).
  static const int runningAfterSeconds = 10;

  static void rememberAccepted(int requestId) {
    if (requestId <= 0) return;
    _acceptedAt.putIfAbsent(requestId, DateTime.now);
  }

  static void clear(int requestId) => _acceptedAt.remove(requestId);

  static void clearAll() => _acceptedAt.clear();

  static DateTime? acceptedAt(int requestId) => _acceptedAt[requestId];

  static int runningElapsedSeconds(int requestId) {
    final at = _acceptedAt[requestId];
    if (at == null) return 3;
    final sinceAccept = DateTime.now().difference(at).inSeconds;
    final sinceRunning = sinceAccept - runningAfterSeconds;
    return sinceRunning < 1 ? 3 : sinceRunning;
  }

  static DevMockTripStage stageFor(int requestId) {
    final started = _acceptedAt[requestId];
    if (started == null) return DevMockTripStage.reserved;
    final sec = DateTime.now().difference(started).inSeconds;
    if (sec >= runningAfterSeconds) return DevMockTripStage.running;
    if (sec >= arrivedAfterSeconds) return DevMockTripStage.arrived;
    return DevMockTripStage.reserved;
  }

  static Duration? nextTickAfter(int requestId) {
    final started = _acceptedAt[requestId];
    if (started == null) return const Duration(seconds: arrivedAfterSeconds);
    final sec = DateTime.now().difference(started).inSeconds;
    if (sec < arrivedAfterSeconds) {
      return Duration(seconds: arrivedAfterSeconds - sec);
    }
    if (sec < runningAfterSeconds) {
      return Duration(seconds: runningAfterSeconds - sec);
    }
    return null;
  }

  static Map<String, dynamic> apply(Map<String, dynamic> trip) {
    final id = int.tryParse(trip['id']?.toString() ?? '') ?? 0;
    rememberAccepted(id);

    final t = Map<String, dynamic>.from(trip);
    t['driverId'] = t['driverId'] ?? t['driver_id'] ?? 9001;
    t['driver'] = {
      'id': t['driverId'],
      'driver_photo_url': null,
      'car_photo_url': null,
      'carType': t['carType'] ?? t['car_type'] ?? 'عادية',
      'carNumber': t['carNumber'] ?? '١٢٣٤',
      'user': {
        'firstName': 'سائق',
        'lastName': 'تجريبي',
        'number': '0958000000',
      },
    };

    switch (stageFor(id)) {
      case DevMockTripStage.reserved:
        t['status'] = 'Reserved';
      case DevMockTripStage.arrived:
        t['status'] = 'DriverArrived';
      case DevMockTripStage.running:
        t['status'] = 'Running';
    }
    return t;
  }

  /// موقع وهمي قريب من نقطة الانطلاق لعرض السيارة على الخريطة.
  static LatLng? mockDriverNearPickup(Map<String, dynamic> trip) {
    final start = trip['start'] ??
        trip['Start'] ??
        trip['pickup'] ??
        trip['from_location'] ??
        trip['fromLocation'];
    if (start is! Map) return null;
    final lat = _coord(start['lat'] ?? start['latitude']);
    final lng = _coord(start['lng'] ?? start['longitude'] ?? start['lon']);
    if (lat == null || lng == null) return null;
    return LatLng(lat + 0.00035, lng + 0.00025);
  }

  static Map<String, dynamic> mockLiveMeter({required int elapsedSec}) {
    final km = (elapsedSec * 0.012).clamp(0.2, 18.0);
    final cost = (4500 + km * 1800 + elapsedSec * 8).round();
    return {
      'finalCost': cost,
      'distanceTraveledKm': double.parse(km.toStringAsFixed(2)),
      'billedWaitingMinutes': elapsedSec > 40 ? 1 : 0,
      'waitingSeconds': elapsedSec > 40 ? (elapsedSec % 60) : 0,
      'meterElapsedSeconds': elapsedSec,
      'isMoving': true,
    };
  }

  static double? _coord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }
}

/// توافق مع الاستدعاءات القديمة.
Map<String, dynamic> applyDevMockDriverAccepted(Map<String, dynamic> trip) =>
    DevMockDriverTrip.apply(trip);
