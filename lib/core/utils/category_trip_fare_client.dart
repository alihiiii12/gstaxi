import 'dart:convert';

import 'package:latlong2/latlong.dart';

final Distance _categoryFareGeo = Distance();

/// تقدير طلب التطبيق: سعر افتتاحي + (كم × KMPrice) + (دقائق × timePrice).
double? categoryTripFareKmMinutesOnly(
  Map<String, dynamic> carType,
  double km,
  double? durationMinutes,
) {
  if (km <= 0) return null;
  final openP = parseMoneyField(carType['openPrice']) ?? 0;
  final kmP = parseMoneyField(carType['KMPrice']);
  final minP = parseMoneyField(carType['timePrice']);

  var fare = openP > 0 ? openP : 0.0;
  if (kmP != null && kmP > 0) fare += km * kmP;
  if (minP != null &&
      minP > 0 &&
      durationMinutes != null &&
      durationMinutes > 0) {
    fare += durationMinutes * minP;
  }
  if (fare <= 0) return null;
  return fare;
}

double? parseMoneyField(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().replaceAll(',', '').trim());
}

/// قراءة `history` كما في لوحة الإدارة (`requestHistory` في DashboardPage).
Map<String, dynamic>? requestHistoryMap(Map<String, dynamic> r) {
  for (final key in <String>['history', 'History']) {
    final v = r[key];
    if (v == null) continue;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    if (v is String) {
      final t = v.trim();
      if (t.isEmpty) continue;
      try {
        final dec = json.decode(t);
        if (dec is Map) return Map<String, dynamic>.from(dec as Map);
      } catch (_) {}
    }
  }
  return null;
}

/// تكلفة مُثبتة للعرض: يفضّل سجل الرحلة (`history`) ثم جذر الطلب — مطابق لترتيب `requestCostFromRow` في الإدمن.
double? requestSettledCostLirasFromRequest(Map<String, dynamic> r) {
  double? pick(dynamic raw) {
    if (raw == null) return null;
    final n = parseMoneyField(raw);
    if (n == null || n <= 0) return null;
    return n;
  }

  final hist = requestHistoryMap(r);
  if (hist != null) {
    for (final k in <String>[
      'finalCost',
      'final_cost',
      'totalCost',
      'total_cost',
      'cost',
      'total',
    ]) {
      final v = pick(hist[k]);
      if (v != null) return v;
    }
  }
  for (final k in <String>[
    'finalCost',
    'final_cost',
    'totalCost',
    'total_cost',
    'trip_cost',
    'tripCost',
    'price',
    'amount',
    'predectedCost',
    'predected_cost',
    'predictedCost',
    'predicted_cost',
  ]) {
    final v = pick(r[k]);
    if (v != null) return v;
  }
  return null;
}

/// معامل منطقة التسعير المحفوظ مع الطلب (1 إن لم يوجد).
double requestZoneMultiplier(Map<String, dynamic> order) {
  final m = parseMoneyField(order['zone_multiplier'] ?? order['zoneMultiplier']);
  return m != null && m > 0 ? m : 1.0;
}

/// «تسعيرة مدينة دمشق ← الريف ×1.5» أو null إن كان المعامل 1.
String? requestZoneLabel(Map<String, dynamic> order) {
  final m = requestZoneMultiplier(order);
  if (m == 1.0) return null;
  final from = (order['pickup_zone_name'] ?? '').toString().trim();
  final to = (order['dest_zone_name'] ?? '').toString().trim();
  final mul = m.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
  if (from.isEmpty || to.isEmpty) return 'تسعيرة منطقة ×$mul';
  return 'تسعيرة $from ← $to ×$mul';
}

/// التعرفة المعروضة للزبون على بطاقة الفئة: (كم × KMPrice) + (دقائق × timePrice)، مقربة.
/// **لا تُستخدم لرحلات العداد الحر** — الزبون في السيارة والتسعيرة من إعدادات العداد فقط.
int? requestCategoryFareLirasRounded(Map<String, dynamic> order) {
  if (_isFreeMeter(order)) return null;

  for (final k in <String>[
    'customerQuotedFare',
    'customer_quoted_fare',
    'quotedFare',
    'quoted_fare',
  ]) {
    final v = order[k];
    if (v == null) continue;
    final n = parseMoneyField(v);
    if (n != null && n > 0) return n.round();
  }

  final ct = requestCarTypeFromOrder(order);
  final km = requestTripKmForCategoryFare(order);
  if (ct != null && km != null && km > 0) {
    final mins = requestEstimatedDurationMinutes(order);
    final fare = categoryTripFareKmMinutesOnly(ct, km, mins);
    if (fare != null && fare > 0) {
      return (fare * requestZoneMultiplier(order)).round();
    }
  }

  final server = _predectedCostNumeric(order);
  if (server != null && server > 0) return server.round();
  return null;
}

bool _isFinishedTripStatus(Map<String, dynamic> order) {
  final st = (order['status'] ?? '').toString().trim().toLowerCase();
  return st == 'finished';
}

