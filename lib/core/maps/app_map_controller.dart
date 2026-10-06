import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import 'app_map_models.dart';
import 'map_performance_profile.dart';
import 'map_style_config.dart';

export 'app_map_models.dart';
export 'map_performance_profile.dart';
export 'map_style_config.dart';

/// تحكم موحّد لخريطة MapLibre (بديل Google Maps — أسلوب MAPS.ME).
class AppMapController {
  MapLibreMapController? _controller;
  bool _styleReady = false;
  bool _imagesReady = false;
  ll.LatLng _lastCenter = const ll.LatLng(33.5138, 36.2765);
  double _lastZoom = 14;
  double _lastBearing = 0;
  double _lastTilt = 0;
  DateTime? _lastRotateAt;
  final List<Symbol> _symbols = [];
  final List<Line> _lines = [];
  Symbol? _driverSymbol;
  String _styleUrl = MapStyleConfig.dayStyleUrl;

  bool get isReady => _controller != null && _styleReady;
  String get styleUrl => _styleUrl;
  double get currentZoom {
    final cam = _controller?.cameraPosition;
    if (cam != null && cam.zoom.isFinite && cam.zoom > 0) return cam.zoom;
    return _lastZoom > 0 ? _lastZoom : 15;
  }
  double get currentBearing => _lastBearing;
  double get currentTilt => _lastTilt;
  ll.LatLng get cameraCenter {
    final cam = _controller?.cameraPosition;
    final t = cam?.target;
    if (t != null && t.latitude.isFinite && t.longitude.isFinite) {
      return ll.LatLng(t.latitude, t.longitude);
    }
    return _lastCenter;
  }

  /// مزامنة مركز الكاميرا من الخريطة (حتى أثناء الحركة البرمجية).
  void pullCameraCenterFromMap() {
    final cam = _controller?.cameraPosition;
    if (cam == null) return;
    if (cam.bearing.isFinite) _lastBearing = cam.bearing;
    if (cam.tilt.isFinite) _lastTilt = cam.tilt;
    if (cam.zoom.isFinite && cam.zoom > 0) _lastZoom = cam.zoom;
    final t = cam.target;
    if (t.latitude.isFinite && t.longitude.isFinite) {
      _lastCenter = ll.LatLng(t.latitude, t.longitude);
    }
  }

  Future<void> attach(MapLibreMapController controller) async {
    // عند تبديل النهار/الليل يُعاد إنشاء الخريطة — يجب إعادة تسجيل الصور.
    _controller = controller;
    _styleReady = false;
    _imagesReady = false;
    _driverSymbol = null;
    _symbols.clear();
    _lines.clear();
  }

  void detach() {
    _stopDriverPoseAnim();
    _controller = null;
    _styleReady = false;
    _imagesReady = false;
    _driverSymbol = null;
    _displayDriverPose = null;
    _targetDriverPose = null;
    _fixPose = null;
    _fixAt = null;
    _interpTo = null;
    _followCamInFlight = false;
    _symbols.clear();
    _lines.clear();
  }

  Future<void> onStyleLoaded({bool nightMode = false}) async {
    _styleReady = true;
    _imagesReady = false;
    _lastZoom = MapStyleConfig.mapDefaultZoom;
    _lastTilt = MapStyleConfig.mapDefaultTilt;
    await _ensureImages();
    final c = _controller;
    if (c != null) {
      try {
        await c.setSymbolIconAllowOverlap(true);
        await c.setSymbolIconIgnorePlacement(true);
      } catch (_) {}
      await _applyPerformanceProfile(c);
      // لا تستخدم setLayerProperties هنا — مع skipNulls:false تمسح
      // text-field/icon-image وتختفي الأسماء والأيقونات.
    }
  }

  /// تخفيف الحمل على الأجهزة الضعيفة مع الإبقاء على كامل الجودة للقوية.
  Future<void> _applyPerformanceProfile(MapLibreMapController c) async {
    final low = MapPerformanceProfile.isLowEnd;
    try {
      await c.setMaximumFps(low ? 30 : 60);
    } catch (_) {}
    if (!low) return;
    // إخفاء البثق ثلاثي الأبعاد والطبقة الراجحة فقط — أماكن POI تبقى ظاهرة.
    for (final id in const [
      'building-3d',
      'natural_earth',
    ]) {
      try {
        await c.setLayerVisibility(id, false);
      } catch (_) {}
    }
  }

  Future<void> setStyleUrl(String url) async {
    if (url == _styleUrl) return;
    _styleUrl = url;
    _styleReady = false;
    _imagesReady = false;
    _driverSymbol = null;
    // إعادة تحميل الستايل تتم عبر إعادة بناء الودجت بمفتاح جديد.
  }

  bool _driverTripActive = false;
  /// طابور تسلسلي — يمنع إضافة سيارتين عند تداخل GPS/المزامنة.
  Future<void> _driverPoseChain = Future<void>.value();
  bool _driverPosePaintQueued = false;
  bool _driverPosePaintRunning = false;

  /// الموقع المعروض (مُنعَّم) مقابل [_lastDriverPose] هدف الـ GPS.
  ll.LatLng? _displayDriverPose;
  double _displayDriverHeading = 0;
  ll.LatLng? _targetDriverPose;
  double _targetDriverHeading = 0;
  Timer? _driverPoseAnimTimer;
  DateTime? _driverPoseLastTickAt;
  static const double _driverPoseSnapMeters = 90;
  /// ثابت زمني أصغر = حركة أسرع وأكثر مباشرة نحو GPS.
  static const double _driverPoseTauSec = 0.12;
  static const double _driverIconSizeTrip = 0.98;
  static const double _driverIconSizeIdle = 0.92;

  /// آخر قراءة GPS فعلية — يُستقرأ منها الموقع بين القراءات بالسرعة والاتجاه.
  ll.LatLng? _fixPose;
  DateTime? _fixAt;
  double _fixSpeedMps = 0;
  static const double _extrapolateMinSpeedMps = 1.4;
  static const double _extrapolateMaxSec = 1.3;

  /// موقع بعيد (من السيرفر كل بضع ثوانٍ): حركة خطية من المعروض إلى القراءة الجديدة
  /// على مدى الفاصل بين القراءتين — بلا توقف وبلا رجوع للخلف.
  bool _remotePose = false;
  ll.LatLng? _interpFrom;
  ll.LatLng? _interpTo;
  DateTime? _interpStartAt;
  int _interpDurMs = 1000;

  /// متابعة الكاميرا للسيارة المعروضة إطاراً بإطار (بدل animate لكل قراءة GPS).
  bool _followCam = false;
  bool _followCamDirty = false;
  bool _followCamInFlight = false;
  double _followTilt = 0;
  double _followLookAhead = 0;
  DateTime? _followHoldUntil;
  DateTime? _lastFollowCamAt;

