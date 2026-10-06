import 'package:geolocator/geolocator.dart';

/// خوارزمية العداد الحر (مطابقة لوحة التحكم):
/// - عند البدء: سعر الفتح
/// - أثناء الحركة: مسافة × سعر الكيلو (بالمتر فور الحركة)
/// - أثناء التوقف: كل 60 ثانية → سعر الدقيقة
class FreeMeterEngine {
  FreeMeterEngine({
    required this.openPrice,
    required this.kmPrice,
    required this.timePrice,
  });

  final double openPrice;
  final double kmPrice;
  final double timePrice;

  /// أقل إزاحة تُحتسب كمسافة — أعلى من اهتزاز GPS عند التوقف التام.
  static const double movementMinMeters = 6.0;

  /// قفزة واضحة تُعدّ حركة مباشرة (حتى إن أعطى الجهاز speed=0 أحياناً).
  static const double strongMovementMeters = 14.0;

  /// مسافة كافية لاعتبارها «قيادة» تُوقف عدّ زمن الوقوف.
  static const double movementPauseWaitingMeters = 10.0;

  /// زحف بطيء مقبول فقط مع سرعة حقيقية (اختناق مروري).
  static const double crawlMinMeters = 3.0;

  /// تحت هذا الحد نعتبر السيارة واقفة — GPS المتوقف غالباً يُظهر 0–2 كم/س كذباً.
  static const double minMovingSpeedKph = 4.5;

  /// سرعة واضحة لمركبة تُوقف عدّ الوقوف.
  static const double drivingSpeedKph = 6.0;

  /// أقصى سرعة معقولة لسيارة في المدينة (~144 كم/س) — فوقها قفزة GPS تُرفض.
  static const double maxPlausibleSpeedMps = 40.0;

  /// أقصى مسافة تُحسب في مقطع واحد (يمنع تضخيم الكيلومترات بين الأجهزة).
  static const double maxSegmentMeters = 100.0;

  /// بعد آخر حركة نمنح GPS مهلة قصيرة قبل أن نبدأ عدّ زمن الوقوف.
  static const int stopGraceSeconds = 4;

  /// دقة GPS مقبولة لاحتساب المسافة (أجهزة ضعيفة غالباً 25–45م).
  static const double maxAccuracyForDistanceM = 45.0;

  /// دقة «جيدة» — نقبل عتبة movementMinMeters.
  static const double goodAccuracyM = 20.0;

  static bool hasUsablePricing({
    required double kmPrice,
    required double timePrice,
  }) =>
      kmPrice > 0 && timePrice > 0;

  /// يقبل دقة حتى [maxAccuracyForDistanceM]، ومع الدقة الضعيفة يطلب مسافة أكبر قليلاً.
  static bool accuracyOkForDistance(double accuracyMeters) {
    if (!accuracyMeters.isFinite || accuracyMeters <= 0) return true;
    return accuracyMeters <= maxAccuracyForDistanceM;
  }

  /// الحد الأدنى للمقطع حسب دقة الجهاز (يقلل اختلاف الأجهزة الضعيفة).
  static double minMetersForAccuracy(double accuracyMeters) {
    if (!accuracyMeters.isFinite || accuracyMeters <= 0) {
      return movementMinMeters;
    }
    if (accuracyMeters <= goodAccuracyM) return movementMinMeters;
    // دقة ضعيفة: اطلب مسافة أوضح — لا تحتسب اهتزاز الدقة السيئة.
    return (accuracyMeters * 0.45).clamp(movementMinMeters, 22.0);
  }

