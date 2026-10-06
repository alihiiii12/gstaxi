import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../Customer/view/widgets/customer_ui_theme.dart';

/// زر اسحب للبدء/الإيقاف للفارس — نفس أسلوب الراكب مع ألوان حسب الحالة.
class DriverSlideToToggle extends StatefulWidget {
  const DriverSlideToToggle({
    super.key,
    required this.isOnline,
    required this.onToggle,
    this.hint,
  });

  final bool isOnline;
  final VoidCallback onToggle;
  final String? hint;

  @override
  State<DriverSlideToToggle> createState() => _DriverSlideToToggleState();
}

class _DriverSlideToToggleState extends State<DriverSlideToToggle>
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
  void didUpdateWidget(covariant DriverSlideToToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isOnline != widget.isOnline) {
      _dragX = 0;
      _done = false;
      _submitting = false;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _shimmer.dispose();
    _chevron.dispose();
    super.dispose();
  }

  Color get _accent =>
      widget.isOnline ? const Color(0xFFEF4444) : CustomerUiTheme.amber;

  Color get _trackStart =>
      widget.isOnline ? const Color(0xFFB91C1C) : CustomerUiTheme.navy;

  Color get _trackEnd =>
      widget.isOnline ? const Color(0xFF7F1D1D) : const Color(0xFF0A1433);

  String get _label =>
      widget.isOnline ? 'اسحب للإيقاف' : 'اسحب للبدء';

  IconData get _thumbIcon =>
      widget.isOnline ? Icons.stop_rounded : Icons.play_arrow_rounded;

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
    widget.onToggle();
    setState(() {
      _dragX = 0;
      _done = false;
      _submitting = false;
    });
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
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            boxShadow: [
                              BoxShadow(
                                color: _accent.withValues(alpha: 0.22 * pulse),
                                blurRadius: 28 + pulse * 10,
                                spreadRadius: pulse * 2,
                              ),
                            ],
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(34),
                            gradient: LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [_trackStart, _trackEnd],
                            ),
                            border: Border.all(
                              color: _accent.withValues(alpha: 0.35 + pulse * 0.2),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: _pad,
                        top: _pad,
                        bottom: _pad,
                        width: _dragX + _thumbSize,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: LinearGradient(
                              colors: [
                                _accent.withValues(alpha: 0.35 * progress),
                                _accent.withValues(alpha: 0.08 * progress),
                              ],
                            ),
                          ),
                        ),
                      ),
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
                                  Text(
                                    _label,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: _pad + _dragX,
                        top: (_trackH - _thumbSize) / 2,
                        child: GestureDetector(
                          onHorizontalDragUpdate: (d) {
                            setState(() {
                              _dragX = (_dragX - d.delta.dx)
                                  .clamp(0, _maxDrag(trackW));
                            });
                          },
                          onHorizontalDragEnd: (_) {
                            if (_dragX >= _maxDrag(trackW) * 0.82) {
                              _finish(trackW);
                            } else {
                              setState(() => _dragX = 0);
                            }
                          },
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: widget.isOnline
                                    ? const [Color(0xFFFFE4E6), Color(0xFFFECACA)]
                                    : const [Color(0xFFFFD54F), Color(0xFFFFB300)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _accent.withValues(alpha: 0.55),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: SizedBox(
                              width: _thumbSize,
                              height: _thumbSize,
                              child: Icon(
                                _done ? Icons.check_rounded : _thumbIcon,
                                color: widget.isOnline
                                    ? const Color(0xFFB91C1C)
                                    : CustomerUiTheme.navy,
                                size: 28,
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
        if (widget.hint != null) ...[
          const SizedBox(height: 10),
          Text(
            widget.hint!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: CustomerUiTheme.navy.withValues(alpha: 0.55),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
