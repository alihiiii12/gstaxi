import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'api_endpoints.dart';

enum NetworkQuality { good, slow, offline }

/// حالة الإنترنت للتطبيق كله (راكب + سائق): مقطوع / ضعيف / جيد.
/// تجمع حالة الشبكة من النظام مع فحص دوري خفيف للوصول إلى الخادم.
class NetworkStatusService with WidgetsBindingObserver {
  NetworkStatusService._();

  static final NetworkStatusService instance = NetworkStatusService._();

  final ValueNotifier<NetworkQuality> quality =
      ValueNotifier<NetworkQuality>(NetworkQuality.good);

  static const Duration _probeTimeout = Duration(seconds: 6);
  static const Duration _slowThreshold = Duration(milliseconds: 3500);
  static const Duration _intervalGood = Duration(seconds: 15);
  static const Duration _intervalBad = Duration(seconds: 4);

  Timer? _timer;
  bool _started = false;
  bool _probing = false;
  bool _foreground = true;
  bool _noNetwork = false;
  int _badStreak = 0;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    Connectivity().onConnectivityChanged.listen(_onConnectivity);
    unawaited(Connectivity().checkConnectivity().then(_onConnectivity));
    _schedule(const Duration(seconds: 2));
  }

  /// فحص فوري (مثلاً عند الضغط على الشريط).
  void recheck() => _schedule(Duration.zero);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _schedule(const Duration(milliseconds: 500));
    } else {
      _timer?.cancel();
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    _noNetwork =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    if (_noNetwork) {
      _badStreak = 0;
      quality.value = NetworkQuality.offline;
      _schedule(_intervalBad);
    } else {
      _schedule(const Duration(milliseconds: 800));
    }
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    if (!_foreground) return;
    _timer = Timer(delay, () => unawaited(_probe()));
  }

  Future<void> _probe() async {
    if (_probing || !_foreground) return;
    _probing = true;
    try {
      if (_noNetwork) {
        quality.value = NetworkQuality.offline;
        return;
      }
      final sw = Stopwatch()..start();
      NetworkQuality next;
      try {
        await http
            .head(Uri.parse(ApiEndpoints.connectivityProbe))
            .timeout(_probeTimeout);
        sw.stop();
        next = sw.elapsed > _slowThreshold
            ? NetworkQuality.slow
            : NetworkQuality.good;
      } on TimeoutException {
        next = NetworkQuality.slow;
      } on SocketException {
        next = NetworkQuality.offline;
      } on http.ClientException {
        next = NetworkQuality.offline;
      } catch (_) {
        next = NetworkQuality.slow;
      }

      if (next == NetworkQuality.good) {
        _badStreak = 0;
        quality.value = NetworkQuality.good;
      } else {
        _badStreak++;
        // فحصان سيئان متتاليان قبل إظهار التنبيه — يمنع الوميض عند تأخّر عابر.
        if (_badStreak >= 2) quality.value = next;
      }
    } finally {
      _probing = false;
      _schedule(
        quality.value == NetworkQuality.good && _badStreak == 0
            ? _intervalGood
            : _intervalBad,
      );
    }
  }
}
