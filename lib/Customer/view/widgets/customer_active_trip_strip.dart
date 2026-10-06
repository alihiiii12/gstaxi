import 'package:flutter/material.dart';

import '../../../core/utils/customer_trip_status_helpers.dart';
import '../../../core/utils/driver_card_subtitle.dart';
import '../../../core/utils/phone_call_launcher.dart';
import '../../../core/widgets/driver_customer_preview_row.dart';
import '../../../core/widgets/gst_booking_ui.dart';

/// شريط الرحلة النشطة للزبون — نمط GS Taxi بألوان GS TAXI.
class CustomerActiveTripStrip extends StatelessWidget {
  const CustomerActiveTripStrip({
    super.key,
    required this.trip,
    this.onCallDriver,
  });

  final Map<String, dynamic> trip;
  final void Function(String phone)? onCallDriver;

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic>? driverMap;
    Map<String, dynamic>? userMap;
    final drTop = trip['driver'];
    if (drTop is Map) {
      driverMap = Map<String, dynamic>.from(drTop);
      final u = drTop['user'];
      if (u is Map) userMap = Map<String, dynamic>.from(u);
    } else {
      final hist = trip['history'];
      if (hist is Map) {
        final dr = hist['driver'];
        if (dr is Map) {
          driverMap = Map<String, dynamic>.from(dr);
          final u = dr['user'];
          if (u is Map) userMap = Map<String, dynamic>.from(u);
        }
      }
    }

    final dPhoto = driverMap?['driver_photo_url']?.toString() ??
        driverMap?['driverPhotoUrl']?.toString();
    final cPhoto = driverMap?['car_photo_url']?.toString() ??
        driverMap?['carPhotoUrl']?.toString();
    final phone = userMap?['number']?.toString().trim() ?? '';
    final driverDetailsSubtitle =
        tripActiveStripDriverSubtitle(driverMap, userMap).trim();
    final fn = userMap?['firstName']?.toString() ?? '';
    final ln = userMap?['lastName']?.toString() ?? '';
    final name = ('$fn $ln').trim().isEmpty ? 'السائق' : ('$fn $ln').trim();
    final st = CustomerTripStatusHelpers.normTripStatus(trip);
    final title = CustomerTripStatusHelpers.customerActiveTripTitle(trip);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: TripBookingTheme.addressBoxDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: TripBookingTheme.navy,
            ),
          ),
          if (st != 'Pending') ...[
            const SizedBox(height: 12),
            DriverCustomerPreviewRow(
              dense: true,
              name: name,
              driverPhotoUrl: dPhoto,
              carPhotoUrl: cPhoto,
              subtitle:
                  driverDetailsSubtitle.isEmpty ? null : driverDetailsSubtitle,
            ),
          ],
          if (phone.isNotEmpty && st != 'Pending') ...[
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () {
                  if (onCallDriver != null) {
                    onCallDriver!(phone);
                  } else {
                    launchPhoneCall(phone);
                  }
                },
                icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                label: Text(
                  phone,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: TripBookingTheme.navy,
                  backgroundColor:
                      TripBookingTheme.amber.withValues(alpha: 0.18),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
