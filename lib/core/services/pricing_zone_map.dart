import 'dart:async';

import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../network/api_endpoints.dart';
import '../network/http_timeouts.dart';
import '../utils/utf8_text.dart';

class PricingZoneHit {
  const PricingZoneHit(this.id, this.name);
  final int id;
  final String name;
}

class PricingZoneQuote {
  const PricingZoneQuote({
    required this.multiplier,
    required this.from,
    required this.to,
  });

  final double multiplier;
  final PricingZoneHit from;
  final PricingZoneHit to;

  bool get isNeutral => (multiplier - 1.0).abs() < 0.0005;

  /// نفس صيغة السيرفر: «تسعيرة مدينة دمشق ← الريف ×1.25».
  String get label {
    if (isNeutral) return '';
    var mul = multiplier.toStringAsFixed(3);
    mul = mul.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
    return 'تسعيرة ${from.name} ← ${to.name} ×$mul';
  }
}

class _Zone {
  _Zone(this.id, this.name, this.polygon)
      : minLat = polygon.map((p) => p[0]).reduce((a, b) => a < b ? a : b),
        maxLat = polygon.map((p) => p[0]).reduce((a, b) => a > b ? a : b),
        minLng = polygon.map((p) => p[1]).reduce((a, b) => a < b ? a : b),
        maxLng = polygon.map((p) => p[1]).reduce((a, b) => a > b ? a : b);

  final int id;
  final String name;
  final List<List<double>> polygon;
  final double minLat, maxLat, minLng, maxLng;

  bool contains(double lat, double lng) {
    if (lat < minLat || lat > maxLat || lng < minLng || lng > maxLng) {
      return false;
    }
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final yi = polygon[i][0], xi = polygon[i][1];
      final yj = polygon[j][0], xj = polygon[j][1];
      final dy = (yj - yi) == 0 ? 1e-12 : (yj - yi);
      if (((yi > lat) != (yj > lat)) && (lng < (xj - xi) * (lat - yi) / dy + xi)) {
        inside = !inside;
      }
    }
    return inside;
  }
}

/// مناطق التسعير من لوحة التحكم — نفس منطق `PricingZoneService` على السيرفر.
class PricingZoneMap {
  PricingZoneMap._() {
    final cached = _box.read(_storageKey);
    if (cached is Map) _apply(Map<String, dynamic>.from(cached));
  }
  static final instance = PricingZoneMap._();

  static const _storageKey = 'pricing_zones_map_v1';
  static const _refreshEvery = Duration(minutes: 5);

  final _box = GetStorage();
  List<_Zone> _zones = const [];
  Map<String, double> _rules = const {};
  PricingZoneHit _outside = const PricingZoneHit(0, 'الريف');
  DateTime? _fetchedAt;
  Future<void>? _inflight;

  bool get hasZones => _zones.isNotEmpty;

  Future<void> refresh({bool force = false}) {
    final at = _fetchedAt;
    if (!force && at != null && DateTime.now().difference(at) < _refreshEvery) {
      return Future.value();
    }
    return _inflight ??= _fetch().whenComplete(() => _inflight = null);
  }

  Future<void> _fetch() async {
    try {
      final res = await http
          .get(
            Uri.parse(ApiEndpoints.pricingZonesMap),
            headers: await ApiEndpoints.headers(),
          )
          .timeout(HttpTimeouts.api);
      if (res.statusCode != 200) return;
      final decoded = decodeJsonUtf8(res);
      if (decoded is! Map || decoded['success'] != true || decoded['data'] is! Map) {
        return;
      }
      final data = Map<String, dynamic>.from(decoded['data'] as Map);
      _apply(data);
      _fetchedAt = DateTime.now();
      await _box.write(_storageKey, data);
    } catch (_) {}
  }

  void _apply(Map<String, dynamic> data) {
    final zones = <_Zone>[];
    final rawZones = data['zones'];
    if (rawZones is List) {
      for (final z in rawZones) {
        if (z is! Map) continue;
        final id = int.tryParse('${z['id']}') ?? 0;
        final poly = <List<double>>[];
        final rawPoly = z['polygon'];
        if (rawPoly is List) {
          for (final p in rawPoly) {
            if (p is List && p.length >= 2) {
              final lat = double.tryParse('${p[0]}');
              final lng = double.tryParse('${p[1]}');
              if (lat != null && lng != null) poly.add([lat, lng]);
            }
          }
        }
        if (id > 0 && poly.length >= 3) {
          zones.add(_Zone(id, '${z['name'] ?? ''}', poly));
        }
      }
    }
    final rules = <String, double>{};
    final rawRules = data['rules'];
    if (rawRules is Map) {
      rawRules.forEach((k, v) {
        final m = double.tryParse('$v');
        if (m != null && m > 0) rules['$k'] = m;
      });
    }
    final out = data['outside'];
    if (out is Map) {
      _outside = PricingZoneHit(
        int.tryParse('${out['id']}') ?? 0,
        '${out['name'] ?? 'الريف'}',
      );
    }
    _zones = zones;
    _rules = rules;
  }

  PricingZoneHit zoneAt(double lat, double lng) {
    for (final z in _zones) {
      if (z.contains(lat, lng)) return PricingZoneHit(z.id, z.name);
    }
    return _outside;
  }

  PricingZoneQuote quote(double fromLat, double fromLng, double toLat, double toLng) {
    final from = zoneAt(fromLat, fromLng);
    final to = zoneAt(toLat, toLng);
    var m = _rules['${from.id}:${to.id}'] ?? 1.0;
    if (!m.isFinite || m <= 0) m = 1.0;
    m = (m * 1000).roundToDouble() / 1000;
    return PricingZoneQuote(multiplier: m, from: from, to: to);
  }
}
