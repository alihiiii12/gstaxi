import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// زر «اسحب للبدء» بتصميم فريد: حلقة متوهجة، إبهام دائري، ونص يتلاشى مع السحب.
class CustomerSlideToStart extends StatefulWidget {
  const CustomerSlideToStart({
    super.key,
    required this.onComplete,
    this.hint = 'بعد السحب ستظهر خيارات الحجز وتحديد الوجهة.',
  });

  final VoidCallback onComplete;
  final String hint;

  static const Color amber = Color(0xFFFFC107);
  static const Color navy = Color(0xFF11215B);

  @override
  State<CustomerSlideToStart> createState() => _CustomerSlideToStartState();
}

class _CustomerSlideToStartState extends State<CustomerSlideToStart>
    with TickerProviderStateMixin {
  static const double _trackH = 68;
  static const double _thumbSize = 56;
  static const double _pad = 6;

  late final AnimationController _pulse;
  late final AnimationController _shimmer;
  late final AnimationController _chevron;

  double _dragX = 0;
  bool _done = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _chevron = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _shimmer.dispose();
    _chevron.dispose();
    super.dispose();
  }

  double _maxDrag(double trackW) =>
      math.max(0, trackW - _thumbSize - _pad * 2);

  Future<void> _finish(double trackW) async {
    if (_submitting || _done) return;
    _submitting = true;
    HapticFeedback.mediumImpact();
    setState(() {
      _dragX = _maxDrag(trackW);
      _done = true;
    });
    await Future<void>.delayed(const Duration(milliseconds: 280));
    if (!mounted) return;
    widget.onComplete();
  }

  void _onDragUpdate(double dx, double trackW) {
    if (_done) return;
    setState(() {
      _dragX = dx.clamp(0, _maxDrag(trackW));
    });
  }

  void _onDragEnd(double trackW) {
    if (_done) return;
    final threshold = _maxDrag(trackW) * 0.82;
    if (_dragX >= threshold) {
      _finish(trackW);
      return;
    }
    setState(() => _dragX = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final trackW = constraints.maxWidth;
            final progress = _maxDrag(trackW) <= 0
                ? 0.0
                : (_dragX / _maxDrag(trackW)).clamp(0.0, 1.0);
            final textOpacity = (1 - progress * 1.35).clamp(0.0, 1.0);

            return AnimatedBuilder(
              animation: Listenable.merge([_pulse, _shimmer, _chevron]),
              builder: (context, _) {
                final pulse = 0.55 + _pulse.value * 0.45;
                final chevOffset = _chevron.value * 6;

                return SizedBox(
                  height: _trackH,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // توهج خلفي نابض
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: [
                              BoxShadow(
                                color: CustomerSlideToStart.amber
                                    .withValues(alpha: 0.22 * pulse),
                                blurRadius: 28 + pulse * 10,
                                spreadRadius: pulse * 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // المسار
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            gradient: LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [
                                CustomerSlideToStart.navy,
                                const Color(0xFF0A1433),
                              ],
                            ),
                            border: Border.all(
                              color: CustomerSlideToStart.amber
                                  .withValues(alpha: 0.35 + pulse * 0.2),
                              width: 1.5,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(34),
                            child: CustomPaint(
                              painter: _ShimmerPainter(
                                progress: _shimmer.value,
                                color: CustomerSlideToStart.amber
                                    .withValues(alpha: 0.12),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // شريط تقدّم
                      Positioned(
                        right: _pad,
                        top: _pad,
                        bottom: _pad,
                        width: _dragX + _thumbSize,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: [
                                CustomerSlideToStart.amber
                                    .withValues(alpha: 0.35 * progress),
                                CustomerSlideToStart.amber
                                    .withValues(alpha: 0.08 * progress),
                              ],
                            ),
                          ),
                        ),
                      ),
                      // النص
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: textOpacity,
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform.translate(
                                    offset: Offset(-chevOffset, 0),
                                    child: Icon(
                                      Icons.keyboard_double_arrow_left_rounded,
                                      color: Colors.white.withValues(alpha: 0.55),
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'اسحب للبدء',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      // الإبهام
                      Positioned(
                        right: _pad + _dragX,
                        top: (_trackH - _thumbSize) / 2,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (d) {
                            // RTL: السحب لليسار يزيد _dragX
                            _onDragUpdate(_dragX - d.delta.dx, trackW);
                          },
                          onHorizontalDragEnd: (_) => _onDragEnd(trackW),
                          child: Transform.scale(
                            scale: 1.0 + progress * 0.06,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: [
                                    Color(0xFFFFD54F),
                                    Color(0xFFFFB300),
                                  ],
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: CustomerSlideToStart.amber
                                        .withValues(alpha: 0.55),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: SizedBox(
                                width: _thumbSize,
                                height: _thumbSize,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Icon(
                                      _done
                                          ? Icons.check_rounded
                                          : Icons.local_taxi_rounded,
                                      color: CustomerSlideToStart.navy,
                                      size: _done ? 28 : 26,
                                    ),
                                    if (!_done)
                                      Positioned(
                                        left: 8 + chevOffset,
                                        child: Icon(
                                          Icons.chevron_left_rounded,
                                          size: 18,
                                          color: CustomerSlideToStart.navy
                                              .withValues(alpha: 0.35),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 10),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          builder: (context, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset(0, (1 - v) * 8),
              child: child,
            ),
          ),
          child: Text(
            widget.hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CustomerSlideToStart.navy.withValues(alpha: 0.55),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width * 0.35;
    final x = (size.width + w) * progress - w;
    final rect = Rect.fromLTWH(x, 0, w, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0),
          color,
          color.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) =>
      old.progress != progress || old.color != color;
}
