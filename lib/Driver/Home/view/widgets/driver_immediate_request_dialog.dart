import 'dart:async';
import '../../../../core/constants/snack_bar.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/utils/app_alert_sound.dart';
import '../../../../core/utils/driver_order_display.dart';
import '../../../../core/utils/request_category_fare_display.dart';
import '../../../../core/utils/trip_location_helpers.dart';
import '../../../../core/utils/trip_request_place_label.dart';
import '../../../../core/widgets/gst_booking_ui.dart';
import '../../../Order/controller/immediate_bookings_controller.dart';
import '../../controller/driver_assigned_trip_controller.dart';
import '../../controller/driver_location_controller.dart';
import 'driver_immediate_map_dialog.dart';

/// حوار قبول/رفض طلب فوري جديد — نمط GS Taxi.
class DriverImmediateRequestDialog {
  DriverImmediateRequestDialog._();

  static const Distance _geo = Distance();

  static String _distanceLabel(Map<String, dynamic> order) {
    final raw = order['distance_from_pickup_km'];
    if (raw is num) {
      final km = raw.toDouble();
      if (km < 1) return '${(km * 1000).round()} م';
      final decimals = km < 10 ? 1 : 0;
      return '${km.toStringAsFixed(decimals)} كم';
    }

    LatLng? driverPoint;
    if (Get.isRegistered<DriverController>()) {
      driverPoint = Get.find<DriverController>().currentPosition.value;
    }
    final pickup = TripLocationHelpers.extractStartPoint(order);
    if (driverPoint != null && pickup != null) {
      final meters = _geo.as(LengthUnit.Meter, driverPoint, pickup);
      if (meters < 1000) return '${meters.round()} م';
      return '${(meters / 1000).toStringAsFixed(1)} كم';
    }
    return '—';
  }

