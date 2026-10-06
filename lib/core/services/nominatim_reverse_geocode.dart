import 'dart:async';

import 'package:http/http.dart' as http;

import '../utils/utf8_text.dart';
import 'google_places_service.dart';

/// قيم تعرض في الواجهة عندما لا يُرجِع الخادم اسم مكان.
bool looksLikeMissingPlaceLabel(String s) {
  final t = s.trim();
  if (t.isEmpty) return true;
  const placeholders = {'—', '-', '–', '‒'};
  return placeholders.contains(t);
}

class _OneAtATime {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() fn) {
    final c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await fn());
      } catch (e, st) {
        c.completeError(e, st);
      }
    });
    return c.future;
  }
}

/// عكس ترميز (lat/lng → اسم مقروء) عبر Nominatim، مع تخزين مؤقت وحدّ معدّل بسيط.
class NominatimReverseGeocode {
  NominatimReverseGeocode._();

  static const Map<String, String> _headers = {
    'Accept': 'application/json',
    'Accept-Language': 'ar,en',
    'User-Agent':
        'SyriaTaxiCustomer/1.0 (Flutter app; contact: app@syriataxi.local)',
  };

  static final Map<String, String> _cache = {};
  static final _OneAtATime _gate = _OneAtATime();

  static String _shorten(String dn, {int maxParts = 4}) {
    final parts = dn
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.length <= maxParts) return dn;
    return parts.take(maxParts).join(', ');
  }

  static DateTime? _lastRequestEnd;

  /// يُرجع [display_name] مختصراً أو null عند الفشل.
  static Future<String?> displayNameForLatLng(double lat, double lon) async {
    final key = '${lat.toStringAsFixed(5)},${lon.toStringAsFixed(5)}';
    final hit = _cache[key];
    if (hit != null && hit.isNotEmpty) return hit;

    return _gate.run<String?>(() async {
      final now = DateTime.now();
      if (_lastRequestEnd != null) {
        final earliest =
            _lastRequestEnd!.add(const Duration(milliseconds: 1100));
        if (now.isBefore(earliest)) {
          await Future<void>.delayed(earliest.difference(now));
        }
      }
      try {
        final again = _cache[key];
        if (again != null && again.isNotEmpty) return again;

        final google = await GooglePlacesService.reverseGeocode(lat, lon);
        if (google != null && google.isNotEmpty) {
          final fixed = repairUtf8Mojibake(google);
          _cache[key] = fixed;
          return fixed;
        }

        final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
          'format': 'json',
          'lat': '$lat',
          'lon': '$lon',
          'zoom': '18',
          'addressdetails': '1',
        });
        final res = await http.get(uri, headers: _headers);
        if (res.statusCode != 200) return null;
        final map = decodeJsonUtf8(res);
        if (map is! Map<String, dynamic>) return null;
        final dn = map['display_name']?.toString().trim();
        if (dn == null || dn.isEmpty) return null;
        final short = repairUtf8Mojibake(_shorten(dn));
        _cache[key] = short;
        return short;
      } finally {
        _lastRequestEnd = DateTime.now();
      }
    });
  }
}
