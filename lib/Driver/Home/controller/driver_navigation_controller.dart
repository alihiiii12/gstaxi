import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/utils/osrm_route_client.dart';

/// تنقّل خطوة-بخطوة للسائق (تقريب MAPS.ME).
class DriverNavigationController extends GetxController {
  static const _kVoice = 'nav_voice_enabled';

  final FlutterTts _tts = FlutterTts();
  final Distance _geo = const Distance();
  final _box = GetStorage();

  final active = false.obs;
  final followMode = true.obs;
  /// تشغيل/إيقاف الإرشاد الصوتي.
  final voiceEnabled = true.obs;
  final currentInstruction = ''.obs;
  /// المسافة المتبقية حتى المناورة الحالية (أمتار حقيقية من GPS).
  final distanceToManeuverM = 0.0.obs;
  /// المتبقي حتى الوجهة على طول المسار (كم).
  final remainingKm = 0.0.obs;
  final remainingMin = 0.0.obs;
  final stepIndex = 0.obs;
  final maneuverType = ''.obs;
  final maneuverModifier = ''.obs;

  List<RouteNavStep> _steps = [];
  List<LatLng> _routePoints = [];
  LatLng? _destination;
  String _lastSpoken = '';
  String _lastSpokenInstruction = '';
  DateTime? _lastRerouteAt;
  double _routeDurationMinAtStart = 0;
  double _routeDistanceKmAtStart = 0;

  IconData get maneuverIcon {
    final t = maneuverType.value;
    final m = maneuverModifier.value;
    if (t == 'arrive') return Icons.flag;
    if (t == 'depart' || t == 'continue' || t == 'new name') {
      return Icons.arrow_upward;
    }
    if (t == 'roundabout' || t == 'rotary') return Icons.sync;
    if (t == 'fork') return Icons.call_split;
    if (t == 'turn' || t == 'end of road' || t == 'off ramp' || t == 'on ramp') {
      if (m.contains('left')) return Icons.turn_left;
      if (m.contains('right')) return Icons.turn_right;
      if (m.contains('uturn') || m.contains('u-turn')) return Icons.u_turn_left;
      return Icons.turn_slight_right;
    }
    if (t == 'merge') return Icons.merge_type;
    return Icons.navigation;
  }

  @override
  void onInit() {
    super.onInit();
    final saved = _box.read(_kVoice);
    voiceEnabled.value = saved != false;
  }

  Future<void> setVoiceEnabled(bool value) async {
    voiceEnabled.value = value;
    await _box.write(_kVoice, value);
    if (!value) {
      try {
        await _tts.stop();
      } catch (_) {}
    }
  }

  Future<void> toggleVoice() => setVoiceEnabled(!voiceEnabled.value);

  Future<void> ensureTts() async {
    try {
      await _tts.setLanguage('ar');
      await _tts.setSpeechRate(0.42);
      await _tts.setVolume(1.0);
    } catch (_) {}
  }

  Future<void> startNavigation({
    required List<LatLng> routePoints,
    required List<RouteNavStep> steps,
    required LatLng destination,
    double? distanceKm,
    double? durationMin,
    LatLng? driverPos,
  }) async {
    await ensureTts();
    _routePoints = routePoints;
    _steps = steps;
    _destination = destination;
    _routeDistanceKmAtStart = distanceKm ?? 0;
    _routeDurationMinAtStart = durationMin ?? 0;
    remainingKm.value = _routeDistanceKmAtStart;
    remainingMin.value = _routeDurationMinAtStart;
    followMode.value = true;
    active.value = true;
    _lastSpoken = '';
    _lastSpokenInstruction = '';

    final pos = driverPos;
    stepIndex.value = pos != null ? _bestUpcomingStepIndex(pos) : 0;
    _publishStepMeta();
    if (pos != null) {
      _updateLiveDistances(pos);
      _skipPassedDepartSteps(pos);
    }
    await _speakStepWithDistance(force: true);
  }

  /// تحديث المسار أثناء إعادة التوجيه دون إعادة الصوت من الصفر بلا داعٍ.
  Future<void> updateNavigation({
    required List<LatLng> routePoints,
    required List<RouteNavStep> steps,
    required LatLng destination,
    double? distanceKm,
    double? durationMin,
    LatLng? driverPos,
  }) async {
    if (!active.value || _steps.isEmpty) {
      await startNavigation(
        routePoints: routePoints,
        steps: steps,
        destination: destination,
        distanceKm: distanceKm,
        durationMin: durationMin,
        driverPos: driverPos,
      );
      return;
    }

    _routePoints = routePoints;
    _steps = steps;
    _destination = destination;
    if (distanceKm != null && distanceKm > 0) {
      _routeDistanceKmAtStart = distanceKm;
      remainingKm.value = distanceKm;
    }
    if (durationMin != null && durationMin > 0) {
      _routeDurationMinAtStart = durationMin;
      remainingMin.value = durationMin;
    }

    final pos = driverPos;
    if (pos != null) {
      stepIndex.value = _bestUpcomingStepIndex(pos);
      _publishStepMeta();
      _updateLiveDistances(pos);
      _skipPassedDepartSteps(pos);
      final instr = currentInstruction.value.trim();
      if (instr.isNotEmpty && instr != _lastSpokenInstruction) {
        await _speakStepWithDistance(force: true);
      }
    } else {
      _publishStepMeta();
    }
  }

