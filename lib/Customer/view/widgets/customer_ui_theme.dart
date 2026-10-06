import 'package:flutter/material.dart';

/// ألوان وتنسيقات مشتركة لواجهة الراكب.
abstract final class CustomerUiTheme {
  static const Color amber = Color(0xFFFFC107);
  static const Color navy = Color(0xFF11215B);
  static const Color charcoal = Color(0xFF212121);
  static const Color sheetBg = Color(0xFFF5F6FA);
  static const Color muted = Color(0xFF6B7280);

  static BoxDecoration screenGradient = const BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
      colors: [
        Color(0xFFFFF9E6),
        Color(0xFFF5F6FA),
        Color(0xFFEEF1F8),
      ],
      stops: [0.0, 0.45, 1.0],
    ),
  );

  static BoxDecoration glassCard({double radius = 24}) => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: navy.withValues(alpha: 0.06), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: navy.withValues(alpha: 0.07),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: amber.withValues(alpha: 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      );

  static BoxDecoration iconOrb({Color? tint}) => BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            (tint ?? amber).withValues(alpha: 0.95),
            (tint ?? amber).withValues(alpha: 0.65),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: (tint ?? amber).withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      );
}
