import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../network/api_endpoints.dart';
import '../network/http_timeouts.dart';

/// يرسل موقع الزبون للسيرفر لخريطة الزبائن في لوحة التحكم.
class CustomerPresenceReporter {
  CustomerPresenceReporter._();
  static final instance = CustomerPresenceReporter._();

  Timer? _timer;
  DateTime? _lastSent;
  static const _minGap = Duration(seconds: 25);

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 35), (_) {
      unawaited(reportOnce());
    });
    unawaited(reportOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unawaited(_goOffline());
  }

  Future<void> reportOnce({double? latitude, double? longitude}) async {
    try {
      final now = DateTime.now();
      if (_lastSent != null && now.difference(_lastSent!) < _minGap) {
        return;
      }
      double lat = latitude ?? 0;
      double lng = longitude ?? 0;
      if (latitude == null || longitude == null) {
        final perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied ||
            perm == LocationPermission.deniedForever) {
          return;
        }
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 8),
          ),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }
      final headers = await ApiEndpoints.headers();
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.customerUpdateLocation),
            headers: headers,
            body: jsonEncode({
              'latitude': lat,
              'longitude': lng,
            }),
          )
          .timeout(HttpTimeouts.poll);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        _lastSent = now;
      }
    } catch (_) {}
  }

  Future<void> _goOffline() async {
    try {
      final headers = await ApiEndpoints.headers();
      await http
          .post(
            Uri.parse(ApiEndpoints.customerGoOffline),
            headers: headers,
            body: '{}',
          )
          .timeout(HttpTimeouts.poll);
    } catch (_) {}
  }
}
