import 'package:flutter/material.dart';

import '../constants/app_images.dart';

/// شعار GS Taxi — يُستخدم بدل FlutterLogo في كل الشاشات.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.width,
    this.height,
    this.size,
    this.fit = BoxFit.contain,
    this.heroTag,
  });

  final double? width;
  final double? height;

  /// اختصار: يضبط العرض والارتفاع معاً (مربّع تقريباً).
  final double? size;
  final BoxFit fit;
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final w = width ?? size;
    final h = height ?? size;

    final Widget picture = Image.asset(
      AppImages.logo,
      fit: fit,
      filterQuality: FilterQuality.high,
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: w ?? 80,
          height: h ?? 48,
          child: const Center(
            child: Text(
              'GS Taxi',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Color(0xFF11215B),
              ),
            ),
          ),
        );
      },
    );

    // FittedBox يجعل الشعار يتمدّد مع المستطيل المتحرّك أثناء طيران Hero،
    // وبدونه يقفز الشعار إلى حجمه النهائي في أول إطار.
    Widget image = SizedBox(
      width: w,
      height: h,
      child: FittedBox(fit: fit, child: picture),
    );

    if (heroTag != null) {
      image = Hero(
        tag: heroTag!,
        createRectTween: (begin, end) => _CurvedRectTween(
          begin: begin,
          end: end,
          curve: Curves.easeInOutCubic,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: image,
        ),
      );
    }

    return image;
  }
}

/// يمنح طيران Hero تسارعاً وتباطؤاً بدل الحركة الخطّية.
class _CurvedRectTween extends RectTween {
  _CurvedRectTween({super.begin, super.end, required this.curve});

  final Curve curve;

  @override
  Rect? lerp(double t) => super.lerp(curve.transform(t.clamp(0, 1)));
}
