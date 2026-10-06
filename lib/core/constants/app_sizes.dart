import 'package:flutter/widgets.dart';

class AppSizes {
  AppSizes._();

  static double _screenW = 375;
  static double _screenH = 812;
  static bool _ready = false;

  /// 🎨 التصميم المرجعي
  static const double _designW = 375;
  static const double _designH = 812;

  /// 🛡 حدود ذكية (نسبة سماح)
  static const double _minScale = 0.85; // -15%
  static const double _maxScale = 1.20; // +20%

  static bool get isReady => _ready;

  static void init(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width <= 0 || size.height <= 0) return;
    _screenW = size.width;
    _screenH = size.height;
    _ready = true;
  }

  // =========================
  // 🎯 CORE ENGINE
  // =========================

  static double _clamp(double value, double base) {
    return value.clamp(
      base * _minScale,
      base * _maxScale,
    );
  }

  /// px من التصميم → عرض الشاشة
  static double w(double px) {
    final scaled = _screenW * (px / _designW);
    return _clamp(scaled, px);
  }

  /// px من التصميم → ارتفاع الشاشة
  static double h(double px) {
    final scaled = _screenH * (px / _designH);
    return _clamp(scaled, px);
  }

  /// خط ذكي (متوازن)
  static double sp(double px) {
    final scaleW = _screenW / _designW;
    final scaleH = _screenH / _designH;
    final scaled = px * ((scaleW + scaleH) / 2);
    return _clamp(scaled, px);
  }

  // =========================
  // HELPERS
  // =========================
  static double get screenWidth => _screenW;
  static double get screenHeight => _screenH;
}