bool _isAppRequest(Map<String, dynamic> order) {
  if (_isFreeMeter(order)) return false;
  if (order['is_app_request'] == true || order['isAppRequest'] == true) {
    return true;
  }
  final bk = (order['billing_kind'] ?? order['billingKind'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  return bk.isEmpty || bk == 'app_request';
}

/// العداد الحر: الزبون في السيارة — لا فئة VIP/اقتصادي ولا تسعيرة طلب التطبيق.
bool _isFreeMeter(Map<String, dynamic> order) {
  final bk = (order['billing_kind'] ?? order['billingKind'] ?? '')
      .toString()
      .trim()
      .toLowerCase();
  if (bk == 'free_meter') return true;
  return order['is_app_request'] == false || order['isAppRequest'] == false;
}

/// سطر أجرة موحّد: طلب التطبيق = فئة؛ العداد الحر = مبلغ العداد فقط.
String? driverRequestUnifiedPricingLine(Map<String, dynamic> order) {
  if (_isFreeMeter(order)) {
    final settled = requestSettledCostLirasFromRequest(order);
    if (settled != null && settled > 0) {
      return 'أجرة العداد الحر (نهائية): ${settled.round()} ل.س';
    }
    return null;
  }

  final ct = requestCarTypeFromOrder(order);
  final computed = requestCategoryFareLirasRounded(order);
  final settled = requestSettledCostLirasFromRequest(order);

  final isApp = _isAppRequest(order);
  final st = (order['status'] ?? '').toString().trim();
  if (st == 'Running') {
    return null;
  }

  int? display;
  if (_isFinishedTripStatus(order) && isApp) {
    if (settled != null && settled > 0) {
      display = settled.round();
    } else if (computed != null && computed > 0) {
      display = computed;
    }
  } else if (_isFinishedTripStatus(order) &&
      settled != null &&
      settled > 0) {
    display = settled.round();
  } else if (computed != null && computed > 0) {
    display = computed;
  } else if (settled != null && settled > 0) {
    display = settled.round();
  }

  if (display == null || display <= 0) return null;

  final name =
      (ct?['name'] ?? ct?['Name'] ?? ct?['title'] ?? '').toString().trim();
  final suffix = _isFinishedTripStatus(order) ? 'نهائية' : 'متوقعة';
  if (name.isNotEmpty) {
    return 'الأجرة ($suffix — $name): $display ل.س';
  }
  return 'الأجرة ($suffix): $display ل.س';
}

Map<String, dynamic>? _asStringKeyedMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

Map<String, dynamic>? requestCarTypeFromOrder(Map<String, dynamic> order) {
  final ct = order['carType'] ??
      order['car_type'] ??
      order['transType'] ??
      order['trans_type'];
  return _asStringKeyedMap(ct);
}

double? _coordDyn(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

LatLng? _latLngFromLocationField(dynamic raw) {
  final m = _asStringKeyedMap(raw);
  if (m == null) return null;
  final lat = _coordDyn(m['latitude'] ?? m['lat']);
  final lng = _coordDyn(m['longitude'] ?? m['lng'] ?? m['lon']);
  if (lat == null || lng == null) return null;
  return LatLng(lat, lng);
}

/// كيلومترات الرحلة لحساب تسعيرة الفئة: يُفضّل المسافة المرسلة من الزبون (`estimatedTripKm`)
/// ثم أي حقل معروف من الخادم، ثم الخط المستقيم بين الانطلاق والوجهة.
double? requestTripKmForCategoryFare(Map<String, dynamic> order) {
  const kmKeys = <String>[
    'estimatedTripKm',
    'estimated_trip_km',
    'trip_distance_km',
    'tripDistanceKm',
    'distanceKm',
    'distance_km',
    'road_distance_km',
    'roadDistanceKm',
    'estimatedDistanceKm',
    'estimated_distance_km',
    'distance',
    'tripDistance',
  ];
  for (final k in kmKeys) {
    final v = order[k];
    if (v == null) continue;
    final d = v is num ? v.toDouble() : double.tryParse(v.toString().trim());
    if (d != null && d > 0) return d;
  }

  final p1 = _latLngFromLocationField(order['startLocation'] ?? order['start_location']);
  final p2 = _latLngFromLocationField(order['destLocation'] ?? order['dest_location']);
  if (p1 == null || p2 == null) return null;
  return _categoryFareGeo.as(LengthUnit.Kilometer, p1, p2);
}

double? requestEstimatedDurationMinutes(Map<String, dynamic> order) {
  const keys = <String>[
    'estimatedDurationMinutes',
    'estimated_duration_minutes',
    'durationMinutes',
    'duration_minutes',
    'estimatedDuration',
    'estimated_duration',
  ];
  for (final k in keys) {
    final v = order[k];
    if (v == null) continue;
    final d = v is num ? v.toDouble() : double.tryParse(v.toString().trim());
    if (d != null && d > 0) return d;
  }
  return null;
}

double? _predectedCostNumeric(Map<String, dynamic> order) {
  final raw = order['predectedCost'] ??
      order['predected_cost'] ??
      order['predictedCost'] ??
      order['predicted_cost'];
  if (raw == null) return null;
  return raw is num ? raw.toDouble() : double.tryParse(raw.toString().trim());
}

String _formatCategoryPricingLine(Map<String, dynamic>? carType, num amount) {
  final priceStr = amount == amount.round()
      ? amount.round().toString()
      : amount.toStringAsFixed(2);

  String catName = '';
  if (carType != null) {
    catName = (carType['name'] ?? carType['Name'] ?? carType['title'] ?? '')
        .toString()
        .trim();
  }
  if (catName.isNotEmpty) {
    return 'تسعيرة الفئة ($catName): $priceStr ل.س';
  }
  return 'تسعيرة الطلب (حسب الفئة): $priceStr ل.س';
}

/// سعر يطابق ما يراه الزبون على بطاقة الفئة.
String? driverRequestCategoryPricingLine(Map<String, dynamic> order) =>
    driverRequestUnifiedPricingLine(order);
