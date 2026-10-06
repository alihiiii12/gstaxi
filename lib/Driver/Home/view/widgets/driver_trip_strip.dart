import 'package:flutter/material.dart';

import '../../../../core/utils/driver_order_display.dart';
import '../../../../core/utils/request_category_fare_display.dart';
import '../../../../core/utils/trip_request_place_label.dart';
import '../../../../core/widgets/passenger_phone_link.dart';
import '../../../../core/widgets/trip_live_meter_panel.dart';
import '../../../../core/widgets/gst_booking_ui.dart';

/// شريط حجز مسبق مقبول قبل وقت التنفيذ.
class DriverUpcomingScheduledStrip extends StatelessWidget {
  const DriverUpcomingScheduledStrip({
    super.key,
    required this.request,
    this.onCancelScheduled,
    this.onGoToPassenger,
  });

  final Map<String, dynamic> request;
  final Future<void> Function(int requestId)? onCancelScheduled;
  final VoidCallback? onGoToPassenger;

  @override
  Widget build(BuildContext context) {
    final id = request['id']?.toString() ?? '';
    final when = formatScheduledRequestDate(request);
    final windowOpen = scheduledGoWindowOpen(request);
    final pickupLabel = pickupPlaceLabelForRequest(request);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: TripBookingTheme.addressBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'حجز مسبق #$id — ${passengerNameFromRequest(request)}',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: TripBookingTheme.navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            when != null ? 'موعد الرحلة: $when' : 'بانتظار موعد الرحلة',
            style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
          ),
          if (pickupLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'موقع الراكب: $pickupLabel',
              style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
            ),
          ],
          if (windowOpen && onGoToPassenger != null) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFFC107),
                foregroundColor: TripBookingTheme.navy,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: onGoToPassenger,
              icon: const Icon(Icons.navigation_rounded),
              label: const Text(
                'انطلق للراكب',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ] else if (!windowOpen) ...[
            const SizedBox(height: 6),
            Text(
              'يُفتح الحجز قبل الموعد بنصف ساعة — حتى ذلك الحين يمكنك استقبال طلبات فورية والعداد الحر.',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
            ),
          ],
          if (onCancelScheduled != null) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                final rid = int.tryParse(request['id']?.toString() ?? '');
                if (rid != null && rid > 0) onCancelScheduled!(rid);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade800),
              child: const Text('إلغاء الحجز'),
            ),
          ],
        ],
      ),
    );
  }
}

/// شريط الطلب النشط على الخريطة — زر الإجراء ثم العداد ثم المعلومات.
class DriverAssignedTripStrip extends StatelessWidget {
  const DriverAssignedTripStrip({
    super.key,
    required this.request,
    this.routeKm,
    required this.onMarkArrived,
    required this.onStartTrip,
    required this.onFinishTrip,
    this.onCancelScheduled,
    this.onCancelEnRoute,
  });

  final Map<String, dynamic> request;
  final double? routeKm;
  final void Function(int requestId) onMarkArrived;
  final void Function(int requestId) onStartTrip;
  final void Function(int requestId) onFinishTrip;
  final Future<void> Function(int requestId)? onCancelScheduled;
  final Future<void> Function(int requestId)? onCancelEnRoute;