  static double? readPrice(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final raw = map[k];
      if (raw == null) continue;
      final v = double.tryParse(raw.toString());
      if (v != null && v >= 0) return v;
    }
    return null;
  }

  static Map<String, double>? parsePricingResponse(Map<String, dynamic> body) {
    final ok = body['state'] == true ||
        body['success'] == true ||
        body['status'] == true;
    if (!ok) return null;

    final raw = body['data'];
    if (raw is! Map) return null;
    final d = Map<String, dynamic>.from(raw);

    final open = readPrice(d, ['openPrice', 'open_price', 'freeOpenPrice']);
    final km = readPrice(d, [
      'kmPrice',
      'KMPrice',
      'km_price',
      'freeKMPrice',
      'free_km_price',
    ]);
    final time = readPrice(d, [
      'timePrice',
      'time_price',
      'freeTimePrice',
      'free_time_price',
    ]);
    if (open == null || km == null || time == null) return null;
    return {'openPrice': open, 'kmPrice': km, 'timePrice': time};
  }

  double cost = 0;
  double distanceKm = 0;
  int waitingSeconds = 0;
  int billedWaitingMinutes = 0;
  bool isMoving = false;
  DateTime? startedAt;
  DateTime? lastSampleAt;
  DateTime? lastMovementAt;
  DateTime? lastWaitingTickAt;

  /// تجميع مسافات صغيرة جداً (اهتزاز/تقطيع GPS) حتى تصل لعتبة الاحتساب.
  double pendingMeters = 0;

  /// الجهاز أعطى سرعة قيادة حقيقية من قبل — نثق بسرعته (Doppler) بدل المسافة/الزمن.
  bool sensorSpeedTrusted = false;

  /// أقل فاصل بين عينتين لحساب سرعة من المسافة — العينات المتقاربة تضخّم اهتزاز GPS.
  static const double minSecsForComputedSpeed = 0.8;

  int get totalWaitingSeconds => billedWaitingMinutes * 60 + waitingSeconds;

  void resetForNewTrip({DateTime? now}) {
    final current = now ?? DateTime.now();
    cost = openPrice;
    distanceKm = 0;
    waitingSeconds = 0;
    billedWaitingMinutes = 0;
    isMoving = false;
    pendingMeters = 0;
    sensorSpeedTrusted = false;
    startedAt = current;
    lastSampleAt = current;
    // null = واقف من البداية → يُحسب الوقوف فوراً من أول ثانية.
    lastMovementAt = null;
    lastWaitingTickAt = current;
  }

  void catchUpWaitingTicks({DateTime? now}) {
    final current = now ?? DateTime.now();
    final anchor = lastWaitingTickAt ?? lastSampleAt ?? startedAt;
    if (anchor == null) return;

    if (isCurrentlyMoving(now: current)) {
      lastWaitingTickAt = current;
      return;
    }

    final gap = current.difference(anchor).inSeconds;
    if (gap <= 0) return;

    for (var i = 1; i <= gap; i++) {
      tickWaitingSecond(now: anchor.add(Duration(seconds: i)));
    }
  }

  void tickWaitingSecond({DateTime? now}) {
    final current = now ?? DateTime.now();
    isMoving = isCurrentlyMoving(now: current);
    if (isMoving) {
      // أثناء الحركة: يُوقف عدّ زمن الوقوف (الثواني المحفوظة تبقى).
      lastWaitingTickAt = current;
      return;
    }

    // مهلة قصيرة فقط بعد آخر حركة حقيقية — لا تمنع العدّ عند البدء واقفاً.
    final idleSince = lastMovementAt;
    if (idleSince != null &&
        current.difference(idleSince).inSeconds < stopGraceSeconds) {
      lastWaitingTickAt = current;
      return;
    }

    waitingSeconds++;
    if (waitingSeconds == 60) {
      cost += timePrice;
      waitingSeconds = 0;
      billedWaitingMinutes++;
    }
    lastWaitingTickAt = current;
  }

  bool isCurrentlyMoving({DateTime? now}) {
    final current = now ?? DateTime.now();
    final lastMove = lastMovementAt;
    // لم تُسجَّل حركة بعد = واقف منذ التشغيل.
    if (lastMove == null) return false;
    return current.difference(lastMove).inSeconds < stopGraceSeconds;
  }

  /// يرفض قفزات GPS غير المعقولة ويحدّ أقصى مسافة للمقطع.
  double? sanitizeSegmentMeters({
    required double distanceMeters,
    required DateTime sampleAt,
  }) {
    if (!distanceMeters.isFinite || distanceMeters <= 0) return null;

    final prev = lastSampleAt;
    if (prev != null) {
      final secs = sampleAt.difference(prev).inMilliseconds / 1000.0;
      if (secs > 0.15 && secs <= 60) {
        final maxBySpeed = maxPlausibleSpeedMps * secs;
        if (distanceMeters > maxBySpeed) {
          // قفزة GPS — لا تُحسب كمسافة.
          return null;
        }
      } else if (secs > 60) {
        // فجوة طويلة: نحدّ المسافة حتى لا تُضخَّم بعد العودة من الخلفية.
        return distanceMeters.clamp(0, maxSegmentMeters).toDouble();
      }
    }

    if (distanceMeters > maxSegmentMeters) {
      return maxSegmentMeters;
    }
    return distanceMeters;
  }

  double? _effectiveSpeedMps({
    required double distanceMeters,
    required DateTime sampleAt,
    double? sensorSpeedMps,
  }) {
    double? computed;
    final prev = lastSampleAt;
    if (prev != null) {
      final secs = sampleAt.difference(prev).inMilliseconds / 1000.0;
      if (secs >= minSecsForComputedSpeed && secs <= 30) {
        computed = distanceMeters / secs;
      }
    }

    final sensorOk =
        sensorSpeedMps != null && sensorSpeedMps.isFinite && sensorSpeedMps >= 0;

    if (sensorOk && sensorSpeedTrusted) return sensorSpeedMps;
    if (sensorOk && computed != null) {
      return sensorSpeedMps > computed ? sensorSpeedMps : computed;
    }
    if (sensorOk) return sensorSpeedMps;
    return computed;
  }

  bool _segmentRepresentsMovement({
    required double distanceMeters,
    required DateTime sampleAt,
    double? speedMps,
    double minMeters = movementMinMeters,
    double strongMeters = strongMovementMeters,
  }) {
    final eff = _effectiveSpeedMps(
      distanceMeters: distanceMeters,
      sampleAt: sampleAt,
      sensorSpeedMps: speedMps,
    );
    if (eff != null && eff > maxPlausibleSpeedMps) return false;

    final speedKph = eff == null ? -1.0 : eff * 3.6;
    final sensorSaysStopped =
        speedMps != null && speedMps.isFinite && speedMps >= 0 && speedMps * 3.6 < minMovingSpeedKph;
    final speedSaysMoving = speedKph >= minMovingSpeedKph;

    // سرعة حقيقية + إزاحة بسيطة = حركة (زحمة / زحف).
    if (speedSaysMoving && distanceMeters >= crawlMinMeters) return true;

    // المستشعر يقول واقف: لا تحتسب إلا قفزة كبيرة جداً (ليست اهتزازاً).
    if (sensorSaysStopped) {
      return distanceMeters >= movementPauseWaitingMeters;
    }

    // مسافة قوية بدون سرعة موثوقة.
    if (distanceMeters >= strongMeters) return true;

    // مسافة متوسطة فقط إن وُجدت سرعة محسوبة فوق العتبة — لا نثق بالمتر وحده.
    if (distanceMeters >= minMeters && speedSaysMoving) return true;

    return false;
  }

  void _billDistance(double meters) {
    final km = meters / 1000.0;
    cost += km * kmPrice;
    distanceKm += km;
    pendingMeters = 0;
  }

  /// حركة كافية لإيقاف عدّ الوقوف (ليست اهتزاز GPS).
  bool _countsAsDrivingMovement({
    required double distanceMeters,
    required DateTime sampleAt,
    double? speedMps,
  }) {
    if (distanceMeters >= movementPauseWaitingMeters) return true;
    if (distanceMeters >= strongMovementMeters) return true;
    final eff = _effectiveSpeedMps(
      distanceMeters: distanceMeters,
      sampleAt: sampleAt,
      sensorSpeedMps: speedMps,
    );
    final speedKph = (eff ?? 0) * 3.6;
    // سرعة مركبة واضحة — لا اهتزاز ثابت عند التوقف.
    return speedKph >= drivingSpeedKph && distanceMeters >= crawlMinMeters;
  }

  void _markDriving(DateTime current) {
    isMoving = true;
    lastMovementAt = current;
    // لا نُصفّر waitingSeconds هنا — تبقى الثواني متراكمة عند العودة للتوقف.
    lastWaitingTickAt = current;
  }

  void applySegment({
    required double distanceMeters,
    double? speedMps,
    DateTime? sampleAt,
    double accuracyMeters = 0,
  }) {
    final current = sampleAt ?? DateTime.now();
    final cleaned = sanitizeSegmentMeters(
      distanceMeters: distanceMeters,
      sampleAt: current,
    );
    if (cleaned == null) {
      // قفزة مرفوضة: نحدّث زمن العينة فقط دون مسافة.
      lastSampleAt = current;
      isMoving = isCurrentlyMoving(now: current);
      return;
    }

    if (speedMps != null &&
        speedMps.isFinite &&
        speedMps * 3.6 >= drivingSpeedKph) {
      sensorSpeedTrusted = true;
    }

    final sensorSaysStopped = speedMps != null &&
        speedMps.isFinite &&
        speedMps >= 0 &&
        speedMps * 3.6 < minMovingSpeedKph;

    // مع دقة ضعيفة ينجرف الموقع أمتاراً عديدة والسيارة واقفة.
    final acc = (accuracyMeters.isFinite && accuracyMeters > 0)
        ? accuracyMeters
        : 0.0;
    final stoppedJumpMeters =
        acc > movementPauseWaitingMeters ? acc : movementPauseWaitingMeters;

    // واقف حسب مستشعر موثوق: لا مسافة إطلاقاً — كل الإزاحة انجراف GPS.
    // واقف حسب مستشعر غير مؤكد: لا تحتسب إلا قفزة أكبر من دقة الجهاز.
    if (sensorSaysStopped &&
        (sensorSpeedTrusted || cleaned < stoppedJumpMeters)) {
      pendingMeters = 0;
      lastSampleAt = current;
      isMoving = isCurrentlyMoving(now: current);
      return;
    }

    final minForDevice = minMetersForAccuracy(accuracyMeters);
    final strongForDevice =
        acc > strongMovementMeters ? acc : strongMovementMeters;

    if (_segmentRepresentsMovement(
      distanceMeters: cleaned,
      speedMps: speedMps,
      sampleAt: current,
      minMeters: minForDevice,
      strongMeters: strongForDevice,
    )) {
      final total = cleaned + pendingMeters;
      _billDistance(total);
      // الحركة الواضحة فقط توقف عدّ الوقوف — اهتزاز GPS لا يفعل.
      if (_countsAsDrivingMovement(
        distanceMeters: total,
        sampleAt: current,
        speedMps: speedMps,
      )) {
        _markDriving(current);
      } else {
        isMoving = isCurrentlyMoving(now: current);
      }
    } else if (cleaned >= 2.5) {
      // تجميع الزحف الحقيقي فقط — لا نكدّس اهتزاز دون نصف المتر.
      pendingMeters += cleaned;
      if (pendingMeters >= minForDevice) {
        final total = pendingMeters;
        // لا تُفوتر التجميع إلا إذا أصبح يمثل حركة حقيقية.
        if (_segmentRepresentsMovement(
          distanceMeters: total,
          speedMps: speedMps,
          sampleAt: current,
          minMeters: minForDevice,
          strongMeters: strongForDevice,
        )) {
          _billDistance(total);
          if (_countsAsDrivingMovement(
            distanceMeters: total,
            sampleAt: current,
            speedMps: speedMps,
          )) {
            _markDriving(current);
          } else {
            isMoving = isCurrentlyMoving(now: current);
          }
        } else {
          // تجميع ضوضاء — صفّره بدل فوترة كيلومترات وهمية.
          pendingMeters = 0;
          isMoving = isCurrentlyMoving(now: current);
        }
      } else {
        isMoving = isCurrentlyMoving(now: current);
      }
    } else {
      isMoving = isCurrentlyMoving(now: current);
    }
    lastSampleAt = current;
  }

  static double? segmentMeters(Position? from, Position to) {
    if (from == null) return null;
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }
}
