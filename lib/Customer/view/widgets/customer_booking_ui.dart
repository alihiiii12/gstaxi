import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_button_dims.dart';
import '../../../core/constants/app_sizes.dart';
import 'customer_ui_theme.dart';

/// لوحة الحجز السفلية — تصميم زجاجي متناسق مع واجهة الراكب.
abstract final class CustomerBookingSheetStyle {
  static BoxDecoration decoration() => BoxDecoration(
        color: Colors.white.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(color: CustomerUiTheme.navy.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: CustomerUiTheme.navy.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, -8),
          ),
          BoxShadow(
            color: CustomerUiTheme.amber.withValues(alpha: 0.1),
            blurRadius: 18,
            offset: const Offset(0, -3),
          ),
        ],
      );
}

class CustomerBookingSheetHandle extends StatelessWidget {
  const CustomerBookingSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 44,
        height: 4,
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: CustomerUiTheme.navy.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class CustomerBookingMenuButton extends StatelessWidget {
  const CustomerBookingMenuButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.94),
          shape: BoxShape.circle,
          border: Border.all(
            color: CustomerUiTheme.navy.withValues(alpha: 0.08),
          ),
          boxShadow: [
            BoxShadow(
              color: CustomerUiTheme.navy.withValues(alpha: 0.1),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(
          Icons.menu_rounded,
          color: CustomerUiTheme.navy,
          size: 22,
        ),
      ),
    );
  }
}

class CustomerBookingWelcomeBanner extends StatelessWidget {
  const CustomerBookingWelcomeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: CustomerUiTheme.glassCard(radius: 20),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: CustomerUiTheme.iconOrb(),
            child: const Icon(
              Icons.waving_hand_rounded,
              color: CustomerUiTheme.navy,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'مرحباً بك في عائلة GS TAXI',
              style: TextStyle(
                color: CustomerUiTheme.navy,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerBookingSearchBar extends StatelessWidget {
  const CustomerBookingSearchBar({
    super.key,
    required this.hint,
    required this.hasDestination,
    required this.onTap,
    this.onClear,
  });

  final String hint;
  final bool hasDestination;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: CustomerUiTheme.glassCard(radius: 18),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: CustomerUiTheme.amber.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.search_rounded,
                color: CustomerUiTheme.navy,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                hint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: CustomerUiTheme.navy.withValues(
                    alpha: hasDestination ? 1 : 0.72,
                  ),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  height: 1.3,
                ),
              ),
            ),
            if (hasDestination && onClear != null)
              GestureDetector(
                onTap: onClear,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: CustomerUiTheme.navy.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.close_rounded,
                    color: CustomerUiTheme.navy.withValues(alpha: 0.65),
                    size: 18,
                  ),
                ),
              )
            else
              Icon(
                Icons.chevron_left_rounded,
                color: CustomerUiTheme.navy.withValues(alpha: 0.35),
                size: 22,
              ),
          ],
        ),
      ),
    );
  }
}

/// مبدّل فوري / حجز مسبق — نفس أسلوب تبويب «طلباتي».
class CustomerBookingSegment extends StatelessWidget {
  const CustomerBookingSegment({
    super.key,
    required this.scheduled,
    required this.onImmediate,
    required this.onScheduled,
    this.scheduleSubtitle,
    this.onPickSchedule,
    this.immediateLabel = 'فوري',
    this.scheduledLabel = 'حجز مسبق',
    this.scheduledFirst = false,
  });

  final bool scheduled;
  final VoidCallback onImmediate;
  final VoidCallback onScheduled;
  final String? scheduleSubtitle;
  final VoidCallback? onPickSchedule;
  final String immediateLabel;
  final String scheduledLabel;
  final bool scheduledFirst;

