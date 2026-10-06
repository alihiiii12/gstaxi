import 'dart:math' as math;

import 'package:flutter/material.dart';

/// يقلب البطاقة حول محورها العمودي عند تغيّر [child] — بدون تحريك بقية الشاشة.
class AuthCardFlipper extends StatefulWidget {
  const AuthCardFlipper({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 620),
  });

  final Widget child;
  final Duration duration;

  @override
  State<AuthCardFlipper> createState() => _AuthCardFlipperState();
}

class _AuthCardFlipperState extends State<AuthCardFlipper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Widget _visible;
  Widget? _incoming;

  @override
  void initState() {
    super.initState();
    _visible = widget.child;
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _controller.addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && _incoming != null) {
      setState(() {
        _visible = _incoming!;
        _incoming = null;
      });
      _controller.value = 0;
    }
  }

  @override
  void didUpdateWidget(AuthCardFlipper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.child.key != oldWidget.child.key) {
      _incoming = widget.child;
      _controller.forward(from: 0);
    } else if (_incoming == null) {
      _visible = widget.child;
    }
  }

  @override
  void dispose() {
    _controller.removeStatusListener(_onStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final showingFirstHalf = t < 0.5;
        final face = showingFirstHalf ? _visible : (_incoming ?? _visible);
        final angle = showingFirstHalf ? t * math.pi : (t - 1) * math.pi;

        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0011)
            ..rotateY(angle),
          child: face,
        );
      },
    );
  }
}