  static void show({
    required Map<String, dynamic> order,
    required ImmediateBookingsController immediate,
    required DriverAssignedTripController trip,
    required void Function(int? openId) setOpenDialogRequestId,
    required int? Function() getOpenDialogRequestId,
    required void Function(int? lastNotifiedId) setLastNotifiedId,
    required int? Function() getLastNotifiedId,
    VoidCallback? onSheetClosed,
    VoidCallback? onDecision,
    bool hasOtherImmediate = false,
    bool playSound = true,
  }) {
    final rid = order['id']?.toString() ?? '';
    final idNum = int.tryParse(rid) ?? 0;
    final name = passengerNameFromRequest(order);
    final pickupLabel = pickupPlaceLabelForRequest(order);
    final destLabel = destPlaceLabelForRequest(order);
    final catName = carCategoryNameFromRequest(order);
    final crossNote = crossCategoryNoteFromRequest(order);
    final distanceLabel = _distanceLabel(order);
    final pickupPoint = TripLocationHelpers.extractStartPoint(order);
    final categoryFare = driverRequestUnifiedPricingLine(order);
    final isScheduled = requestIsScheduled(order);
    final schedWhen = formatScheduledRequestDate(order);
    final titleText = isScheduled ? 'حجز مسبق جديد' : 'طلب فوري جديد';
    final subtitleText = isScheduled
        ? (schedWhen != null
            ? 'حجز #$rid — الموعد $schedWhen — $distanceLabel'
            : 'حجز #$rid — $distanceLabel')
        : 'طلب #$rid — $distanceLabel';

    if (idNum > 0) setOpenDialogRequestId(idNum);
    if (playSound) unawaited(AppAlertSound.playNewRequest());

    final ctx = Get.context;
    if (ctx == null) return;

    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        final bottom = MediaQuery.viewPaddingOf(sheetCtx).bottom;
        return PopScope(
          canPop: false,
          child: Container(
            decoration: TripBookingTheme.sheetDecoration(),
            padding: EdgeInsets.fromLTRB(18, 8, 18, 16 + bottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TripBookingSheetHandle(),
                Text(
                  titleText,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: TripBookingTheme.navy,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitleText,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                TripBookingAddressCard(
                  pickupLabel: pickupLabel,
                  destinationLabel: destLabel,
                ),
                if (name.isNotEmpty && name != 'راكب') ...[
                  const SizedBox(height: 10),
                  Text(
                    'الراكب: $name',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: TripBookingTheme.navy,
                    ),
                  ),
                ],
                if (catName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'فئة المركبة: $catName',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800),
                  ),
                ],
                if (crossNote != null) ...[
                  const SizedBox(height: 8),
                  CrossCategoryNoteChip(note: crossNote),
                ],
                if (categoryFare != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    categoryFare,
                    style: TextStyle(
                      color: Colors.green.shade800,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (hasOtherImmediate) ...[
                  const SizedBox(height: 8),
                  Text(
                    'هناك طلبات أخرى في الانتظار.',
                    style: TextStyle(
                      color: Colors.orange.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          LatLng driverPoint;
                          if (Get.isRegistered<DriverController>()) {
                            driverPoint = Get.find<DriverController>()
                                .currentPosition
                                .value;
                          } else if (pickupPoint != null) {
                            driverPoint = pickupPoint;
                          } else {
                            AppSnackBar.notify('الخريطة', 'لا تتوفر إحداثيات');
                            return;
                          }
                          if (pickupPoint == null) {
                            AppSnackBar.notify('الخريطة', 'لا تتوفر نقطة انطلاق');
                            return;
                          }
                          unawaited(
                            showDriverImmediateMapDialog(
                              sheetCtx,
                              driverPoint: driverPoint,
                              pickupPoint: pickupPoint,
                              passengerName: name,
                              pickupLabel: pickupLabel,
                              requestId: idNum > 0 ? idNum : null,
                            ),
                          );
                        },
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('الخريطة'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: TripBookingTheme.navy,
                          minimumSize: const Size(0, 46),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () async {
                          final id = int.tryParse(rid);
                          onDecision?.call();
                          if (id == null || id <= 0) {
                            Navigator.pop(sheetCtx);
                            return;
                          }
                          if (getLastNotifiedId() == id) setLastNotifiedId(null);
                          Navigator.pop(sheetCtx);
                          await immediate.ignoreImmediateForMe(id);
                          AppSnackBar.notify(
                            'تم التجاهل',
                            'لن يظهر لك هذا الطلب مرة أخرى',
                            duration: const Duration(seconds: 3),
                          );
                        },
                        child: const Text('تجاهل'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TripBookingPrimaryButton(
                        label: 'قبول الطلب',
                        onPressed: () async {
                          final id = int.tryParse(rid);
                          onDecision?.call();
                          if (id == null) {
                            Navigator.pop(sheetCtx);
                            return;
                          }
                          Navigator.pop(sheetCtx);
                          final result = await immediate.acceptWithResult(id);
                          if (!result.ok) {
                            AppSnackBar.notify(
                              result.takenByOther ? 'تم قبول الطلب' : 'فشل',
                              result.message,
                              duration: const Duration(seconds: 7),
                            );
                            if (getLastNotifiedId() == id) {
                              setLastNotifiedId(null);
                            }
                            return;
                          }
                          if (getLastNotifiedId() == id) setLastNotifiedId(null);
                          AppSnackBar.notify('تم', result.message);
                          if (Get.isRegistered<DriverController>()) {
                            Get.find<DriverController>()
                                .setAcceptedTripPreview(order);
                          } else {
                            final pickup = TripLocationHelpers.extractLocation(
                              order,
                              'startLocation',
                            );
                            trip.acceptImmediatePickup(pickup);
                            Get.find<DriverController>()
                                .notifyAssignedTripRefresh();
                          }
                          // لا تتصل برقم الزبون تلقائياً — الاتصال من رابط الرقم عند الحاجة.
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) {
      unawaited(AppAlertSound.stopRingtone());
      onSheetClosed?.call();
      if (getOpenDialogRequestId() == idNum) setOpenDialogRequestId(null);
      // لا تمسح lastNotified هنا — يبقى الطلب مثبتاً حتى قبول/تجاهل صريح.
    });
  }
}