  /// تفعيل/إيقاف متابعة الكاميرا للسيارة. [hold] يؤجّل المتابعة حتى تنتهي حركة جارية.
  void setDriverFollow({
    required bool enabled,
    double tilt = 0,
    double lookAheadMeters = 0,
    Duration hold = Duration.zero,
  }) {
    _followCam = enabled;
    if (!enabled) {
      _followCamDirty = false;
      return;
    }
    _followTilt = tilt;
    _followLookAhead = lookAheadMeters;
    if (hold > Duration.zero) _holdFollow(hold);
    _followCamDirty = true;
    if (_displayDriverPose != null) _ensureDriverPoseAnimTimer();
  }

  /// إصبع المستخدم على الخريطة — لا نحرّك الكاميرا تحته.
  bool _userTouching = false;
  int _touchPointers = 0;

  void noteUserPointer({required bool down}) {
    _touchPointers = (_touchPointers + (down ? 1 : -1)).clamp(0, 10);
    _userTouching = _touchPointers > 0;
    if (!_userTouching && _followCam) {
      _followCamDirty = true;
      if (_displayDriverPose != null) _ensureDriverPoseAnimTimer();
    }
  }

  void _holdFollow(Duration d) {
    final until = DateTime.now().add(d);
    final cur = _followHoldUntil;
    if (cur == null || until.isAfter(cur)) _followHoldUntil = until;
  }

  /// تحديث سريع لموقع/اتجاه سيارة السائق دون إعادة رسم المسار.
  /// [heading] اتجاه جغرافي (شمال=0)؛ يُحوَّل نسبةً لدوران الخريطة مثل سهم Google Maps.
  /// مسار واحد فقط لأيقونة السيارة — يمنع التكرار عند مزامنة المسار/بدء الرحلة.
  Future<void> updateDriverPose(
    ll.LatLng point,
    double heading, {
    bool? tripActive,
    double? speedMps,
    bool remote = false,
  }) async {
    if (tripActive != null) _driverTripActive = tripActive;
    _remotePose = remote;
    _lastDriverPose = point;
    if (heading.isFinite) _lastDriverHeading = heading;

    // أثناء clear/rebuild للـ overlay نخزّن الموقع فقط؛ يُعاد الرسم في نهاية sync.
    if (_syncingOverlay) return;

    final targetHeading =
        heading.isFinite ? heading : _lastDriverHeading;
    final prevFixAt = _fixAt;
    _noteDriverFix(point, speedMps);
    final newFixAt = _fixAt;
    final isNewFix = newFixAt != null && newFixAt != prevFixAt;
    _targetDriverPose = point;
    _targetDriverHeading = targetHeading;

    final display = _displayDriverPose;
    if (display == null) {
      _displayDriverPose = point;
      _displayDriverHeading = targetHeading;
      _interpTo = null;
      _followCamDirty = true;
      _ensureDriverPoseAnimTimer();
      await _applyDriverPoseNow();
      return;
    }

    final meters = const ll.Distance().as(
      ll.LengthUnit.Meter,
      display,
      point,
    );

    // قفزة كبيرة → تثبيت فوري.
    if (meters >= _driverPoseSnapMeters) {
      _displayDriverPose = point;
      _displayDriverHeading = targetHeading;
      _interpTo = null;
      _followCamDirty = true;
      _ensureDriverPoseAnimTimer();
      await _applyDriverPoseNow();
      return;
    }

    if (remote && isNewFix) {
      final gapMs = prevFixAt == null
          ? 1000
          : newFixAt.difference(prevFixAt).inMilliseconds;
      _interpFrom = display;
      _interpTo = point;
      _interpStartAt = newFixAt;
      _interpDurMs = (gapMs * 1.1).clamp(400, 4500).round();
    }

    _ensureDriverPoseAnimTimer();
  }

  /// قراءة جديدة فقط عند تغيّر الموقع — تحديثات الاتجاه وحدها لا تُصفّر زمن الاستقراء.
  void _noteDriverFix(ll.LatLng point, double? speedMps) {
    final now = DateTime.now();
    final prev = _fixPose;
    final prevAt = _fixAt;
    if (prev != null &&
        (prev.latitude - point.latitude).abs() < 1e-7 &&
        (prev.longitude - point.longitude).abs() < 1e-7) {
      return;
    }
    var speed = speedMps;
    if ((speed == null || !speed.isFinite || speed < 0) &&
        prev != null &&
        prevAt != null) {
      final dt = now.difference(prevAt).inMilliseconds / 1000.0;
      if (dt >= 0.2 && dt <= 3) {
        speed = const ll.Distance().as(ll.LengthUnit.Meter, prev, point) / dt;
      }
    }
    _fixSpeedMps =
        (speed != null && speed.isFinite) ? speed.clamp(0.0, 45.0) : 0;
    _fixPose = point;
    _fixAt = now;
  }

  bool _isExtrapolating(DateTime now) {
    final at = _fixAt;
    if (_remotePose || _fixPose == null || at == null) return false;
    if (_fixSpeedMps < _extrapolateMinSpeedMps) return false;
    return now.difference(at).inMilliseconds / 1000.0 < _extrapolateMaxSec;
  }

  /// الموقع المتوقَّع الآن: آخر قراءة + السرعة × الزمن منذها (بحد أقصى).
  ll.LatLng? _predictedDriverPose(DateTime now) {
    final fix = _fixPose;
    final at = _fixAt;
    if (fix == null || at == null) return _targetDriverPose;
    if (_remotePose || _fixSpeedMps < _extrapolateMinSpeedMps) return fix;
    final dt = (now.difference(at).inMilliseconds / 1000.0)
        .clamp(0.0, _extrapolateMaxSec);
    if (dt <= 0) return fix;
    return const ll.Distance().offset(
      fix,
      _fixSpeedMps * dt,
      _targetDriverHeading,
    );
  }

