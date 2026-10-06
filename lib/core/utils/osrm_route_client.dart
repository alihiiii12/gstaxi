import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../maps/map_style_config.dart';
import 'utf8_text.dart';

/// نتيجة مسار على الطرق: نقاط + مسافة/زمن + خطوات تنقّل.
class RoadRouteResult {
  const RoadRouteResult({
    required this.points,
    this.distanceKm,
    this.durationMinutes,
    this.source = 'osrm',
    this.steps = const [],
  });

  final List<LatLng> points;
  final double? distanceKm;
  final double? durationMinutes;
  final String source;
  final List<RouteNavStep> steps;
}

class RouteNavStep {
  const RouteNavStep({
    required this.instruction,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.location,
    this.modifier,
    this.type,
  });

  final String instruction;
  final double distanceMeters;
  final double durationSeconds;
  final LatLng location;
  final String? modifier;
  final String? type;
}

/// جلب مسار على الطرق عبر OSRM فقط (بدون Google Directions).
class OsrmRouteClient {
  OsrmRouteClient._();

  static String get _osrmBase => MapStyleConfig.osrmBaseUrl;
  static const _maxCacheEntries = 32;
  static const _maxDisplayPoints = 180;
  static final _cache = <String, RoadRouteResult>{};

  /// يحوّل مصفوفة GeoJSON `[[lng,lat], ...]` إلى نقاط للخريطة.
  static List<LatLng> parseRoutePointsGeoJson(dynamic raw) {
    if (raw is! List || raw.isEmpty) return [];
    final out = <LatLng>[];
    for (final e in raw) {
      if (e is! List || e.length < 2) continue;
      final a = e[0];
      final b = e[1];
      if (a is! num || b is! num) continue;
      final lat = b.toDouble();
      final lng = a.toDouble();
      if (!lat.isFinite || !lng.isFinite) continue;
      out.add(LatLng(lat, lng));
    }
    return out;
  }

  static List<LatLng> simplifyForDisplay(
    List<LatLng> points, {
    int maxPoints = _maxDisplayPoints,
  }) {
    if (points.length <= maxPoints) return points;
    final out = <LatLng>[points.first];
    final step = (points.length - 2) / (maxPoints - 2);
    var idx = step;
    for (var i = 1; i < maxPoints - 1; i++) {
      final pick = idx.round().clamp(1, points.length - 2);
      out.add(points[pick]);
      idx += step;
    }
    out.add(points.last);
    return out;
  }

  static String _cacheKeyForPoints(List<LatLng> points, {bool withSteps = false}) {
    final parts = points
        .map(
          (p) =>
              '${p.latitude.toStringAsFixed(4)},${p.longitude.toStringAsFixed(4)}',
        )
        .join('|');
    return '$parts|${withSteps ? 's' : 'n'}';
  }

  static Future<List<LatLng>?> fetchRoutePoints(LatLng from, LatLng to) async {
    final r = await fetchRoute(from, to);
    return r?.points;
  }

  static Future<RoadRouteResult?> fetchRoute(
    LatLng from,
    LatLng to, {
    bool withSteps = false,
  }) =>
      fetchRouteThrough([from, to], withSteps: withSteps);

  /// مسار عبر نقاط متعددة (انطلاق + وجهات مرتّبة).
  static Future<RoadRouteResult?> fetchRouteThrough(
    List<LatLng> points, {
    bool withSteps = false,
  }) async {
    if (points.length < 2) return null;
    final key = _cacheKeyForPoints(points, withSteps: withSteps);
    final cached = _cache[key];
    if (cached != null) return cached;

    final osrm = await _fetchOsrmThrough(points, withSteps: withSteps);
    if (osrm != null && osrm.points.length >= 2) {
      _remember(key, osrm);
      return osrm;
    }
    return null;
  }

