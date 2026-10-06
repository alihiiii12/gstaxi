import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// مقاسات آمنة لـ iPad / الشاشات العريضة.
abstract final class TabletLayout {
  TabletLayout._();

  static bool isTablet(BuildContext context) =>
      MediaQuery.sizeOf(context).shortestSide >= 600;

  /// عرض القائمة الجانبية — لا يتجاوز 360 على الأجهزة اللوحية.
  static double drawerWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return math.min(w * 0.65, 360);
  }

  /// أقصى عرض لمحتوى النماذج/البطاقات على iPad.
  static double contentMaxWidth(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 700) return w;
    return 560;
  }
}
