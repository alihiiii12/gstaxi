import 'package:latlong2/latlong.dart';

import 'driver_order_display.dart';

/// استخراج إحداثيات من حقول الطلب (API متعدد الأشكال).
class TripLocationHelpers {
  TripLocationHelpers._();

  static double? coordToDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().trim());
  }

  static LatLng? extractLocation(Map<String, dynamic> order, String key) {
    final m = (order[key] ??
        order[key == 'startLocation' ? 'start_location' : 'dest_location']);
    if (m is! Map) return null;
    final mm = Map<String, dynamic>.from(m);
    final lat = coordToDouble(mm['latitude']);
    final lng = coordToDouble(mm['longitude']);
    if (lat == null || lng == null) return null;
    if (!lat.isFinite || !lng.isFinite) return null;
    return LatLng(lat, lng);
  }

  static LatLng? extractStartPoint(Map<String, dynamic> order) =>
      extractLocation(order, 'startLocation');

  static String latLngShort(Map<dynamic, dynamic> m) {
    final lat = m['latitude'];
    final lng = m['longitude'];
    return '${lat ?? '—'}, ${lng ?? '—'}';
  }

  static String shortLatLng(LatLng p) =>
      '${p.latitude.toStringAsFixed(5)}, ${p.longitude.toStringAsFixed(5)}';

  static bool shouldNavigateToPickup(
    Map<String, dynamic>? order,
    String st,
    String tripType,
  ) {
    if (order == null) return false;
    if (st == 'Pending' && tripType == 'Immediate') return true;
    if (st == 'Reserved' || st == 'DriverArrived') {
      if (requestIsScheduled(order)) {
        return scheduledDriverMayOperateTrip(order);
      }
      return true;
    }
    return false;
  }

  static bool shouldPromptProximityForOrder(Map<String, dynamic> order) {
    if (!requestIsScheduled(order)) return true;
    return scheduledDriverMayOperateTrip(order);
  }

  static bool requestAppearsRemovedInDriverList(
    List<dynamic> list,
    int requestId,
  ) {
    var found = false;
    for (final raw in list) {
      if (raw is! Map) continue;
      final r = Map<String, dynamic>.from(raw);
      final id = int.tryParse(r['id']?.toString() ?? '') ?? 0;
      if (id != requestId) continue;
      found = true;
      final st = r['status']?.toString() ?? '';
      return st == 'Removed' || st == 'Finished';
    }
    // اختفى من قائمة السائق (مُصفّى أو أُلغي) — اعتبره منتهياً.
    return !found;
  }

  static bool driverRequestsJsonOk(Map<String, dynamic> map) =>
      map['success'] == true || map['state'] == true;
}
