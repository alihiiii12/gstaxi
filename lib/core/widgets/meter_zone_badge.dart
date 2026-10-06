import 'package:flutter/material.dart';

/// شارة «تسعيرة مدينة دمشق ← الريف ×1.25» على العداد عند الخروج من منطقة التسعير.
class MeterZoneBadge extends StatelessWidget {
  const MeterZoneBadge({
    super.key,
    required this.label,
    this.dense = false,
    this.onDark = true,
  });

  final String label;
  final bool dense;
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    if (label.trim().isEmpty) return const SizedBox.shrink();
    const amber = Color(0xFFFFC107);
    final fg = onDark ? const Color(0xFFFFD54F) : const Color(0xFF8A5A00);
    return Container(
      margin: EdgeInsets.only(top: dense ? 4 : 8),
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 3 : 6),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: onDark ? 0.18 : 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: amber.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.alt_route_rounded, size: dense ? 13 : 16, color: onDark ? amber : fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: fg,
                fontSize: dense ? 10.5 : 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
