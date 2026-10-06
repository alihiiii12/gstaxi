import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_images.dart';
import '../../../core/theme/app_text_style.dart';
import 'customer_ui_theme.dart';

/// ألوان رادار البحث — نفس هوية التطبيق (كهرماني + كحلي).
abstract final class SearchingDriverRadarColors {
  static const Color backgroundTop = Color(0xFF0A1638);
  static const Color backgroundBottom = CustomerUiTheme.navy;
  static const Color ring = CustomerUiTheme.amber;
  static const Color disc = Color(0xFF1A2F6E);
  static const Color sweep = Color(0xFFFFE082);
  static const Color title = Color(0xFFFFF8E7);
  static const Color subtitle = Color(0xFFC5CBD8);
}

/// محتوى رادار البحث: حلقات نابضة + عقرب + لوغو + نصوص.
/// بدون AppBar / أزرار / تمرير — يُعرض كشاشة كاملة.
class CustomerSearchingDriverRadarBody extends StatefulWidget {
  const CustomerSearchingDriverRadarBody({
    super.key,
    this.title = 'جاري البحث عن سائق...',
    this.subtitle = 'عم ندور على أقرب سائق لك',
    this.error,
    this.onCancelSearch,
    this.cancelling = false,
    this.progress,
    this.noDriverFound = false,
    this.onRetry,
    this.onBack,
  });

  final String title;
  final String subtitle;
  final String? error;
  final VoidCallback? onCancelSearch;
  final bool cancelling;

  /// تقدّم مهلة البحث (0..1) — null لإخفاء الشريط.
  final double? progress;

  /// انتهت المهلة دون سائق: يتوقف الرادار وتظهر «إعادة المحاولة».
  final bool noDriverFound;
  final VoidCallback? onRetry;
  final VoidCallback? onBack;

  @override
  State<CustomerSearchingDriverRadarBody> createState() =>
      _CustomerSearchingDriverRadarBodyState();
}

class _CustomerSearchingDriverRadarBodyState
    extends State<CustomerSearchingDriverRadarBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );
    if (!widget.noDriverFound) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant CustomerSearchingDriverRadarBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.noDriverFound && _controller.isAnimating) {
      _controller.stop();
    } else if (!widget.noDriverFound && !_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: SearchingDriverRadarColors.backgroundBottom,
      ),
      child: Material(
        color: SearchingDriverRadarColors.backgroundBottom,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                SearchingDriverRadarColors.backgroundTop,
                SearchingDriverRadarColors.backgroundBottom,
                Color(0xFF0C1840),
              ],
              stops: [0.0, 0.55, 1.0],
            ),
          ),
          child: SafeArea(
            child: SizedBox.expand(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 240,
                    height: 240,
                    child: AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        return CustomPaint(
                          painter: SearchingDriverRadarPainter(
                            t: _controller.value,
                          ),
                          child: child,
                        );
                      },
                      child: Center(
                        child: Container(
                          width: 96,
                          height: 96,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.96),
                            boxShadow: [
                              BoxShadow(
                                color: CustomerUiTheme.amber
                                    .withValues(alpha: 0.32),
                                blurRadius: 22,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const ClipOval(
                            child: Image(
                              image: AssetImage(AppImages.logo),
                              fit: BoxFit.contain,
                              filterQuality: FilterQuality.high,
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: SearchingDriverRadarColors.title,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      widget.subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: SearchingDriverRadarColors.subtitle,
                        height: 1.45,
                      ),
                    ),
                  ),
                  if (widget.progress != null && !widget.noDriverFound) ...[
                    const SizedBox(height: 18),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 64),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: widget.progress!.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: 0.12),
                          color: SearchingDriverRadarColors.ring,
                        ),
                      ),
                    ),
                  ],
                  if (widget.error != null &&
                      widget.error!.trim().isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        widget.error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Colors.red.shade200,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                  if (widget.noDriverFound) ...[
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: widget.onRetry == null
                              ? null
                              : () {
                                  HapticFeedback.mediumImpact();
                                  widget.onRetry!.call();
                                },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text(
                            'إعادة المحاولة',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: SearchingDriverRadarColors.ring,
                            foregroundColor: CustomerUiTheme.navy,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: widget.onBack,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SearchingDriverRadarColors.title,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1.4,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'رجوع',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (widget.onCancelSearch != null && !widget.noDriverFound) ...[
                    const SizedBox(height: 28),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: widget.cancelling
                              ? null
                              : () {
                                  HapticFeedback.mediumImpact();
                                  widget.onCancelSearch?.call();
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: SearchingDriverRadarColors.title,
                            disabledForegroundColor:
                                SearchingDriverRadarColors.title
                                    .withValues(alpha: 0.5),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.35),
                              width: 1.4,
                            ),
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.08),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: widget.cancelling
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: SearchingDriverRadarColors.title,
                                  ),
                                )
                              : const Text(
                                  'إلغاء البحث',
                                  style: TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// رادار مسطح 2D: 3 حلقات متوسّعة + قرص داخلي + عقرب دوار.
class SearchingDriverRadarPainter extends CustomPainter {
  SearchingDriverRadarPainter({required this.t});

  /// 0.0 → 1.0 لكل دورة (ثانيتان).
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final discPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = SearchingDriverRadarColors.disc.withValues(alpha: 0.55);
    canvas.drawCircle(center, 50, discPaint);

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..isAntiAlias = true;

    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1.0;
      final radius = 40 + p * 80;
      ringPaint.color =
          SearchingDriverRadarColors.ring.withValues(alpha: (1 - p) * 0.95);
      canvas.drawCircle(center, radius, ringPaint);
    }

    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = SearchingDriverRadarColors.sweep.withValues(alpha: 0.85);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    // Flutter: زاوية موجبة = مع عقارب الساعة.
    canvas.rotate(t * 2 * math.pi);
    canvas.drawLine(Offset.zero, const Offset(90, 0), sweepPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SearchingDriverRadarPainter oldDelegate) {
    return oldDelegate.t != t;
  }
}
