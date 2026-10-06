import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/google_maps_config.dart';
import '../utils/utf8_text.dart';

class PlaceSearchHit {
  PlaceSearchHit({required this.label, required this.point, this.placeId});

  final String label;
  final LatLng point;
  final String? placeId;
}

/// بحث أماكن: Nominatim أولاً (موثوق بدون مفتاح)، ثم Google كاحتياطي إن وُجدت نتائج.
class GooglePlacesService {
  GooglePlacesService._();

  static const _placesBase = 'https://places.googleapis.com/v1';

  static const Map<String, String> _nominatimHeaders = {
    'Accept': 'application/json',
    'Accept-Language': 'ar,en',
    'User-Agent':
        'SyriaTaxiCustomer/1.0 (Flutter app; contact: app@syriataxi.local)',
  };

  static Future<List<PlaceSearchHit>> autocomplete({
    required String query,
    LatLng? biasNear,
    int limit = 10,
  }) async {
    final q = query.trim();
    if (q.length < 2) return [];

    // Nominatim يعمل بدون مفتاح Google — كان يعمل قبل التحويل لـ Places API.
    final fromNominatim = await _nominatimSearch(
      query: q,
      biasNear: biasNear,
      limit: limit,
    );
    if (fromNominatim.isNotEmpty) return fromNominatim;

    return _googleAutocomplete(
      query: q,
      biasNear: biasNear,
      limit: limit,
    );
  }

  static Future<List<PlaceSearchHit>> _nominatimSearch({
    required String query,
    LatLng? biasNear,
    int limit = 10,
  }) async {
    try {
      final params = <String, String>{
        'format': 'json',
        'limit': '${math.max(limit * 2, 12)}',
        'addressdetails': '0',
        'countrycodes': 'sy',
        'q': query,
      };
      if (biasNear != null) {
        // viewbox حوالي دمشق/سوريا الوسطى لتحسين الصلة
        final d = 0.35;
        params['viewbox'] =
            '${biasNear.longitude - d},${biasNear.latitude + d},${biasNear.longitude + d},${biasNear.latitude - d}';
        params['bounded'] = '0';
      }

      final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
      final res = await http
          .get(uri, headers: _nominatimHeaders)
          .timeout(const Duration(milliseconds: 3500));
      if (res.statusCode != 200) return [];

      final raw = decodeJsonUtf8(res);
      if (raw is! List) return [];

      final hits = <PlaceSearchHit>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final lat = double.tryParse(item['lat']?.toString() ?? '');
        final lon = double.tryParse(item['lon']?.toString() ?? '');
        final name = repairUtf8Mojibake(
          item['display_name']?.toString().trim() ?? '',
        );
        if (lat == null || lon == null || name.isEmpty) continue;
        hits.add(
          PlaceSearchHit(
            label: _shorten(name),
            point: LatLng(lat, lon),
          ),
        );
      }

      if (biasNear != null && hits.length > 1) {
        hits.sort((a, b) {
          final da = _haversineM(biasNear, a.point);
          final db = _haversineM(biasNear, b.point);
          return da.compareTo(db);
        });
      }

      if (hits.length <= limit) return hits;
      return hits.take(limit).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<PlaceSearchHit>> _googleAutocomplete({
    required String query,
    LatLng? biasNear,
    int limit = 10,
  }) async {
    final body = <String, dynamic>{
      'input': query,
      'includedRegionCodes': ['sy'],
      'languageCode': 'ar',
    };
    if (biasNear != null) {
      body['locationBias'] = {
        'circle': {
          'center': {
            'latitude': biasNear.latitude,
            'longitude': biasNear.longitude,
          },
          'radius': 50000.0,
        },
      };
    }

    try {
      final res = await http.post(
        Uri.parse('$_placesBase/places:autocomplete'),
        headers: {
          'Content-Type': 'application/json',
          'X-Goog-Api-Key': kGoogleMapsApiKey,
        },
        body: jsonEncode(body),
      );
      if (res.statusCode != 200) return [];

      final map = decodeJsonUtf8(res);
      if (map is! Map<String, dynamic>) return [];

      final suggestions = map['suggestions'];
      if (suggestions is! List) return [];

      final out = <PlaceSearchHit>[];
      for (final raw in suggestions) {
        if (out.length >= limit) break;
        if (raw is! Map) continue;
        final pred = raw['placePrediction'];
        if (pred is! Map) continue;
        final placeId = pred['placeId']?.toString();
        final text = pred['text'];
        String label = '';
        if (text is Map) {
          label = repairUtf8Mojibake(text['text']?.toString().trim() ?? '');
        }
        if (label.isEmpty || placeId == null || placeId.isEmpty) continue;

        final loc = await _placeLocation(placeId);
        if (loc == null) continue;
        out.add(PlaceSearchHit(label: label, point: loc, placeId: placeId));
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<LatLng?> _placeLocation(String placeId) async {
    try {
      final res = await http.get(
        Uri.parse('$_placesBase/places/$placeId'),
        headers: {
          'X-Goog-Api-Key': kGoogleMapsApiKey,
          'X-Goog-FieldMask': 'location',
        },
      );
      if (res.statusCode != 200) return null;
      final map = decodeJsonUtf8(res);
      if (map is! Map<String, dynamic>) return null;
      final loc = map['location'];
      if (loc is! Map) return null;
      final lat = loc['latitude'];
      final lng = loc['longitude'];
      if (lat is! num || lng is! num) return null;
      return LatLng(lat.toDouble(), lng.toDouble());
    } catch (_) {
      return null;
    }
  }

  /// lat/lng → عنوان مقروء (Geocoding API ثم Nominatim عبر الشاشة الأخرى).
  static Future<String?> reverseGeocode(double lat, double lon) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/geocode/json',
        {
          'latlng': '$lat,$lon',
          'key': kGoogleMapsApiKey,
          'language': 'ar',
        },
      );
      final res = await http.get(uri);
      if (res.statusCode != 200) return null;
      final map = decodeJsonUtf8(res);
      if (map is! Map<String, dynamic>) return null;
      if (map['status']?.toString() != 'OK') return null;
      final results = map['results'];
      if (results is! List || results.isEmpty) return null;
      final first = results.first;
      if (first is! Map) return null;
      final addr = first['formatted_address']?.toString().trim();
      if (addr == null || addr.isEmpty) return null;
      return _shorten(repairUtf8Mojibake(addr));
    } catch (_) {
      return null;
    }
  }

  static double _haversineM(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = _rad(b.latitude - a.latitude);
    final dLon = _rad(b.longitude - a.longitude);
    final lat1 = _rad(a.latitude);
    final lat2 = _rad(b.latitude);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;

  static String _shorten(String dn, {int maxParts = 4}) {
    final parts = dn
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length <= maxParts) return dn;
    return parts.take(maxParts).join(', ');
  }
}
