import 'request_route_label.dart';

String? _trim(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// اسم نقطة الانطلاق/الوجهة للعرض في تفاصيل الطلب (بدون إحداثيات).
String pickupPlaceLabelForRequest(Map<String, dynamic> request) {
  final fromReq = _trim(
    request['startLocationName'] ??
        request['start_location_name'] ??
        request['pickup_name'] ??
        request['pickupName'],
  );
  if (fromReq != null) return fromReq;

  final loc = request['startLocation'] ?? request['start_location'];
  final fromLoc = areaLabelFromRequestForPoint(
    request,
    loc,
    destination: false,
  );
  if (fromLoc.isNotEmpty && fromLoc != '—') return fromLoc;

  final ld = _trim(request['locationDesc'] ?? request['location_desc']);
  if (ld != null) return ld;

  return 'نقطة الانطلاق — راجع الخريطة';
}

String destPlaceLabelForRequest(Map<String, dynamic> request) {
  final waypoints = request['waypoints'] ?? request['way_points'];
  if (waypoints is List && waypoints.length > 1) {
    final names = <String>[];
    for (final e in waypoints) {
      if (e is! Map) continue;
      final n = _trim(e['name'] ?? e['label']);
      if (n != null) names.add(n);
    }
    if (names.length > 1) return names.join(' ← ');
  }

  final fromReq = _trim(
    request['destLocationName'] ??
        request['dest_location_name'] ??
        request['destination_name'] ??
        request['destinationName'],
  );
  if (fromReq != null) return fromReq;

  final loc = request['destLocation'] ?? request['dest_location'];
  final fromLoc = areaLabelFromRequestForPoint(
    request,
    loc,
    destination: true,
  );
  if (fromLoc.isNotEmpty && fromLoc != '—') return fromLoc;

  return 'الوجهة — راجع الخريطة';
}

/// «طلب اقتصادية — الأجرة بتسعيرة الاقتصادية» حين يصل الطلب لسائق من فئة أخرى.
String? crossCategoryNoteFromRequest(Map<String, dynamic> request) =>
    _trim(request['cross_category_note'] ?? request['crossCategoryNote']);

/// اسم فئة المركبة من الطلب (كيا، هونداي، اقتصادي…) وليس «سيارة/دراجة».
String carCategoryNameFromRequest(Map<String, dynamic> request) {
  final ct = request['carType'] ?? request['car_type'];
  if (ct is Map) {
    final n = _trim(Map<String, dynamic>.from(ct)['name']);
    if (n != null) return n;
  }
  final tt = request['transType'] ?? request['trans_type'];
  if (tt is Map) {
    final n = _trim(Map<String, dynamic>.from(tt)['name']);
    if (n != null) return n;
  }
  return '';
}
