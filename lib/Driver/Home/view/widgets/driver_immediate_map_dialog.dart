import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../../../core/maps/app_map_controller.dart';

/// خريطة منبثقة: موقع السائق + موقع الراكب (نقطة الانطلاق).
Future<void> showDriverImmediateMapDialog(
  BuildContext context, {
  required ll.LatLng driverPoint,
  required ll.LatLng? pickupPoint,
  required String passengerName,
  required String pickupLabel,
  int? requestId,
}) async {
  final pickup = pickupPoint ?? driverPoint;
  final controller = AppMapController();
  final overlay = AppMapOverlay(
    markers: [
      AppMapMarker(
        id: 'driver',
        point: driverPoint,
        kind: AppMapMarkerKind.taxi,
      ),
      AppMapMarker(
        id: 'pickup',
        point: pickup,
        kind: AppMapMarkerKind.passenger,
      ),
    ],
    polylines: [
      AppMapPolyline(
        id: 'line',
        points: [driverPoint, pickup],
        color: Colors.blue.shade700,
        width: 4,
      ),
    ],
  );

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(passengerName),
        content: SizedBox(
          width: 320,
          height: 280,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AppMapView(
              controller: controller,
              initialCenter: pickup,
              initialZoom: 14,
              overlay: overlay,
              onMapReady: () {
                controller.fitPoints([driverPoint, pickup], padding: 40);
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      );
    },
  );
  controller.detach();
}