  @override
  Widget build(BuildContext context) {
    final st = normTripStatusForOrder(request);
    final discountCode =
        (request['discountCode'] ?? request['discount_code'])?.toString();
    final discountValue = request['discountValue'] ?? request['discount_value'];
    final discountType =
        (request['discountType'] ?? request['discount_type'])?.toString();
    final discountSuffix = discountType == 'Fixed' ? ' ل.س' : '%';
    final zoneLabel = requestZoneLabel(request);
    final name = passengerNameFromRequest(request);
    final passengerPhone = passengerPhoneFromRequest(request);
    final hasPassengerPhone =
        passengerPhone != null && passengerPhone.isNotEmpty;

    String subtitle = st;
    if (st == 'Pending' && request['type']?.toString() == 'Immediate') {
      subtitle = 'موجّه إليك — بانتظار تأكيد القبول';
    }
    if (scheduledInWaitingPhase(request)) {
      final when = formatScheduledRequestDate(request);
      subtitle = when != null
          ? 'حجز مسبق — الموعد $when'
          : 'حجز مسبق — بانتظار وقت الرحلة';
    } else if (st == 'Reserved') {
      subtitle = 'متجه إلى الراكب — اضغط «بدء الرحلة» عند صعود الراكب';
    }
    if (st == 'DriverArrived') subtitle = 'اضغط «بدء الرحلة» عندما يصعد الراكب';
    if (st == 'AwaitingDestination') {
      subtitle = 'بانتظار تحديد الوجهة من الراكب';
    }
    if (st == 'Running') subtitle = 'التوجيه إلى وجهة الراكب';

    final pickupLabel = pickupPlaceLabelForRequest(request);
    final destLabel = destPlaceLabelForRequest(request);
    final destStops = <String>[];
    final wpRaw = request['waypoints'] ?? request['way_points'];
    if (wpRaw is List) {
      for (final e in wpRaw) {
        if (e is! Map) continue;
        final n = (e['name'] ?? e['label'])?.toString().trim() ?? '';
        if (n.isNotEmpty) destStops.add(n);
      }
    }
    final catName = carCategoryNameFromRequest(request);
    final crossNote = crossCategoryNoteFromRequest(request);
    final locDesc =
        (request['locationDesc'] ?? request['location_desc'])?.toString().trim() ??
            '';
    // أثناء الجري يُعرض سعر العداد لا التقديري.
    final categoryFare =
        st == 'Running' ? null : driverRequestUnifiedPricingLine(request);
    final showMeter = st == 'Running';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1) زر البدء / الإنهاء أولاً
        _AssignedActionButton(
          request: request,
          onMarkArrived: onMarkArrived,
          onStartTrip: onStartTrip,
          onFinishTrip: onFinishTrip,
          onCancelScheduled: onCancelScheduled,
          onCancelEnRoute: onCancelEnRoute,
        ),
        // 2) عداد الرحلة مباشرة تحت زر الإنهاء
        if (showMeter) ...[
          const SizedBox(height: 12),
          const TripLiveMeterPanel(
            compact: true,
            title: 'التكلفة الحالية',
            forceShow: true,
          ),
        ],
        const SizedBox(height: 12),
        // 3) باقي المعلومات تحت العداد
        TripBookingAddressCard(
          pickupLabel: pickupLabel,
          destinationLabel: destLabel,
          destinationStops: destStops.isEmpty ? null : destStops,
        ),
        const SizedBox(height: 10),
        if (name.isNotEmpty && name != 'راكب')
          Text(
            'الراكب: $name',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: TripBookingTheme.navy,
            ),
          ),
        if (hasPassengerPhone) ...[
          const SizedBox(height: 4),
          PassengerPhoneLink(
            phone: passengerPhone,
            iconSize: 16,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: TripBookingTheme.navy,
              letterSpacing: 0.3,
              fontSize: 13,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(color: Colors.grey.shade800, fontSize: 12),
        ),
        if (catName.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'فئة المركبة: $catName',
            style: TextStyle(
              color: Colors.blueGrey.shade800,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (crossNote != null) ...[
          const SizedBox(height: 6),
          CrossCategoryNoteChip(note: crossNote),
        ],
        if (categoryFare != null) ...[
          const SizedBox(height: 4),
          Text(
            categoryFare,
            style: TextStyle(
              color: Colors.green.shade800,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (locDesc.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'ملاحظات: $locDesc',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
        if (discountCode != null && discountCode.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'كوبون: $discountCode (${discountValue ?? ''}$discountSuffix)',
              style: TextStyle(
                color: Colors.green.shade800,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (zoneLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              zoneLabel,
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        if (routeKm != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'المسافة: ${routeKm!.toStringAsFixed(1)} كم',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
            ),
          ),
      ],
    );
  }
}

class _AssignedActionButton extends StatelessWidget {
  const _AssignedActionButton({
    required this.request,
    required this.onMarkArrived,
    required this.onStartTrip,
    required this.onFinishTrip,
    this.onCancelScheduled,
    this.onCancelEnRoute,
  });

  final Map<String, dynamic> request;
  final void Function(int requestId) onMarkArrived;
  final void Function(int requestId) onStartTrip;
  final void Function(int requestId) onFinishTrip;
  final Future<void> Function(int requestId)? onCancelScheduled;
  final Future<void> Function(int requestId)? onCancelEnRoute;

  @override
  Widget build(BuildContext context) {
    final st = normTripStatusForOrder(request);
    final id = int.tryParse(request['id']?.toString() ?? '');
    if (id == null) return const SizedBox.shrink();

    if (st == 'Reserved') {
      if (scheduledInWaitingPhase(request)) {
        final when = formatScheduledRequestDate(request);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (when != null)
              Text(
                'موعد الرحلة: $when',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            if (onCancelScheduled != null && requestIsScheduled(request)) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => onCancelScheduled!(id),
                child: Text(
                  'إلغاء + اعتذار',
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TripBookingPrimaryButton(
            label: 'بدء الرحلة',
            onPressed: () => onStartTrip(id),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => onMarkArrived(id),
            style: OutlinedButton.styleFrom(
              foregroundColor: TripBookingTheme.navy,
              side: const BorderSide(color: TripBookingTheme.navy),
            ),
            child: const Text('وصلت للراكب'),
          ),
          if (driverMayCancelEnRoute(request) && onCancelEnRoute != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => onCancelEnRoute!(id),
              child: Text(
                'إلغاء الطلب',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      );
    }
    if (st == 'Running') {
      return TripBookingPrimaryButton(
        label: 'إنهاء الرحلة',
        onPressed: () => onFinishTrip(id),
      );
    }
    if (st == 'DriverArrived') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TripBookingPrimaryButton(
            label: 'بدء الرحلة',
            onPressed: () => onStartTrip(id),
          ),
          if (driverMayCancelEnRoute(request) && onCancelEnRoute != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => onCancelEnRoute!(id),
              child: Text(
                'إلغاء الطلب',
                style: TextStyle(
                  color: Colors.red.shade800,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      );
    }
    if (st == 'AwaitingDestination') {
      final hasDest = request['destLocationId'] != null ||
          request['dest_location_id'] != null ||
          request['destLocation'] != null;
      if (hasDest) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TripBookingPrimaryButton(
              label: 'بدء الرحلة',
              onPressed: () => onStartTrip(id),
            ),
            if (driverMayCancelEnRoute(request) && onCancelEnRoute != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => onCancelEnRoute!(id),
                child: Text(
                  'إلغاء الطلب',
                  style: TextStyle(color: Colors.red.shade800),
                ),
              ),
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'بانتظار تحديد الوجهة من الراكب…',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          if (driverMayCancelEnRoute(request) && onCancelEnRoute != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => onCancelEnRoute!(id),
              child: Text(
                'إلغاء الطلب',
                style: TextStyle(color: Colors.red.shade800),
              ),
            ),
          ],
        ],
      );
    }
    return const SizedBox.shrink();
  }
}