  void stopNavigation() {
    active.value = false;
    followMode.value = true;
    currentInstruction.value = '';
    distanceToManeuverM.value = 0;
    remainingKm.value = 0;
    remainingMin.value = 0;
    maneuverType.value = '';
    maneuverModifier.value = '';
    stepIndex.value = 0;
    _steps = [];
    _routePoints = [];
    _destination = null;
    _lastSpoken = '';
    _lastSpokenInstruction = '';
    _tts.stop();
  }

  void toggleFollowMode() => followMode.value = !followMode.value;

  void enableFollowMode() => followMode.value = true;

  Future<bool> onDriverMoved(LatLng pos) async {
    if (!active.value || _destination == null) return false;

    _updateLiveDistances(pos);

    if (_routePoints.length >= 2) {
      final nearest = _nearestDistanceMeters(pos, _routePoints);
      if (nearest > 80) {
        final now = DateTime.now();
        if (_lastRerouteAt == null ||
            now.difference(_lastRerouteAt!) > const Duration(seconds: 20)) {
          _lastRerouteAt = now;
          return true;
        }
      }
    }

    if (_steps.isEmpty) return false;

    var idx = stepIndex.value.clamp(0, _steps.length - 1);
    var advanced = false;
    while (idx < _steps.length - 1) {
      final d = _geo.as(LengthUnit.Meter, pos, _steps[idx].location);
      // تجاوز نقطة المناورة → انتقل للخطوة التالية.
      if (d < 35) {
        idx++;
        stepIndex.value = idx;
        advanced = true;
      } else {
        break;
      }
    }

    if (advanced) {
      _publishStepMeta();
      _updateLiveDistances(pos);
      await _speakStepWithDistance(force: true);
      return false;
    }

    // حدّث المسافة الحية للمناورة الحالية فقط (لا تستبدلها بطول الخطوة).
    final step = _steps[stepIndex.value.clamp(0, _steps.length - 1)];
    distanceToManeuverM.value =
        _geo.as(LengthUnit.Meter, pos, step.location).toDouble();

    final nearKey = 'near_${stepIndex.value}';
    final dM = distanceToManeuverM.value;
    if (dM <= 80 && dM >= 25 && _lastSpoken != nearKey) {
      await _speak('${_distanceSpeechAr(dM)}. ${step.instruction}');
      _lastSpoken = nearKey;
      _lastSpokenInstruction = step.instruction;
    }
    return false;
  }

  /// يحدّث النص/الأيقونة فقط — بدون لمس المسافة الحية.
  void _publishStepMeta() {
    if (_steps.isEmpty) {
      currentInstruction.value = 'تابع إلى الوجهة';
      maneuverType.value = 'continue';
      maneuverModifier.value = '';
      return;
    }
    final i = stepIndex.value.clamp(0, _steps.length - 1);
    final step = _steps[i];
    currentInstruction.value = step.instruction;
    maneuverType.value = step.type ?? '';
    maneuverModifier.value = step.modifier ?? '';
  }

  void _updateLiveDistances(LatLng pos) {
    if (_steps.isNotEmpty) {
      final step = _steps[stepIndex.value.clamp(0, _steps.length - 1)];
      distanceToManeuverM.value =
          _geo.as(LengthUnit.Meter, pos, step.location).toDouble();
    }

    final remainM = _remainingAlongRouteMeters(pos);
    if (remainM.isFinite && remainM > 0) {
      remainingKm.value = remainM / 1000.0;
      if (_routeDistanceKmAtStart > 0.05 && _routeDurationMinAtStart > 0) {
        final ratio =
            (remainM / 1000.0 / _routeDistanceKmAtStart).clamp(0.0, 1.5);
        remainingMin.value = (_routeDurationMinAtStart * ratio).clamp(1.0, 999.0);
      } else {
        // تقدير خشن ~30 كم/س إن لم تتوفر مدة المسار.
        remainingMin.value = ((remainM / 1000.0) / 30.0 * 60.0).clamp(1.0, 999.0);
      }
    } else if (_destination != null) {
      remainingKm.value =
          _geo.as(LengthUnit.Meter, pos, _destination!) / 1000.0;
    }
  }