  static void _remember(String key, RoadRouteResult result) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = result;
  }

  static Future<RoadRouteResult?> _fetchOsrmThrough(
    List<LatLng> points, {
    bool withSteps = false,
  }) async {
    try {
      final coords = points
          .map((p) => '${p.longitude},${p.latitude}')
          .join(';');
      final stepsQ = withSteps ? '&steps=true' : '';
      final url = Uri.parse(
        '$_osrmBase/$coords?overview=full&geometries=geojson$stepsQ',
      );
      final res = await http.get(
        url,
        headers: const {
          'Accept': 'application/json',
          'User-Agent': 'SyriaTaxiApp/1.0 (OSM-MapLibre)',
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final map = decodeJsonUtf8(res);
      if (map is! Map) return null;
      final route = map['routes']?[0];
      if (route is! Map) return null;
      final geoCoords = route['geometry']?['coordinates'];
      final pts = simplifyForDisplay(parseRoutePointsGeoJson(geoCoords));
      if (pts.length < 2) return null;
      final meters = route['distance'];
      final seconds = route['duration'];
      final steps = withSteps ? _parseSteps(route) : const <RouteNavStep>[];
      return RoadRouteResult(
        points: pts,
        distanceKm: meters is num ? meters / 1000.0 : null,
        durationMinutes: seconds is num ? seconds / 60.0 : null,
        source: 'osrm',
        steps: steps,
      );
    } catch (_) {
      return null;
    }
  }

  static List<RouteNavStep> _parseSteps(Map route) {
    final out = <RouteNavStep>[];
    final legs = route['legs'];
    if (legs is! List) return out;
    for (final leg in legs) {
      if (leg is! Map) continue;
      final steps = leg['steps'];
      if (steps is! List) continue;
      for (final s in steps) {
        if (s is! Map) continue;
        final man = s['maneuver'];
        if (man is! Map) continue;
        final loc = man['location'];
        LatLng? point;
        if (loc is List && loc.length >= 2 && loc[0] is num && loc[1] is num) {
          point = LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble());
        }
        point ??= const LatLng(0, 0);
        final type = man['type']?.toString();
        final modifier = man['modifier']?.toString();
        final name = repairUtf8Mojibake(s['name']?.toString() ?? '');
        final dist = (s['distance'] is num) ? (s['distance'] as num).toDouble() : 0.0;
        final dur = (s['duration'] is num) ? (s['duration'] as num).toDouble() : 0.0;
        out.add(
          RouteNavStep(
            instruction: _arabicInstruction(type, modifier, name),
            distanceMeters: dist,
            durationSeconds: dur,
            location: point,
            modifier: modifier,
            type: type,
          ),
        );
      }
    }
    return out;
  }

  static String _arabicInstruction(String? type, String? modifier, String road) {
    final roadPart = road.trim().isEmpty ? '' : ' على $road';
    switch (type) {
      case 'depart':
        return 'انطلق$roadPart';
      case 'arrive':
        return 'لقد وصلت إلى الوجهة';
      case 'turn':
      case 'end of road':
        if (modifier == 'left') return 'انعطف لليسار$roadPart';
        if (modifier == 'right') return 'انعطف لليمين$roadPart';
        if (modifier == 'sharp left') return 'انعطف حاداً لليسار$roadPart';
        if (modifier == 'sharp right') return 'انعطف حاداً لليمين$roadPart';
        if (modifier == 'slight left') return 'ميل قليلاً لليسار$roadPart';
        if (modifier == 'slight right') return 'ميل قليلاً لليمين$roadPart';
        if (modifier == 'uturn' || modifier == 'u-turn') {
          return 'اجعل دورة كاملة للخلف$roadPart';
        }
        return 'انعطف$roadPart';
      case 'new name':
        return 'تابع$roadPart';
      case 'merge':
        return 'ادمج في الطريق$roadPart';
      case 'on ramp':
        return 'ادخل المنحدر$roadPart';
      case 'off ramp':
        if (modifier?.contains('left') == true) {
          return 'اخرج من المنحدر لليسار$roadPart';
        }
        if (modifier?.contains('right') == true) {
          return 'اخرج من المنحدر لليمين$roadPart';
        }
        return 'اخرج من المنحدر$roadPart';
      case 'fork':
        if (modifier?.contains('left') == true) return 'خذ المسار الأيسر$roadPart';
        if (modifier?.contains('right') == true) return 'خذ المسار الأيمن$roadPart';
        return 'عند التفرع تابع$roadPart';
      case 'roundabout':
      case 'rotary':
        return 'ادخل الدوار$roadPart';
      case 'continue':
        return 'استمر مستقيم$roadPart';
      default:
        return 'تابع$roadPart';
    }
  }
}
