/// تسمية نقطة انطلاق / وجهة للعرض في القوائم (اسم منطقة أو عنوان، وليس الإحداثيات إن وُجد نص).
String? _trimDyn(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

/// يقرأ اسم منطقة أو وصف نصي من كائن موقع يعيده الخادم (مع علاقة [service_area] إن وُجدت).
String areaLabelFromLocationJson(dynamic loc) {
  if (loc is! Map) return '';
  final m = Map<String, dynamic>.from(loc);
  const keys = <String>[
    'area_name',
    'areaName',
    'zone_name',
    'zoneName',
    'name',
    'label',
    'address',
    'formatted_address',
    'formattedAddress',
    'title',
    'description',
    'placeName',
    'place_name',
    'display_name',
    'displayName',
  ];
  for (final k in keys) {
    final t = _trimDyn(m[k]);
    if (t != null) return t;
  }
  const nests = <String>[
    'service_area',
    'serviceArea',
    'area',
    'zone',
  ];
  for (final n in nests) {
    final inner = m[n];
    if (inner is Map) {
      final im = Map<String, dynamic>.from(inner);
      final t = _trimDyn(im['name'] ?? im['title'] ?? im['label']);
      if (t != null) return t;
    }
  }
  return '';
}

/// تسمية نقطة لطلب كامل: يجمع حقول الموقع مع حقول اختيارية على مستوى الطلب.
String areaLabelFromRequestForPoint(
  Map<String, dynamic> request,
  dynamic locationJson, {
  required bool destination,
}) {
  final fromLoc = areaLabelFromLocationJson(locationJson);
  if (fromLoc.isNotEmpty) return fromLoc;

  if (!destination) {
    for (final key in <String>[
      'pickup_service_area',
      'pickupServiceArea',
      'start_service_area',
      'startServiceArea',
    ]) {
      final sa = request[key];
      if (sa is Map) {
        final t = _trimDyn(Map<String, dynamic>.from(sa)['name']);
        if (t != null) return t;
      }
    }
    final sa = request['service_area'] ?? request['serviceArea'];
    if (sa is Map) {
      final t = _trimDyn(Map<String, dynamic>.from(sa)['name']);
      if (t != null) return t;
    }
    final ld = _trimDyn(request['locationDesc'] ?? request['location_desc']);
    if (ld != null) return ld;
  } else {
    for (final key in <String>[
      'dest_service_area',
      'destServiceArea',
      'destination_service_area',
      'destinationServiceArea',
      'drop_service_area',
      'dropServiceArea',
    ]) {
      final sa = request[key];
      if (sa is Map) {
        final t = _trimDyn(Map<String, dynamic>.from(sa)['name']);
        if (t != null) return t;
      }
    }
  }

  return '—';
}
