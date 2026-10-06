import 'package:flutter_test/flutter_test.dart';
import 'package:syriataxi/Driver/Home/service/free_meter_engine.dart';

void main() {
  const base = 7000.0;
  const kmPrice = 3500.0;
  const minPrice = 300.0;
  final t0 = DateTime(2026, 1, 1, 12, 0, 0);

  group('Free meter engine', () {
    test('starts at open price', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      );
      m.resetForNewTrip(now: t0);
      expect(m.cost, base);
      expect(m.distanceKm, 0);
      expect(m.isMoving, false);
    });

    test('ignores small GPS jitter while sensor says stopped', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      m.applySegment(
        distanceMeters: 2.5,
        speedMps: 0,
        sampleAt: t0.add(const Duration(milliseconds: 800)),
      );
      expect(m.distanceKm, 0);
      expect(m.cost, base);
      expect(m.isMoving, false);
      expect(m.pendingMeters, 0);
    });

    test('counts km on large segment even if device speed is zero', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      m.applySegment(
        distanceMeters: 50,
        speedMps: 0,
        sampleAt: t0.add(const Duration(seconds: 10)),
      );
      expect(m.cost, base + (50 / 1000.0) * kmPrice);
      expect(m.isMoving, true);
    });

    test('strong movement counts in one segment', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      m.applySegment(
        distanceMeters: 15,
        speedMps: 0,
        sampleAt: t0.add(const Duration(seconds: 2)),
      );
      expect(m.distanceKm, closeTo(0.015, 0.0001));
      expect(m.isMoving, true);
    });

    test('crawl with real speed bills distance', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      m.applySegment(
        distanceMeters: 4,
        speedMps: 2.0, // ≈ 7.2 كم/س
        sampleAt: t0.add(const Duration(seconds: 2)),
      );
      expect(m.distanceKm, closeTo(0.004, 0.0001));
      expect(m.isMoving, true);
    });

    test('tiny stopped segments do not accumulate as fake km', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      for (var i = 1; i <= 8; i++) {
        m.applySegment(
          distanceMeters: 0.8,
          speedMps: 0,
          sampleAt: t0.add(Duration(milliseconds: 400 * i)),
        );
      }
      expect(m.distanceKm, 0);
      expect(m.pendingMeters, 0);
      expect(m.isMoving, false);
      expect(m.cost, base);
    });

    test('waiting starts after brief grace once movement stops', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      m.applySegment(
        distanceMeters: 120,
        speedMps: 0,
        sampleAt: t0.add(const Duration(seconds: 20)),
      );

      // المقطع يُحدّ بـ maxSegmentMeters لتقليل اختلاف الأجهزة
      const billedM = FreeMeterEngine.maxSegmentMeters;
      for (var i = 1; i <= 3; i++) {
        m.tickWaitingSecond(now: t0.add(Duration(seconds: 20 + i)));
      }
      expect(m.cost, base + (billedM / 1000.0) * kmPrice);

      for (var i = 4; i <= 63; i++) {
        m.tickWaitingSecond(now: t0.add(Duration(seconds: 20 + i)));
      }
      expect(m.cost, base + (billedM / 1000.0) * kmPrice + minPrice);
    });

    test('rejects unrealistic GPS jump', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      m.applySegment(
        distanceMeters: 200,
        speedMps: 0,
        sampleAt: t0.add(const Duration(seconds: 1)),
      );
      expect(m.distanceKm, 0);
      expect(m.cost, base);
    });

    test('still accepts clear distance on weaker GPS accuracy', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      expect(FreeMeterEngine.accuracyOkForDistance(45), isTrue);
      m.applySegment(
        distanceMeters: 20,
        speedMps: 0,
        sampleAt: t0.add(const Duration(seconds: 3)),
        accuracyMeters: 40,
      );
      expect(m.distanceKm, closeTo(0.02, 0.0001));
    });

    test('parse pricing from API shape', () {
      final p = FreeMeterEngine.parsePricingResponse({
        'state': true,
        'data': {
          'openPrice': 5000,
          'kmPrice': 4000,
          'timePrice': 250,
        },
      });
      expect(p, isNotNull);
      expect(p!['openPrice'], 5000);
      expect(p['kmPrice'], 4000);
      expect(p['timePrice'], 250);
    });

    test('catchUpWaitingTicks bills idle gap while app was backgrounded', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      m.applySegment(
        distanceMeters: 40,
        speedMps: 0,
        sampleAt: t0.add(const Duration(seconds: 10)),
      );

      final backgroundAt = t0.add(const Duration(seconds: 10 + 4));
      m.catchUpWaitingTicks(
        now: backgroundAt.add(const Duration(seconds: 120)),
      );
      expect(m.billedWaitingMinutes, 2);
      expect(m.cost, closeTo(base + (40 / 1000.0) * kmPrice + minPrice * 2, 0.001));
    });

    test('catchUpWaitingTicks bills idle time after background gap', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      final stoppedAt = t0.add(const Duration(seconds: 10));
      m.applySegment(
        distanceMeters: 40,
        speedMps: 0,
        sampleAt: stoppedAt,
      );

      m.catchUpWaitingTicks(
        now: stoppedAt.add(const Duration(seconds: 10 + 4 + 60)),
      );
      expect(m.cost, closeTo(base + (40 / 1000.0) * kmPrice + minPrice, 0.001));
    });

    test('one waiting tick per second — no double billing', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      m.applySegment(
        distanceMeters: 40,
        speedMps: 0,
        sampleAt: t0.add(const Duration(seconds: 10)),
      );

      for (var s = 1; s <= 60; s++) {
        m.tickWaitingSecond(
          now: t0.add(Duration(seconds: 10 + 4 + s)),
        );
      }
      expect(m.billedWaitingMinutes, 1);
      expect(m.waitingSeconds, 0);
      expect(m.cost, closeTo(base + (40 / 1000.0) * kmPrice + minPrice, 0.001));

      m.catchUpWaitingTicks(
        now: t0.add(Duration(seconds: 10 + 4 + 60 + 1)),
      );
      expect(m.billedWaitingMinutes, 1);
      expect(m.waitingSeconds, 1);
      expect(m.cost, closeTo(base + (40 / 1000.0) * kmPrice + minPrice, 0.001));
    });

    test('waiting seconds accumulate across stop-move-stop', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      for (var s = 1; s <= 20; s++) {
        m.tickWaitingSecond(now: t0.add(Duration(seconds: 4 + s)));
      }
      expect(m.waitingSeconds, 20);
      expect(m.billedWaitingMinutes, 0);

      final moveAt = t0.add(const Duration(seconds: 4 + 20 + 1));
      m.applySegment(
        distanceMeters: 40,
        speedMps: 5,
        sampleAt: moveAt,
      );
      expect(m.isMoving, true);
      expect(m.waitingSeconds, 20);

      for (var s = 1; s <= 40; s++) {
        m.tickWaitingSecond(now: moveAt.add(Duration(seconds: 4 + s)));
      }
      expect(m.billedWaitingMinutes, 1);
      expect(m.waitingSeconds, 0);
      expect(
        m.cost,
        closeTo(base + (40 / 1000.0) * kmPrice + minPrice, 0.001),
      );
    });

    test('totalWaitingSeconds matches display at minute boundary', () {
      final m = FreeMeterEngine(
        openPrice: base,
        kmPrice: kmPrice,
        timePrice: minPrice,
      )..resetForNewTrip(now: t0);

      m.applySegment(
        distanceMeters: 40,
        speedMps: 0,
        sampleAt: t0.add(const Duration(seconds: 10)),
      );
      for (var s = 1; s <= 59; s++) {
        m.tickWaitingSecond(now: t0.add(Duration(seconds: 10 + 4 + s)));
      }
      expect(m.totalWaitingSeconds, 59);
      expect(m.billedWaitingMinutes, 0);
      expect(m.cost, base + (40 / 1000.0) * kmPrice);

      m.tickWaitingSecond(now: t0.add(const Duration(seconds: 10 + 4 + 60)));
      expect(m.totalWaitingSeconds, 60);
      expect(m.billedWaitingMinutes, 1);
      expect(m.cost, closeTo(base + (40 / 1000.0) * kmPrice + minPrice, 0.001));
    });
  });
}