  @override
  Widget build(BuildContext context) {
    final idx = scheduledFirst
        ? (scheduled ? 0 : 1)
        : (scheduled ? 1 : 0);
    final firstIsScheduled = scheduledFirst;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tabW = constraints.maxWidth / 2;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: CustomerUiTheme.sheetBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: CustomerUiTheme.navy.withValues(alpha: 0.07),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                AnimatedPositionedDirectional(
                  duration: const Duration(milliseconds: 90),
                  curve: Curves.easeOut,
                  start: idx == 0 ? 4 : tabW + 4,
                  top: 4,
                  bottom: 4,
                  width: tabW - 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          CustomerUiTheme.navy,
                          CustomerUiTheme.navy.withValues(alpha: 0.88),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: CustomerUiTheme.navy.withValues(alpha: 0.22),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    if (firstIsScheduled) ...[
                      _SegmentItem(
                        icon: Icons.event_available_rounded,
                        label: scheduleSubtitle ?? scheduledLabel,
                        selected: scheduled,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (!scheduled) onScheduled();
                          onPickSchedule?.call();
                        },
                      ),
                      _SegmentItem(
                        icon: Icons.flash_on_rounded,
                        label: immediateLabel,
                        selected: !scheduled,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onImmediate();
                        },
                      ),
                    ] else ...[
                      _SegmentItem(
                        icon: Icons.flash_on_rounded,
                        label: immediateLabel,
                        selected: !scheduled,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onImmediate();
                        },
                      ),
                      _SegmentItem(
                        icon: Icons.event_available_rounded,
                        label: scheduleSubtitle ?? scheduledLabel,
                        selected: scheduled,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (!scheduled) onScheduled();
                          onPickSchedule?.call();
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SegmentItem extends StatelessWidget {
  const _SegmentItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? Colors.white : CustomerUiTheme.navy,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : CustomerUiTheme.navy,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerBookingHint extends StatelessWidget {
  const CustomerBookingHint({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: CustomerUiTheme.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: CustomerUiTheme.amber.withValues(alpha: 0.28),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.map_outlined,
            size: 18,
            color: CustomerUiTheme.navy.withValues(alpha: 0.75),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: CustomerUiTheme.navy.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class CustomerBookingPrimaryButton extends StatelessWidget {
  const CustomerBookingPrimaryButton({
    super.key,
    required this.label,
    this.priceLabel,
    required this.onPressed,
    this.enabled = true,
  });

  final String label;
  final String? priceLabel;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? () {
        HapticFeedback.lightImpact();
        onPressed?.call();
      } : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
        opacity: enabled ? 1 : 0.55,
        child: Container(
          width: double.infinity,
          height: AppButtonDims.heightLg,
          padding: EdgeInsets.symmetric(horizontal: AppSizes.w(18)),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: enabled
                  ? [
                      CustomerUiTheme.navy,
                      CustomerUiTheme.navy.withValues(alpha: 0.88),
                    ]
                  : [
                      Colors.grey.shade400,
                      Colors.grey.shade500,
                    ],
            ),
            borderRadius: BorderRadius.circular(AppButtonDims.radius + 4),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: CustomerUiTheme.navy.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: AppSizes.sp(16),
                  ),
                ),
              ),
              if (priceLabel != null && priceLabel!.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSizes.w(10),
                    vertical: AppSizes.h(6),
                  ),
                  decoration: BoxDecoration(
                    color: CustomerUiTheme.amber.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    priceLabel!,
                    style: TextStyle(
                      color: CustomerUiTheme.navy,
                      fontWeight: FontWeight.w900,
                      fontSize: AppSizes.sp(14),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomerMapToolItem {
  const CustomerMapToolItem({
    required this.icon,
    required this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool highlight;
}

/// شريط أدوات الخريطة — مجموعة أزرار زجاجية عائمة.
class CustomerMapToolRail extends StatelessWidget {
  const CustomerMapToolRail({super.key, required this.items});

  final List<CustomerMapToolItem> items;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.93),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: CustomerUiTheme.navy.withValues(alpha: 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: CustomerUiTheme.navy.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: CustomerUiTheme.amber.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _MapToolTile(item: items[i]),
                  if (i < items.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: CustomerUiTheme.navy.withValues(alpha: 0.06),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// زر واحد يفتح/يغلق قائمة منسدلة لأدوات الخريطة.
class CustomerMapToolsMenu extends StatelessWidget {
  const CustomerMapToolsMenu({
    super.key,
    required this.expanded,
    required this.onToggle,
    required this.items,
    this.expandUpward = false,
  });

  final bool expanded;
  final VoidCallback onToggle;
  final List<CustomerMapToolItem> items;
  /// عند التثبيت أسفل الشاشة تُفتح القائمة للأعلى.
  final bool expandUpward;

  Widget _toggleButton() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onToggle();
        },
        customBorder: const CircleBorder(),
        child: Ink(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.95),
            border: Border.all(
              color: CustomerUiTheme.navy.withValues(alpha: 0.1),
            ),
            boxShadow: [
              BoxShadow(
                color: CustomerUiTheme.navy.withValues(alpha: 0.14),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            expanded ? Icons.close_rounded : Icons.layers_rounded,
            color: CustomerUiTheme.navy,
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _expandedRail() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: expandUpward ? Alignment.bottomCenter : Alignment.topCenter,
      child: expanded
          ? Padding(
              padding: EdgeInsets.only(
                top: expandUpward ? 0 : 8,
                bottom: expandUpward ? 8 : 0,
              ),
              child: CustomerMapToolRail(items: items),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: expandUpward
          ? [_expandedRail(), _toggleButton()]
          : [_toggleButton(), _expandedRail()],
    );
  }
}

class _MapToolTile extends StatefulWidget {
  const _MapToolTile({required this.item});

  final CustomerMapToolItem item;

  @override
  State<_MapToolTile> createState() => _MapToolTileState();
}

class _MapToolTileState extends State<_MapToolTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        item.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 46,
          height: 46,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: item.highlight ? 40 : 36,
              height: item.highlight ? 40 : 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: item.highlight
                    ? LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [
                          CustomerUiTheme.amber,
                          CustomerUiTheme.amber.withValues(alpha: 0.78),
                        ],
                      )
                    : null,
                color: item.highlight
                    ? null
                    : CustomerUiTheme.navy.withValues(alpha: 0.05),
              ),
              child: Icon(
                item.icon,
                color: CustomerUiTheme.navy,
                size: item.highlight ? 21 : 19,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
