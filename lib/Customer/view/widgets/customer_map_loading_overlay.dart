import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_images.dart';
import '../../../core/theme/app_text_style.dart';
import 'customer_ui_theme.dart';

/// طبقة تحميل الخريطة/التطبيق — تصميم كهرماني/كحلي (مو رادار البحث).
class CustomerMapLoadingOverlay extends StatefulWidget {
  const CustomerMapLoadingOverlay({
    super.key,
    this.message = 'جاري تجهيز الخريطة…',
  });

  final String message;

  @override
  State<CustomerMapLoadingOverlay> createState() =>
      _CustomerMapLoadingOverlayState();
}

class _CustomerMapLoadingOverlayState extends State<CustomerMapLoadingOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                CustomerUiTheme.navy.withValues(alpha: 0.92),
                const Color(0xFF0A1638),
                CustomerUiTheme.navy.withValues(alpha: 0.96),
              ],
            ),
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 168,
                  height: 168,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: _AmberBreathPainter(t: _controller.value),
                        child: child,
                      );
                    },
                    child: Center(
                      child: Container(
                        width: 108,
                        height: 108,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withValues(alpha: 0.96),
                          boxShadow: [
                            BoxShadow(
                              color: CustomerUiTheme.amber.withValues(alpha: 0.35),
                              blurRadius: 28,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Image(
                          image: AssetImage(AppImages.logo),
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  widget.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFFF8E7),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'لحظة ونفتح لك الطريق',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: Colors.white.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AmberBreathPainter extends CustomPainter {
  _AmberBreathPainter({required this.t});

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..isAntiAlias = true;

    for (var i = 0; i < 2; i++) {
      final p = (t + i * 0.5) % 1.0;
      final r = 42 + p * 38;
      paint.color = CustomerUiTheme.amber.withValues(alpha: (1 - p) * 0.55);
      canvas.drawCircle(c, r, paint);
    }

    // نقطة ضوء خفيفة تدور ببطء حول اللوغو.
    final angle = t * 2 * math.pi;
    final orbit = Offset(
      c.dx + math.cos(angle) * 58,
      c.dy + math.sin(angle) * 58,
    );
    canvas.drawCircle(
      orbit,
      3.2,
      Paint()
        ..color = CustomerUiTheme.amber.withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  @override
  bool shouldRepaint(covariant _AmberBreathPainter oldDelegate) =>
      oldDelegate.t != t;
}
