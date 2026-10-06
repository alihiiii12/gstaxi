import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../network/api_endpoints.dart';
import '../network/http_timeouts.dart';
import '../utils/utf8_text.dart';

/// بعد إرسال SOS: يرسل موقع الهاتف كل بضع ثوانٍ لتتابعه الإدارة مباشرة على الخريطة.
class SosLiveReporter {
  SosLiveReporter._();
  static final instance = SosLiveReporter._();

  static const _interval = Duration(seconds: 5);
  static const _duration = Duration(minutes: 30);
  static const _storageKey = 'sos_live_until_ms';

  final _box = GetStorage();
  Timer? _timer;
  bool _busy = false;

  void start() {
    final until = DateTime.now().add(_duration).millisecondsSinceEpoch;
    _box.write(_storageKey, until);
    _run();
  }

  /// يستأنف الإرسال بعد إعادة فتح التطبيق إن كان هناك SOS حديث.
  void resumeIfActive() {
    if (_timer != null) return;
    final until = _box.read(_storageKey);
    if (until is int && until > DateTime.now().millisecondsSinceEpoch) {
      _run();
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _box.remove(_storageKey);
  }

  void _run() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  Future<void> _tick() async {
    if (_busy) return;
    final until = _box.read(_storageKey);
    if (until is! int || until <= DateTime.now().millisecondsSinceEpoch) {
      stop();
      return;
    }
    _busy = true;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 4),
        ),
      );
      final headers = await ApiEndpoints.headers();
      final res = await http
          .post(
            Uri.parse(ApiEndpoints.emergencySosLive),
            headers: headers,
            body: jsonEncode({
              'latitude': pos.latitude,
              'longitude': pos.longitude,
            }),
          )
          .timeout(HttpTimeouts.poll);
      if (res.statusCode == 200) {
        final decoded = decodeJsonUtf8(res);
        if (decoded is Map && decoded['active'] == false) {
          stop();
        }
      }
    } catch (_) {
    } finally {
      _busy = false;
    }
  }
}
