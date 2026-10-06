import 'package:latlong2/latlong.dart';

import 'customer_trip_status_helpers.dart';

/// تحديث نقاط الخريطة من الطلب النشط.
class CustomerTripMapUpdate {
  const CustomerTripMapUpdate({
    this.pickup,
    this.dropoff,
    this.hasDestination,
    this.started,
  });

  final LatLng? pickup;
  final LatLng? dropoff;
  final bool? hasDestination;
  final bool? started;

  static Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  static double? _coord(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  static LatLng? latLngFromLooseMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<dynamic, dynamic>.from(raw);
    final lat = _coord(m['lat'] ?? m['latitude']);
    final lng = _coord(m['lng'] ?? m['longitude'] ?? m['lon']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  static LatLng? _latLngFromLocMap(Map<String, dynamic> m) {
    final lat = _coord(m['latitude'] ?? m['lat']);
    final lng = _coord(m['longitude'] ?? m['lng'] ?? m['lon']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  /// يستخرج الانطلاق والوجهة من صف الطلب.
  static CustomerTripMapUpdate fromTrip(Map<String, dynamic> trip) {
    LatLng? pickup;
    LatLng? dropoff;
    var hasDestination = false;

    final sl = _asMap(trip['startLocation']) ?? _asMap(trip['start_location']);
    if (sl != null) pickup = _latLngFromLocMap(sl);

    final dl = _asMap(trip['destLocation']) ?? _asMap(trip['dest_location']);
    if (dl != null) {
      final d = _latLngFromLocMap(dl);
      if (d != null) {
        dropoff = d;
        hasDestination = true;
      }
    }
    if (!hasDestination &&
        CustomerTripStatusHelpers.normTripStatus(trip) ==
            'AwaitingDestination') {
      hasDestination = false;
    } else if (dropoff != null) {
      hasDestination = true;
    }

    return CustomerTripMapUpdate(
      pickup: pickup,
      dropoff: dropoff,
      hasDestination: hasDestination,
      started: true,
    );
  }

  /// بعد انتهاء الرحلة: من صف الخادم ثم الذاكرة إن لزم.
  static CustomerTripMapUpdate fromCompletedSnapshot({
    required Map<String, dynamic> apiRow,
    Map<String, dynamic>? memoryTrip,
  }) {
    var u = fromTrip(apiRow);
    if (u.hasDestination != true && memoryTrip != null) {
      u = fromTrip(memoryTrip);
    }
    return CustomerTripMapUpdate(
      pickup: u.pickup,
      dropoff: u.dropoff,
      hasDestination: u.hasDestination,
      started: true,
    );
  }
}
