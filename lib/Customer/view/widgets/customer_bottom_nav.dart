import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// شريط تنقّل سفلي عائم بتصميم حديث ومؤشر متحرّك.
class CustomerBottomNav extends StatelessWidget {
  const CustomerBottomNav({
    super.key,
    required this.currentIndex,
    required this.onChanged,
  });

  static const Color amber = Color(0xFFFFC107);
  static const Color navy = Color(0xFF11215B);
  static const Color charcoal = Color(0xFF212121);

  /// ارتفاع الشريط + الهامش — لحجز مسافة أسفل المحتوى.
  static const double reservedHeight = 92;

  final int currentIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 10 + bottom),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: navy.withValues(alpha: 0.08),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: navy.withValues(alpha: 0.14),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: amber.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: SizedBox(
              height: 64,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tabW = constraints.maxWidth / 2;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedPositionedDirectional(
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeOutCubic,
                        start: currentIndex == 0 ? 6 : tabW + 6,
                        top: 6,
                        bottom: 6,
                        width: tabW - 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [
                                amber,
                                amber.withValues(alpha: 0.82),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(22),
                            boxShadow: [
                              BoxShadow(
                                color: amber.withValues(alpha: 0.45),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          _NavItem(
                            selected: currentIndex == 0,
                            icon: Icons.local_taxi_rounded,
                            label: 'حجز رحلة',
                            onTap: () {
                              if (currentIndex != 0) {
                                HapticFeedback.selectionClick();
                                onChanged(0);
                              }
                            },
                          ),
                          _NavItem(
                            selected: currentIndex == 1,
                            icon: Icons.receipt_long_rounded,
                            label: 'طلباتي',
                            onTap: () {
                              if (currentIndex != 1) {
                                HapticFeedback.selectionClick();
                                onChanged(1);
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          splashColor: CustomerBottomNav.navy.withValues(alpha: 0.06),
          highlightColor: Colors.transparent,
          child: AnimatedScale(
            scale: selected ? 1.0 : 0.94,
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutBack,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => ScaleTransition(
                    scale: anim,
                    child: child,
                  ),
                  child: Icon(
                    icon,
                    key: ValueKey('$icon-$selected'),
                    size: selected ? 24 : 22,
                    color: selected
                        ? CustomerBottomNav.navy
                        : CustomerBottomNav.charcoal.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 3),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    fontSize: selected ? 12 : 11,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected
                        ? CustomerBottomNav.navy
                        : CustomerBottomNav.charcoal.withValues(alpha: 0.45),
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
