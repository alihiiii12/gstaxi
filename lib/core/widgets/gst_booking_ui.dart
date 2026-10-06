import 'package:flutter/material.dart';

export 'trip_booking_search_overlay.dart';

/// ألوان Syria Taxi لـ GS Taxi (كحلي + أصفر).
abstract final class TripBookingTheme {
  static const Color navy = Color(0xFF11215B);
  static const Color amber = Color(0xFFFFC107);
  static const Color sheetBg = Color(0xFFF5F6FA);
  static const Color cardBg = Colors.white;
  static const Color muted = Color(0xFF6B7280);

  static BoxDecoration sheetDecoration({Color? color}) => BoxDecoration(
        color: color ?? cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 14,
            offset: Offset(0, -4),
          ),
        ],
      );

  static BoxDecoration addressBoxDecoration() => BoxDecoration(
        color: navy.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: navy.withValues(alpha: 0.12)),
      );
}

class TripBookingSheetHandle extends StatelessWidget {
  const TripBookingSheetHandle({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 4,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: color ?? Colors.grey.shade300,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

class TripBookingCircleButton extends StatelessWidget {
  const TripBookingCircleButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.backgroundColor,
    this.iconColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor ?? Colors.white.withValues(alpha: 0.95),
      elevation: 4,
      shadowColor: Colors.black38,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: iconColor ?? TripBookingTheme.navy, size: 22),
        ),
      ),
    );
  }
}

/// صف A/B لنقطة الانطلاق والوجهة.
class TripBookingAddressCard extends StatelessWidget {
  const TripBookingAddressCard({
    super.key,
    required this.pickupLabel,
    required this.destinationLabel,
    this.destinationStops,
    this.onEditPickup,
    this.onEditDestination,
    this.onEditStop,
  });

  final String pickupLabel;
  final String destinationLabel;
  /// إن وُجدت أكثر من وجهة تُعرض كصفوف B, C, D…
  final List<String>? destinationStops;
  final VoidCallback? onEditPickup;
  final VoidCallback? onEditDestination;
  final ValueChanged<int>? onEditStop;

  static String _letterForIndex(int i) {
    if (i < 26) return String.fromCharCode(65 + i); // A, B, C…
    return '${i + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final stops = destinationStops;
    final multi = stops != null && stops.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: TripBookingTheme.addressBoxDecoration(),
      child: Column(
        children: [
          _AddressRow(
            letter: 'A',
            letterColor: TripBookingTheme.navy,
            label: pickupLabel.isEmpty ? 'نقطة الانطلاق' : pickupLabel,
            onTap: onEditPickup,
          ),
          if (multi)
            for (var i = 0; i < stops.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1, color: Colors.grey.shade300),
              ),
              _AddressRow(
                letter: _letterForIndex(i + 1),
                letterColor: TripBookingTheme.amber,
                label: stops[i].isEmpty ? 'وجهة' : stops[i],
                onTap: onEditStop != null
                    ? () => onEditStop!(i)
                    : onEditDestination,
              ),
            ]
          else ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(height: 1, color: Colors.grey.shade300),
            ),
            _AddressRow(
              letter: 'B',
              letterColor: TripBookingTheme.amber,
              label: destinationLabel.isEmpty ? 'الوجهة' : destinationLabel,
              onTap: onEditDestination,
            ),
          ],
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    required this.letter,
    required this.letterColor,
    required this.label,
    this.onTap,
  });

  final String letter;
  final Color letterColor;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lightLetter = letterColor == TripBookingTheme.amber;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: letterColor,
              shape: BoxShape.circle,
            ),
            child: Text(
              letter,
              style: TextStyle(
                color: lightLetter ? TripBookingTheme.navy : Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: TripBookingTheme.navy,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// زر إجراء رئيسي (نص + سعر) لـ GS Taxi.
class TripBookingPrimaryButton extends StatelessWidget {
  const TripBookingPrimaryButton({
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
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: TripBookingTheme.navy,
          disabledBackgroundColor: Colors.grey.shade400,
          foregroundColor: TripBookingTheme.amber,
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: enabled ? onPressed : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            if (priceLabel != null && priceLabel!.isNotEmpty)
              Text(
                priceLabel!,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// صف خيارات (فوري / حجز مسبق).
class TripBookingOptionsRow extends StatelessWidget {
  const TripBookingOptionsRow({
    super.key,
    required this.scheduled,
    required this.onToggleImmediate,
    required this.onToggleScheduled,
    this.scheduleSubtitle,
    this.onPickSchedule,
  });

  final bool scheduled;
  final VoidCallback onToggleImmediate;
  final VoidCallback onToggleScheduled;
  final String? scheduleSubtitle;
  final VoidCallback? onPickSchedule;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OptionChip(
            icon: Icons.bolt_rounded,
            label: 'فوري',
            selected: !scheduled,
            onTap: onToggleImmediate,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _OptionChip(
            icon: Icons.event_rounded,
            label: scheduleSubtitle ?? 'حجز مسبق',
            selected: scheduled,
            onTap: () {
              if (!scheduled) onToggleScheduled();
              onPickSchedule?.call();
            },
          ),
        ),
      ],
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
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
    return Material(
      color: selected
          ? TripBookingTheme.amber.withValues(alpha: 0.25)
          : Colors.grey.shade100,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected ? TripBookingTheme.navy : TripBookingTheme.muted,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: selected ? TripBookingTheme.navy : TripBookingTheme.muted,
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

/// لوحة انتظار السائق / البحث عن سائق.
class TripBookingWaitingPanel extends StatelessWidget {
  const TripBookingWaitingPanel({
    super.key,
    required this.title,
    this.subtitle,
    this.cancelLabel = 'إلغاء الطلب',
    this.onCancel,
    this.showProgress = true,
    this.error,
  });

  final String title;
  final String? subtitle;
  final String cancelLabel;
  final VoidCallback? onCancel;
  final bool showProgress;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const TripBookingSheetHandle(),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: TripBookingTheme.navy,
          ),
        ),
        if (showProgress) ...[
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.grey.shade200,
              color: TripBookingTheme.amber,
            ),
          ),
        ],
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            subtitle!,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
        if (error != null && error!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: TextStyle(color: Colors.red.shade800, fontSize: 12),
          ),
        ],
        if (onCancel != null) ...[
          const SizedBox(height: 18),
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: TripBookingTheme.navy,
              alignment: AlignmentDirectional.centerStart,
            ),
            child: Text(
              cancelLabel,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ],
      ],
    );
  }
}

/// شارة لسائق يستلم طلباً من فئة أخرى — مثل «طلب اقتصادية — الأجرة بتسعيرة الاقتصادية».
class CrossCategoryNoteChip extends StatelessWidget {
  const CrossCategoryNoteChip({super.key, required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade600),
      ),
      child: Row(
        children: [
          Icon(Icons.local_offer_outlined, size: 16, color: Colors.amber.shade900),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              note,
              style: TextStyle(
                color: Colors.amber.shade900,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