  void _skipPassedDepartSteps(LatLng pos) {
    if (_steps.isEmpty) return;
    var idx = stepIndex.value.clamp(0, _steps.length - 1);
    while (idx < _steps.length - 1) {
      final step = _steps[idx];
      final d = _geo.as(LengthUnit.Meter, pos, step.location);
      final isDepart = step.type == 'depart';
      if ((isDepart && d < 60) || d < 28) {
        idx++;
        stepIndex.value = idx;
        _publishStepMeta();
        _updateLiveDistances(pos);
      } else {
        break;
      }
    }
  }

  int _bestUpcomingStepIndex(LatLng pos) {
    if (_steps.isEmpty) return 0;
    var best = 0;
    var bestScore = double.infinity;
    for (var i = 0; i < _steps.length; i++) {
      final d = _geo.as(LengthUnit.Meter, pos, _steps[i].location);
      // فضّل أقرب مناورات لم تُتجاوز بعد؛ غرامة خفيفة للبعيدة جداً خلفنا.
      final score = d < 25 && i < _steps.length - 1 ? d + 5000 : d;
      if (score < bestScore) {
        bestScore = score;
        best = i;
      }
    }
    if (bestScore < 30 && best < _steps.length - 1) {
      return best + 1;
    }
    return best;
  }

  Future<void> _speakStepWithDistance({bool force = false}) async {
    final text = currentInstruction.value.trim();
    if (text.isEmpty) return;
    if (!force && text == _lastSpokenInstruction) return;
    _lastSpokenInstruction = text;
    final d = distanceToManeuverM.value;
    final phrase = d >= 40 ? '${_distanceSpeechAr(d)}. $text' : text;
    _lastSpoken = phrase;
    await _speak(phrase);
  }

  /// صياغة مسافة عربية واضحة للنطق والعرض المنطقي.
  static String _distanceSpeechAr(double meters) {
    if (!meters.isFinite || meters < 0) return 'بعد قليل';
    if (meters >= 1000) {
      final km = meters / 1000.0;
      if (km >= 10) return 'بعد ${km.round()} كيلومتر';
      final rounded = (km * 10).round() / 10.0;
      if (rounded == rounded.roundToDouble()) {
        return 'بعد ${rounded.round()} كيلومتر';
      }
      final s = rounded.toStringAsFixed(1).replaceAll('.', ' فاصلة ');
      return 'بعد $s كيلومتر';
    }
    final m = meters < 40
        ? meters.round()
        : ((meters / 10).round() * 10).clamp(10, 990);
    return 'بعد $m متر';
  }

  Future<void> _speak(String text) async {
    if (!voiceEnabled.value) return;
    final t = text.trim();
    if (t.isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(t);
    } catch (_) {}
  }

  double _remainingAlongRouteMeters(LatLng pos) {
    if (_routePoints.length < 2) {
      if (_destination == null) return 0;
      return _geo.as(LengthUnit.Meter, pos, _destination!);
    }
    var bestIdx = 0;
    var bestD = double.infinity;
    for (var i = 0; i < _routePoints.length; i++) {
      final d = _geo.as(LengthUnit.Meter, pos, _routePoints[i]);
      if (d < bestD) {
        bestD = d;
        bestIdx = i;
      }
    }
    var sum = bestD;
    for (var i = bestIdx; i < _routePoints.length - 1; i++) {
      sum += _geo.as(LengthUnit.Meter, _routePoints[i], _routePoints[i + 1]);
    }
    return sum;
  }

  static double _nearestDistanceMeters(LatLng pos, List<LatLng> route) {
    final geo = const Distance();
    var best = double.infinity;
    for (var i = 0; i < route.length; i++) {
      final d = geo.as(LengthUnit.Meter, pos, route[i]);
      if (d < best) best = d;
      if (i < route.length - 1) {
        final seg = _distanceToSegmentMeters(pos, route[i], route[i + 1]);
        if (seg < best) best = seg;
      }
    }
    return best;
  }

  static double _distanceToSegmentMeters(LatLng p, LatLng a, LatLng b) {
    final geo = const Distance();
    final ab = geo.as(LengthUnit.Meter, a, b);
    if (ab < 1) return geo.as(LengthUnit.Meter, p, a);
    // إسقاط تقريبي في الإحداثيات المحلية (كافٍ لمسافات قصيرة داخل المدينة).
    final ax = a.longitude;
    final ay = a.latitude;
    final bx = b.longitude;
    final by = b.latitude;
    final px = p.longitude;
    final py = p.latitude;
    final dx = bx - ax;
    final dy = by - ay;
    final t = (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
        .clamp(0.0, 1.0);
    final proj = LatLng(ay + t * dy, ax + t * dx);
    return geo.as(LengthUnit.Meter, p, proj);
  }

  static double distanceBetween(LatLng a, LatLng b) =>
      Geolocator.distanceBetween(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
}
