import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// مستويات أداء الخريطة — أجهزة ضعيفة vs قوية.
enum MapPerfTier { low, high }

/// كشف بسيط بدون حزم إضافية (أنوية المعالج + دقة الشاشة).
abstract final class MapPerformanceProfile {
  static MapPerfTier? _cached;

  static MapPerfTier get tier => _cached ??= _detect();

  static bool get isLowEnd => tier == MapPerfTier.low;

  static MapPerfTier _detect() {
    if (kIsWeb) return MapPerfTier.high;

    var cores = 8;
    try {
      cores = Platform.numberOfProcessors;
    } catch (_) {}

    var pixels = 0.0;
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        final s = views.first.physicalSize;
        if (s.width.isFinite && s.height.isFinite) {
          pixels = s.width * s.height;
        }
      }
    } catch (_) {}

    // أجهزة ضعيفة/متوسطة: ≤4 أنوية، أو 6 أنوية مع شاشة كثيفة جداً.
    if (cores <= 4) return MapPerfTier.low;
    if (cores <= 6 && pixels >= 2.8e6) return MapPerfTier.low;
    return MapPerfTier.high;
  }

  /// للاختبارات فقط.
  @visibleForTesting
  static void debugOverride(MapPerfTier? tier) => _cached = tier;
}