  void _maybeFollowCamera(DateTime now) {
    if (!_followCam || !_followCamDirty || _followCamInFlight) return;
    if (_userTouching) return;
    final c = _controller;
    final p = _displayDriverPose;
    if (c == null || !_styleReady || p == null) return;
    final hold = _followHoldUntil;
    if (hold != null && now.isBefore(hold)) return;
    final gapMs = MapPerformanceProfile.isLowEnd ? 50 : 30;
    final last = _lastFollowCamAt;
    if (last != null && now.difference(last).inMilliseconds < gapMs) return;

    // عند التوقف لا نُدير الخريطة مع اهتزاز البوصلة.
    final moving = _fixSpeedMps >= _extrapolateMinSpeedMps;
    final bearing = moving ? _displayDriverHeading : _lastBearing;
    var target = p;
    if (_followLookAhead > 0 && bearing.isFinite) {
      target = const ll.Distance().offset(p, _followLookAhead, bearing);
    }
    final zoom = currentZoom;
    _lastCenter = target;
    _lastBearing = bearing;
    _lastTilt = _followTilt;
    _lastZoom = zoom;
    _lastFollowCamAt = now;
    _followCamDirty = false;
    _markProgrammaticCamera(260);
    _followCamInFlight = true;
    c
        .moveCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(target.latitude, target.longitude),
              zoom: zoom,
              bearing: bearing,
              tilt: _followTilt,
            ),
          ),
        )
        .catchError((_) => false)
        .whenComplete(() => _followCamInFlight = false);
  }

  void _ensureDriverPoseAnimTimer() {
    if (_driverPoseAnimTimer != null) return;
    _driverPoseLastTickAt = DateTime.now();
    final periodMs = MapPerformanceProfile.isLowEnd ? 33 : 16;
    _driverPoseAnimTimer = Timer.periodic(
      Duration(milliseconds: periodMs),
      (_) => _tickDriverPoseAnim(),
    );
  }

  void _stopDriverPoseAnim() {
    _driverPoseAnimTimer?.cancel();
    _driverPoseAnimTimer = null;
    _driverPoseLastTickAt = null;
  }

  void _tickDriverPoseAnim() {
    final display = _displayDriverPose;
    final now = DateTime.now();
    final target = _predictedDriverPose(now);
    if (display == null || target == null) {
      _stopDriverPoseAnim();
      return;
    }

    final last = _driverPoseLastTickAt ?? now;
    _driverPoseLastTickAt = now;
    final dt = (now.difference(last).inMilliseconds / 1000.0).clamp(0.0, 0.08);
    // تقريب أسي نحو الموقع المتوقَّع — حركة مستمرة بلا توقف بين عيّنات GPS.
    final alpha = (1 - math.exp(-dt / _driverPoseTauSec)).clamp(0.0, 1.0);

    final from = _interpFrom;
    final to = _interpTo;
    final startAt = _interpStartAt;
    if (_remotePose && from != null && to != null && startAt != null) {
      final f = (now.difference(startAt).inMilliseconds / _interpDurMs)
          .clamp(0.0, 1.0);
      _displayDriverPose = ll.LatLng(
        from.latitude + (to.latitude - from.latitude) * f,
        from.longitude + (to.longitude - from.longitude) * f,
      );
      final hd = _shortestHeadingDelta(
        _displayDriverHeading,
        _targetDriverHeading,
      );
      _displayDriverHeading = (_displayDriverHeading + hd * alpha + 360) % 360;
      _followCamDirty = true;
      unawaited(_requestDriverPosePaint());
      _maybeFollowCamera(now);
      if (f >= 1 && hd.abs() < 0.8) _interpTo = null;
      return;
    }

    final meters = const ll.Distance().as(
      ll.LengthUnit.Meter,
      display,
      target,
    );
    final headingDelta = _shortestHeadingDelta(
      _displayDriverHeading,
      _targetDriverHeading,
    );

    if (meters < 0.35 && headingDelta.abs() < 0.8) {
      _displayDriverPose = target;
      _displayDriverHeading = _targetDriverHeading;
      unawaited(_requestDriverPosePaint());
      _maybeFollowCamera(now);
      final hold = _followHoldUntil;
      final camPending = _followCam &&
          (_followCamDirty ||
              _followCamInFlight ||
              (hold != null && now.isBefore(hold)));
      if (!_isExtrapolating(now) && !camPending) {
        _stopDriverPoseAnim();
      }
      return;
    }

    _displayDriverPose = ll.LatLng(
      display.latitude + (target.latitude - display.latitude) * alpha,
      display.longitude + (target.longitude - display.longitude) * alpha,
    );
    _displayDriverHeading =
        (_displayDriverHeading + headingDelta * alpha + 360) % 360;
    _followCamDirty = true;

    unawaited(_requestDriverPosePaint());
    _maybeFollowCamera(now);
  }

  static double _shortestHeadingDelta(double from, double to) {
    var d = (to - from) % 360;
    if (d > 180) d -= 360;
    if (d < -180) d += 360;
    return d;
  }

  Future<void> _applyDriverPoseNow() => _requestDriverPosePaint();

  /// دمج إطارات الرسم — يمنع طابوراً طويلاً من updateSymbol أثناء التنعيم.
  Future<void> _requestDriverPosePaint() {
    _driverPosePaintQueued = true;
    if (_driverPosePaintRunning) return _driverPoseChain;
    _driverPosePaintRunning = true;
    _driverPoseChain = _driverPoseChain.then((_) async {
      try {
        while (_driverPosePaintQueued) {
          _driverPosePaintQueued = false;
          await _applyDriverPoseLocked();
        }
      } finally {
        _driverPosePaintRunning = false;
        if (_driverPosePaintQueued) {
          unawaited(_requestDriverPosePaint());
        }
      }
    });
    return _driverPoseChain;
  }

  Future<void> _applyDriverPoseLocked() async {
    if (_syncingOverlay) return;
    final point = _displayDriverPose ?? _lastDriverPose;
    final c = _controller;
    if (point == null || c == null || !_styleReady) return;
    await _ensureImages();
    if (_syncingOverlay || !identical(c, _controller)) return;

    final heading = _displayDriverPose != null
        ? _displayDriverHeading
        : _lastDriverHeading;
    final mapBearing = _followCam
        ? _lastBearing
        : (c.cameraPosition?.bearing ?? _lastBearing);
    final iconRotate = (heading - mapBearing + 360) % 360;
    final opts = SymbolOptions(
      geometry: LatLng(point.latitude, point.longitude),
      iconImage: _driverTripActive ? 'app-driver-rear' : 'app-driver',
      iconSize:
          _driverTripActive ? _driverIconSizeTrip : _driverIconSizeIdle,
      iconRotate: iconRotate,
      iconAnchor: 'center',
    );

    final existing = _driverSymbol;
    if (existing != null) {
      try {
        await c.updateSymbol(existing, opts);
        return;
      } catch (e) {
        debugPrint('[AppMapController] driver pose update: $e');
        await _removeDriverSymbolOnly();
      }
    }

    // ضمان عدم بقاء رمز يتيم قبل الإضافة.
    await _removeDriverSymbolOnly();
    try {
      _driverSymbol = await c.addSymbol(opts);
    } catch (e2) {
      debugPrint('[AppMapController] driver pose add: $e2');
      _driverSymbol = null;
    }
  }

  Future<void> _removeDriverSymbolOnly() async {
    final stale = _driverSymbol;
    _driverSymbol = null;
    if (stale == null) return;
    final c = _controller;
    if (c == null) return;
    try {
      await c.removeSymbol(stale);
    } catch (_) {}
  }

  /// إزالة سيارة السائق من الخريطة (بعد انتهاء الرحلة).
  Future<void> clearDriverPose() async {
    _stopDriverPoseAnim();
    _displayDriverPose = null;
    _targetDriverPose = null;
    _lastDriverPose = null;
    _fixPose = null;
    _fixAt = null;
    _fixSpeedMps = 0;
    _interpTo = null;
    _driverTripActive = false;
    await _removeDriverSymbolOnly();
  }

  /// عتبة سحب يدوي (متر) — أقل من السابق حتى يتوقف التتبع بسرعة مثل Google Maps.
  static const double _userPanMeters = 12;

  /// مزامنة الكاميرا بعد سحب المستخدم وإعادة توجيه أيقونة السيارة.
  /// يعيد `true` إذا تحرّك المركز (تصفح)، و`false` إذا تغيّر الزوم/الدوران فقط.
  bool syncCameraFromUserIdle() {
    final cam = _controller?.cameraPosition;
    if (cam == null) return false;
    final prevCenter = _lastCenter;
    if (cam.bearing.isFinite) _lastBearing = cam.bearing;
    if (cam.tilt.isFinite) _lastTilt = cam.tilt;
    if (cam.zoom.isFinite && cam.zoom > 0) _lastZoom = cam.zoom;
    var panned = false;
    if (cam.target.latitude.isFinite) {
      final next = ll.LatLng(cam.target.latitude, cam.target.longitude);
      final movedM = const ll.Distance().as(
        ll.LengthUnit.Meter,
        prevCenter,
        next,
      );
      // زوم القرص يزيح الهدف قليلاً بسبب look-ahead — لا نعتبره تصفحاً.
      if (movedM > _userPanMeters) panned = true;
      _lastCenter = next;
    }
    // إعادة رسم الدوران فقط — بدون إعادة استهداف الحركة الناعمة.
    if (_displayDriverPose != null || _lastDriverPose != null) {
      unawaited(_requestDriverPosePaint());
    }
    return panned;
  }

  /// أثناء حركة الكاميرا: يكشف سحب المستخدم عندما لا تكون الحركة برمجية.
  bool notePossibleUserPan(CameraPosition? cam) {
    if (cam == null) return false;
    // أثناء animate/move برمجي لا نفسّر الإزاحة كتصفح (البداية بعيدة عن الهدف).
    if (isProgrammaticCameraActive && !_userTouching) return false;
    final t = cam.target;
    if (!t.latitude.isFinite || !t.longitude.isFinite) return false;
    final next = ll.LatLng(t.latitude, t.longitude);
    final fromExpected = const ll.Distance().as(
      ll.LengthUnit.Meter,
      _lastCenter,
      next,
    );
    if (fromExpected <= _userPanMeters) return false;
    _lastCenter = next;
    if (cam.bearing.isFinite) _lastBearing = cam.bearing;
    if (cam.tilt.isFinite) _lastTilt = cam.tilt;
    if (cam.zoom.isFinite && cam.zoom > 0) _lastZoom = cam.zoom;
    return true;
  }

  void clearProgrammaticCameraHold() {
    _programmaticCamera = false;
    _programmaticCameraUntil = null;
  }

  Future<void> move(ll.LatLng point, double zoom, {bool animate = true}) async {
    _lastCenter = point;
    _lastZoom = zoom;
    if (_lastTilt <= 0) _lastTilt = MapStyleConfig.mapDefaultTilt;
    final c = _controller;
    if (c == null || !_styleReady) return;
    final animMs = animate ? 420 : 0;
    _markProgrammaticCamera(animate ? 520 : 280);
    _holdFollow(Duration(milliseconds: animMs + 150));
    final cam = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: LatLng(point.latitude, point.longitude),
        zoom: zoom,
        bearing: _lastBearing,
        tilt: _lastTilt,
      ),
    );
    if (animate) {
      await c.animateCamera(cam, duration: Duration(milliseconds: animMs));
    } else {
      await c.moveCamera(cam);
    }
  }

  Future<void> rotate(double degrees, {bool force = false}) async {
    if (!degrees.isFinite) return;
    final now = DateTime.now();
    final delta = (degrees - _lastBearing).abs();
    final wrapped = delta > 180 ? 360 - delta : delta;
    if (!force) {
      if (wrapped < 12) return;
      if (_lastRotateAt != null &&
          now.difference(_lastRotateAt!) < const Duration(milliseconds: 1600)) {
        return;
      }
    }
    _lastBearing = degrees;
    _lastRotateAt = now;
    final c = _controller;
    if (c == null || !_styleReady) return;
    await c.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(_lastCenter.latitude, _lastCenter.longitude),
          zoom: _lastZoom,
          bearing: degrees,
          tilt: _lastTilt,
        ),
      ),
    );
  }

  bool _programmaticCamera = false;
  DateTime? _programmaticCameraUntil;
  AppMapOverlay? _queuedOverlay;
  bool _syncingOverlay = false;
  ll.LatLng? _lastDriverPose;
  double _lastDriverHeading = 0;

  Future<void> setNavigationCamera({
    required ll.LatLng point,
    required double bearing,
    double zoom = 17.2,
    double tilt = 55,
    /// إزاحة نقطة النظر للأمام فتظهر السيارة أسفل الشاشة مثل MAPS.ME.
    double lookAheadMeters = 42,
    bool animate = false,
    /// مدة الحركة الناعمة (مثل Google Maps). الافتراضي ~320ms للمتابعة المستمرة.
    Duration? duration,
  }) async {
    var target = point;
    if (lookAheadMeters > 0 && bearing.isFinite) {
      target = const ll.Distance().offset(point, lookAheadMeters, bearing);
    }
    _lastCenter = target;
    _lastZoom = zoom;
    _lastBearing = bearing;
    _lastTilt = tilt;
    final c = _controller;
    if (c == null || !_styleReady) return;
    final anim = duration ??
        (animate ? const Duration(milliseconds: 320) : Duration.zero);
    final holdMs = animate
        ? (anim.inMilliseconds + 120).clamp(280, 900)
        : 260;
    _markProgrammaticCamera(holdMs);
    _holdFollow(Duration(milliseconds: anim.inMilliseconds + 60));
    final cam = CameraUpdate.newCameraPosition(
      CameraPosition(
        target: LatLng(target.latitude, target.longitude),
        zoom: zoom,
        bearing: bearing,
        tilt: tilt,
      ),
    );
    if (animate || anim > Duration.zero) {
      await c.animateCamera(
        cam,
        duration: anim > Duration.zero
            ? anim
            : const Duration(milliseconds: 320),
      );
    } else {
      await c.moveCamera(cam);
    }
  }

  void _markProgrammaticCamera(int holdMs) {
    _programmaticCamera = true;
    final until = DateTime.now().add(Duration(milliseconds: holdMs));
    if (_programmaticCameraUntil == null ||
        until.isAfter(_programmaticCameraUntil!)) {
      _programmaticCameraUntil = until;
    }
  }

  /// لا يُصفَّر عند أول idle — يمنع إيقاف المتابعة أثناء animateCamera.
  bool get consumeProgrammaticCameraIdle {
    final until = _programmaticCameraUntil;
    if (_programmaticCamera ||
        (until != null && DateTime.now().isBefore(until))) {
      if (until != null && !DateTime.now().isBefore(until)) {
        _programmaticCamera = false;
        _programmaticCameraUntil = null;
      }
      return true;
    }
    return false;
  }

  bool get isProgrammaticCameraActive {
    final until = _programmaticCameraUntil;
    return _programmaticCamera ||
        (until != null && DateTime.now().isBefore(until));
  }

  Future<void> resetNorth({ll.LatLng? at, double? zoom}) async {
    final point = at ?? _lastCenter;
    _lastBearing = 0;
    await setNavigationCamera(
      point: point,
      bearing: 0,
      zoom: zoom ?? MapStyleConfig.mapDefaultZoom,
      tilt: MapStyleConfig.mapDefaultTilt,
      lookAheadMeters: 0,
    );
  }

  Future<void> fitPoints(
    List<ll.LatLng> points, {
    double padding = 48,
    bool animate = false,
  }) async {
    if (points.isEmpty) return;
    if (points.length == 1) {
      await move(points.first, 14, animate: animate);
      return;
    }
    var minLat = points.first.latitude;
    var maxLat = minLat;
    var minLng = points.first.longitude;
    var maxLng = minLng;
    for (final p in points.skip(1)) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    _lastCenter = ll.LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
    final c = _controller;
    if (c == null || !_styleReady) return;
    _markProgrammaticCamera(animate ? 900 : 500);
    _holdFollow(Duration(milliseconds: animate ? 1500 : 800));
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    final update = CameraUpdate.newLatLngBounds(
      bounds,
      left: padding,
      top: padding,
      right: padding,
      bottom: padding,
    );
    if (animate) {
      await c.animateCamera(update);
    } else {
      await c.moveCamera(update);
    }
  }

  Future<void> syncOverlay(AppMapOverlay overlay) async {
    _queuedOverlay = overlay;
    if (_syncingOverlay) return;
    _syncingOverlay = true;
    try {
      // انتظر أي تحديث سيارة جارٍ قبل مسح الرموز.
      await _driverPoseChain;
      while (_queuedOverlay != null) {
        final next = _queuedOverlay!;
        _queuedOverlay = null;
        await _syncOverlayNow(next);
      }
    } finally {
      _syncingOverlay = false;
    }
    // بعد انتهاء المزامنة فقط — سيارة واحدة عبر الطابور التسلسلي.
    if (_lastDriverPose != null) {
      _displayDriverPose ??= _lastDriverPose;
      _displayDriverHeading = _lastDriverHeading;
      await _applyDriverPoseNow();
    }
    final leftover = _queuedOverlay;
    if (leftover != null) {
      unawaited(syncOverlay(leftover));
    }
  }

  Future<void> _syncOverlayNow(AppMapOverlay overlay) async {
    final c = _controller;
    if (c == null || !_styleReady) return;
    await _ensureImages();

    // امسح رموز التعليق فقط — لا تلمس سيارة السائق (يمنع وميض الأيقونة).
    if (_symbols.isNotEmpty) {
      try {
        await c.removeSymbols(List<Symbol>.from(_symbols));
      } catch (_) {
        for (final s in List<Symbol>.from(_symbols)) {
          try {
            await c.removeSymbol(s);
          } catch (_) {}
        }
      }
      _symbols.clear();
    }

    if (_lines.isNotEmpty) {
      try {
        await c.removeLines(List<Line>.from(_lines));
      } catch (_) {
        for (final line in List<Line>.from(_lines)) {
          try {
            await c.removeLine(line);
          } catch (_) {}
        }
      }
      _lines.clear();
    }

    for (final line in overlay.polylines) {
      if (line.points.length < 2) continue;
      final geometry = line.points
          .map((p) => LatLng(p.latitude, p.longitude))
          .toList();
      if (line.cased) {
        final casing = await c.addLine(
          LineOptions(
            geometry: geometry,
            lineColor: _colorToHex(const Color(MapStyleConfig.routeCasingColor)),
            lineWidth: line.width + 4,
            lineOpacity: 0.95,
            lineJoin: 'round',
          ),
        );
        _lines.add(casing);
      }
      final added = await c.addLine(
        LineOptions(
          geometry: geometry,
          lineColor: _colorToHex(line.color.withValues(alpha: line.alpha)),
          lineWidth: line.width,
          lineOpacity: line.alpha,
          lineJoin: 'round',
        ),
      );
      _lines.add(added);
    }

    // السيارة لا تُضاف هنا أبداً — فقط عبر updateDriverPose (يمنع التكرار).
    for (final m in overlay.markers) {
      final isDriver = m.kind == AppMapMarkerKind.driver ||
          m.kind == AppMapMarkerKind.taxi;
      if (isDriver) {
        _lastDriverPose = m.point;
        if (m.rotation.isFinite) _lastDriverHeading = m.rotation;
        continue;
      }
      final size = switch (m.kind) {
        AppMapMarkerKind.passenger || AppMapMarkerKind.pickup => 1.35,
        AppMapMarkerKind.destination => 1.25,
        AppMapMarkerKind.driver || AppMapMarkerKind.taxi => 1.05,
        AppMapMarkerKind.sos => 1.0,
      };
      final added = await c.addSymbol(
        SymbolOptions(
          geometry: LatLng(m.point.latitude, m.point.longitude),
          iconImage: _iconFor(m.kind),
          iconSize: size,
          iconRotate: m.rotation,
          iconAnchor: m.kind == AppMapMarkerKind.destination ? 'bottom' : 'center',
        ),
      );
      _symbols.add(added);
    }
  }

  String _iconFor(AppMapMarkerKind kind) {
    switch (kind) {
      case AppMapMarkerKind.driver:
      case AppMapMarkerKind.taxi:
        return 'app-driver';
      case AppMapMarkerKind.passenger:
        return 'app-passenger';
      case AppMapMarkerKind.pickup:
        return 'app-pickup';
      case AppMapMarkerKind.destination:
        return 'app-destination';
      case AppMapMarkerKind.sos:
        return 'app-sos';
    }
  }

  Future<void> _ensureImages() async {
    if (_imagesReady) return;
    final c = _controller;
    if (c == null || !_styleReady) return;
    try {
      // نموذج 3D — الحجم السابق (220×220) مع منظور أمامي/خلفي.
      final idle3d = await _assetPng(
        'assets/images/markers/taxi_3d_idle.png',
        fallbackAsset: 'assets/images/markers/driver_taxi.png',
      );
      final rear3d = await _assetPng(
        'assets/images/markers/taxi_3d_rear.png',
        fallbackAsset: 'assets/images/markers/taxi_3d_idle.png',
      );
      await c.addImage('app-driver', idle3d);
      await c.addImage('app-taxi', idle3d);
      await c.addImage('app-driver-rear', rear3d);
      await c.addImage('app-passenger', await _personMarkerPng());
      await c.addImage('app-pickup', await _personMarkerPng());
      await c.addImage('app-destination', await _destinationPinPng());
      await c.addImage('app-sos', await _dotPng(const Color(0xFFF9A825)));
      _imagesReady = true;
      try {
        await c.setSymbolIconAllowOverlap(true);
        await c.setSymbolIconIgnorePlacement(true);
      } catch (_) {}
      // شارات الأماكن كما عدّلناها — بعد أيقونات الرحلة حتى لا تؤخر الظهور.
      try {
        await _registerElegantPoiBadges(c);
      } catch (e) {
        debugPrint('[AppMapController] poi badges: $e');
      }
    } catch (e) {
      debugPrint('[AppMapController] images: $e');
      _imagesReady = false;
    }
  }

  /// يستبدل أيقونات الـ sprite بشارات دائرية أنيقة (تصميم التطبيق).
  static Future<void> _registerElegantPoiBadges(
    MapLibreMapController c,
  ) async {
    const badges = <String, (IconData, Color)>{
      'restaurant': (Icons.restaurant_rounded, Color(0xFFE53935)),
      'cafe': (Icons.local_cafe_rounded, Color(0xFF8D6E63)),
      'fast_food': (Icons.fastfood_rounded, Color(0xFFFF7043)),
      'bar': (Icons.local_bar_rounded, Color(0xFFAB47BC)),
      'beer': (Icons.sports_bar_rounded, Color(0xFFAB47BC)),
      'biergarten': (Icons.sports_bar_rounded, Color(0xFFAB47BC)),
      'pub': (Icons.local_bar_rounded, Color(0xFFAB47BC)),
      'shop': (Icons.storefront_rounded, Color(0xFF5C6BC0)),
      'grocery': (Icons.local_grocery_store_rounded, Color(0xFF66BB6A)),
      'supermarket': (Icons.local_grocery_store_rounded, Color(0xFF66BB6A)),
      'convenience': (Icons.store_rounded, Color(0xFF66BB6A)),
      'mall': (Icons.local_mall_rounded, Color(0xFF5C6BC0)),
      'bakery': (Icons.bakery_dining_rounded, Color(0xFFFFA726)),
      'butcher': (Icons.set_meal_rounded, Color(0xFFEF5350)),
      'alcohol_shop': (Icons.liquor_rounded, Color(0xFF7E57C2)),
      'clothing_store': (Icons.checkroom_rounded, Color(0xFF42A5F5)),
      'clothes': (Icons.checkroom_rounded, Color(0xFF42A5F5)),
      'gift': (Icons.card_giftcard_rounded, Color(0xFFEC407A)),
      'books': (Icons.menu_book_rounded, Color(0xFF5C6BC0)),
      'electronics': (Icons.devices_rounded, Color(0xFF42A5F5)),
      'mobile_phone': (Icons.smartphone_rounded, Color(0xFF42A5F5)),
      'jewelry': (Icons.diamond_rounded, Color(0xFFEC407A)),
      'shoes': (Icons.shopping_bag_rounded, Color(0xFF8D6E63)),
      'optician': (Icons.visibility_rounded, Color(0xFF29B6F6)),
      'bank': (Icons.account_balance_rounded, Color(0xFF42A5F5)),
      'atm': (Icons.atm_rounded, Color(0xFF29B6F6)),
      'hospital': (Icons.local_hospital_rounded, Color(0xFFEF5350)),
      'clinic': (Icons.local_hospital_rounded, Color(0xFFEF5350)),
      'doctors': (Icons.medical_services_rounded, Color(0xFFEF5350)),
      'doctor': (Icons.medical_services_rounded, Color(0xFFEF5350)),
      'dentist': (Icons.medical_services_rounded, Color(0xFF26A69A)),
      'pharmacy': (Icons.local_pharmacy_rounded, Color(0xFF26A69A)),
      'chemist': (Icons.local_pharmacy_rounded, Color(0xFF26A69A)),
      'school': (Icons.school_rounded, Color(0xFF42A5F5)),
      'kindergarten': (Icons.child_care_rounded, Color(0xFF42A5F5)),
      'college': (Icons.account_balance_rounded, Color(0xFF5C6BC0)),
      'university': (Icons.account_balance_rounded, Color(0xFF5C6BC0)),
      'library': (Icons.local_library_rounded, Color(0xFF5C6BC0)),
      'fuel': (Icons.local_gas_station_rounded, Color(0xFF78909C)),
      'charging_station': (Icons.ev_station_rounded, Color(0xFF66BB6A)),
      'parking': (Icons.local_parking_rounded, Color(0xFF5C6BC0)),
      'bicycle_parking': (Icons.pedal_bike_rounded, Color(0xFF5C6BC0)),
      'bicycle_rental': (Icons.pedal_bike_rounded, Color(0xFF26A69A)),
      'lodging': (Icons.hotel_rounded, Color(0xFF26A69A)),
      'hotel': (Icons.hotel_rounded, Color(0xFF26A69A)),
      'guest_house': (Icons.hotel_rounded, Color(0xFF26A69A)),
      'hostel': (Icons.hotel_rounded, Color(0xFF26A69A)),
      'motel': (Icons.hotel_rounded, Color(0xFF26A69A)),
      'bus': (Icons.directions_bus_rounded, Color(0xFF42A5F5)),
      'bus_station': (Icons.directions_bus_rounded, Color(0xFF42A5F5)),
      'railway': (Icons.train_rounded, Color(0xFF5C6BC0)),
      'rail': (Icons.train_rounded, Color(0xFF5C6BC0)),
      'subway': (Icons.subway_rounded, Color(0xFF5C6BC0)),
      'station': (Icons.train_rounded, Color(0xFF5C6BC0)),
      'park': (Icons.park_rounded, Color(0xFF66BB6A)),
      'garden': (Icons.yard_rounded, Color(0xFF66BB6A)),
      'playground': (Icons.toys_rounded, Color(0xFFFFA726)),
      'police': (Icons.local_police_rounded, Color(0xFF5C6BC0)),
      'post': (Icons.local_post_office_rounded, Color(0xFFFFA726)),
      'post_office': (Icons.local_post_office_rounded, Color(0xFFFFA726)),
      'fire_station': (Icons.local_fire_department_rounded, Color(0xFFEF5350)),
      'florist': (Icons.local_florist_rounded, Color(0xFFEC407A)),
      'furniture': (Icons.chair_rounded, Color(0xFF8D6E63)),
      'laundry': (Icons.local_laundry_service_rounded, Color(0xFF42A5F5)),
      'hairdresser': (Icons.content_cut_rounded, Color(0xFFEC407A)),
      'beauty': (Icons.spa_rounded, Color(0xFFEC407A)),
      'ice_cream': (Icons.icecream_rounded, Color(0xFFEC407A)),
      'monument': (Icons.account_balance_rounded, Color(0xFF8D6E63)),
      'memorial': (Icons.account_balance_rounded, Color(0xFF8D6E63)),
      'castle': (Icons.account_balance_rounded, Color(0xFF8D6E63)),
      'museum': (Icons.museum_rounded, Color(0xFF8D6E63)),
      'gallery': (Icons.palette_rounded, Color(0xFF8D6E63)),
      'toilet': (Icons.wc_rounded, Color(0xFF78909C)),
      'toilets': (Icons.wc_rounded, Color(0xFF78909C)),
      'drinking_water': (Icons.water_drop_rounded, Color(0xFF29B6F6)),
      'fountain': (Icons.water_drop_rounded, Color(0xFF29B6F6)),
      'information': (Icons.info_rounded, Color(0xFF42A5F5)),
      'attraction': (Icons.star_rounded, Color(0xFF26A69A)),
      'viewpoint': (Icons.visibility_rounded, Color(0xFF26A69A)),
      'cinema': (Icons.movie_rounded, Color(0xFFAB47BC)),
      'theatre': (Icons.theater_comedy_rounded, Color(0xFFAB47BC)),
      'theater': (Icons.theater_comedy_rounded, Color(0xFFAB47BC)),
      'nightclub': (Icons.music_note_rounded, Color(0xFFAB47BC)),
      'place_of_worship': (Icons.mosque_rounded, Color(0xFF8D6E63)),
      'mosque': (Icons.mosque_rounded, Color(0xFF8D6E63)),
      'church': (Icons.account_balance_rounded, Color(0xFF8D6E63)),
      'airport': (Icons.local_airport_rounded, Color(0xFF42A5F5)),
      'airport_11': (Icons.local_airport_rounded, Color(0xFF42A5F5)),
      'office': (Icons.business_rounded, Color(0xFF5C6BC0)),
      'town_hall': (Icons.account_balance_rounded, Color(0xFF5C6BC0)),
      'community_centre': (Icons.groups_rounded, Color(0xFF5C6BC0)),
      'courthouse': (Icons.gavel_rounded, Color(0xFF5C6BC0)),
      'embassy': (Icons.account_balance_rounded, Color(0xFF5C6BC0)),
      'sports_centre': (Icons.sports_soccer_rounded, Color(0xFF66BB6A)),
      'sports_hall': (Icons.sports_basketball_rounded, Color(0xFF66BB6A)),
      'fitness_centre': (Icons.fitness_center_rounded, Color(0xFF66BB6A)),
      'swimming_pool': (Icons.pool_rounded, Color(0xFF29B6F6)),
      'pitch': (Icons.sports_soccer_rounded, Color(0xFF66BB6A)),
      'stadium': (Icons.stadium_rounded, Color(0xFF66BB6A)),
      'golf': (Icons.golf_course_rounded, Color(0xFF66BB6A)),
      'zoo': (Icons.pets_rounded, Color(0xFFFFA726)),
      'aquarium': (Icons.water_rounded, Color(0xFF29B6F6)),
      'theme_park': (Icons.celebration_rounded, Color(0xFFFF7043)),
      'campsite': (Icons.park_rounded, Color(0xFF66BB6A)),
      'camp_site': (Icons.park_rounded, Color(0xFF66BB6A)),
      'cemetery': (Icons.park_rounded, Color(0xFF78909C)),
      'grave_yard': (Icons.park_rounded, Color(0xFF78909C)),
      'harbor': (Icons.directions_boat_rounded, Color(0xFF29B6F6)),
      'ferry_terminal': (Icons.directions_boat_rounded, Color(0xFF29B6F6)),
      'car': (Icons.directions_car_rounded, Color(0xFF78909C)),
      'car_repair': (Icons.car_repair_rounded, Color(0xFF78909C)),
      'car_rental': (Icons.car_rental_rounded, Color(0xFF5C6BC0)),
      'marketplace': (Icons.storefront_rounded, Color(0xFFFFA726)),
      'default_marker': (Icons.place_rounded, Color(0xFF78909C)),
    };

    // سجّل الافتراضي أولاً حتى لا تختفي كل الأيقونات إن فشل نوع معيّن.
    final ordered = <MapEntry<String, (IconData, Color)>>[
      MapEntry('default_marker', badges['default_marker']!),
      ...badges.entries.where((e) => e.key != 'default_marker'),
    ];

    for (final entry in ordered) {
      try {
        final badge = await _elegantPoiBadgePng(
          icon: entry.value.$1,
          color: entry.value.$2,
        );
        await c.addImage(entry.key, badge);
        await c.addImage('${entry.key}_11', badge);
      } catch (e) {
        debugPrint('[AppMapController] poi badge ${entry.key}: $e');
      }
    }
  }

  static Future<Uint8List> _elegantPoiBadgePng({
    required IconData icon,
    required Color color,
  }) async {
    const size = 112.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);

    canvas.drawCircle(
      center.translate(0, 2.5),
      size * 0.40,
      Paint()
        ..color = Colors.black26
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(center, size * 0.40, Paint()..color = color);
    canvas.drawCircle(
      center,
      size * 0.40,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 48,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset((size - tp.width) / 2, (size - tp.height) / 2 - 1),
    );

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  static Future<Uint8List> _assetPng(
    String asset, {
    String? fallbackAsset,
  }) async {
    Future<Uint8List> load(String path) async {
      final data = await rootBundle.load(path);
      return data.buffer.asUint8List();
    }

    try {
      return await load(asset);
    } catch (_) {
      if (fallbackAsset != null) {
        try {
          return await load(fallbackAsset);
        } catch (_) {}
      }
      return _dotPng(const Color(0xFFFFC107));
    }
  }

  /// أيقونة شخص لموقع الزبون (دائرة كهرمانية + شخص).
  static Future<Uint8List> _personMarkerPng() async {
    const size = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    canvas.drawCircle(
      const Offset(size / 2, size / 2 + 3),
      size * 0.36,
      Paint()
        ..color = Colors.black38
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size * 0.38,
      Paint()..color = const Color(0xFF11215B),
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size * 0.34,
      Paint()..color = const Color(0xFFFFC107),
    );

    const icon = Icons.person_rounded;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 46,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: const Color(0xFF11215B),
      ),
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset((size - tp.width) / 2, (size - tp.height) / 2 - 2),
    );

    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  /// علامة وجهة — دبوس كحلي/ذهبي مع أيقونة مكان (بدل الأحمر السابق).
  static Future<Uint8List> _destinationPinPng() async {
    const w = 88.0;
    const h = 118.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const navy = Color(0xFF11215B);
    const gold = Color(0xFFFFC107);
    const tipY = h - 10;
    const head = Offset(w / 2, 40);

    // ظل الأرض
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(w / 2, tipY + 2),
        width: 30,
        height: 11,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.32),
    );

    // جسم الدبوس (شكل دمعة)
    final pin = Path()
      ..moveTo(head.dx, tipY)
      ..quadraticBezierTo(head.dx - 34, head.dy + 18, head.dx - 30, head.dy)
      ..arcToPoint(
        Offset(head.dx + 30, head.dy),
        radius: const Radius.circular(30),
        clockwise: true,
      )
      ..quadraticBezierTo(head.dx + 34, head.dy + 18, head.dx, tipY)
      ..close();

    canvas.drawPath(
      pin,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawPath(pin, Paint()..color = navy);
    canvas.drawPath(
      pin,
      Paint()
        ..color = gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2,
    );

    // دائرة داخلية ذهبية
    canvas.drawCircle(head, 18, Paint()..color = gold);
    canvas.drawCircle(head, 14.5, Paint()..color = Colors.white);

    // أيقونة مكان
    const icon = Icons.place_rounded;
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 22,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: navy,
      ),
    );
    tp.layout();
    tp.paint(
      canvas,
      Offset(head.dx - tp.width / 2, head.dy - tp.height / 2 - 1),
    );

    final img = await recorder.endRecording().toImage(w.toInt(), h.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  static Future<Uint8List> _dotPng(Color color) async {
    const size = 64.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = const Offset(size / 2, size / 2);
    canvas.drawCircle(
      center,
      size * 0.28,
      Paint()..color = Colors.black26,
    );
    canvas.drawCircle(center, size * 0.26, Paint()..color = color);
    canvas.drawCircle(
      center,
      size * 0.26,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    final img =
        await recorder.endRecording().toImage(size.toInt(), size.toInt());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  }

  static String _colorToHex(Color c) {
    final r = (c.r * 255.0).round().clamp(0, 255);
    final g = (c.g * 255.0).round().clamp(0, 255);
    final b = (c.b * 255.0).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }
}

/// ودجت خريطة MapLibre موحّد.
class AppMapView extends StatefulWidget {
  AppMapView({
    super.key,
    required this.controller,
    required this.initialCenter,
    double? initialZoom,
    this.initialBearing = 0,
    double? initialTilt,
    this.overlay = AppMapOverlay.empty,
    this.onMapReady,
    this.onMapClick,
    this.onUserGesture,
    this.onCameraIdle,
    this.myLocationEnabled = false,
    this.nightMode = false,
    /// يفرض أخذ إيماءات السحب من الـ bottom sheet وغيره (مهم لمنتقي الموقع).
    this.eagerGestureArena = false,
  })  : initialZoom = initialZoom ?? MapStyleConfig.mapDefaultZoom,
        initialTilt = initialTilt ?? MapStyleConfig.mapDefaultTilt;

  final AppMapController controller;
  final ll.LatLng initialCenter;
  final double initialZoom;
  final double initialBearing;
  final double initialTilt;
  final AppMapOverlay overlay;
  final VoidCallback? onMapReady;
  final void Function(ll.LatLng point)? onMapClick;
  final VoidCallback? onUserGesture;
  /// يُستدعى عند استقرار الكاميرا (يشمل التصفح اليدوي والتحرك البرمجي).
  final VoidCallback? onCameraIdle;
  final bool myLocationEnabled;
  final bool nightMode;
  final bool eagerGestureArena;

  @override
  State<AppMapView> createState() => _AppMapViewState();
}

class _AppMapViewState extends State<AppMapView> {
  String get _style =>
      widget.nightMode ? MapStyleConfig.nightStyleUrl : MapStyleConfig.dayStyleUrl;

  @override
  void didUpdateWidget(covariant AppMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.nightMode != widget.nightMode) {
      // إعادة بناء الودجت بمفتاح جديد؛ إعادة ضبط الحالة حتى تُسجَّل الصور من جديد.
      unawaited(widget.controller.setStyleUrl(_style));
      return;
    }
    if (oldWidget.overlay != widget.overlay) {
      unawaited(widget.controller.syncOverlay(widget.overlay));
    }
  }

  @override
  Widget build(BuildContext context) {
    final center = widget.initialCenter;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.controller.noteUserPointer(down: true),
      onPointerUp: (_) => widget.controller.noteUserPointer(down: false),
      onPointerCancel: (_) => widget.controller.noteUserPointer(down: false),
      child: MapLibreMap(
      key: ValueKey('maplibre_${_style}_${widget.nightMode}'),
      styleString: _style,
      initialCameraPosition: CameraPosition(
        target: LatLng(center.latitude, center.longitude),
        zoom: widget.initialZoom,
        bearing: widget.initialBearing,
        tilt: widget.initialTilt,
      ),
      myLocationEnabled: widget.myLocationEnabled,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      trackCameraPosition: true,
      compassEnabled: true,
      rotateGesturesEnabled: true,
      scrollGesturesEnabled: true,
      zoomGesturesEnabled: true,
      tiltGesturesEnabled: true,
      gestureRecognizers: widget.eagerGestureArena
          ? <Factory<OneSequenceGestureRecognizer>>{
              Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
            }
          : null,
      onMapCreated: (c) async {
        await widget.controller.attach(c);
      },
      onStyleLoadedCallback: () async {
        await widget.controller.onStyleLoaded(nightMode: widget.nightMode);
        await widget.controller.syncOverlay(widget.overlay);
        widget.onMapReady?.call();
      },
      onMapClick: (point, latLng) {
        widget.onMapClick?.call(ll.LatLng(latLng.latitude, latLng.longitude));
      },
      onCameraMove: (cam) {
        // كشف مبكر للسحب أثناء الحركة — لا ننتظر idle حتى لا تقفز الكاميرا.
        if (widget.controller.notePossibleUserPan(cam)) {
          widget.onUserGesture?.call();
        }
      },
      onCameraIdle: () {
        final programmatic = widget.controller.consumeProgrammaticCameraIdle;
        if (!programmatic) {
          final panned = widget.controller.syncCameraFromUserIdle();
          // الزوم/الدوران لا يوقفان المتابعة — السحب فقط.
          if (panned) {
            widget.onUserGesture?.call();
          }
        } else {
          widget.controller.pullCameraCenterFromMap();
        }
        widget.onCameraIdle?.call();
      },
      ),
    );
  }
}
