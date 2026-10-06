import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/maps/app_map_controller.dart';
import '../../../core/utils/osrm_route_client.dart';

Future<void> showCustomerRequestRouteMapDialog(
  BuildContext context, {
  required LatLng? pickup,
  required LatLng? destination,
  String pickupName = '',
  String destinationName = '',
  int? requestId,
}) async {
  if (pickup == null && destination == null) return;
  final from = pickup ?? destination!;
  final to = destination ?? pickup!;
  await showDialog<void>(
    context: context,
    builder: (_) => _CustomerRequestRouteMapDialog(
      from: from,
      to: to,
      title: requestId != null ? 'مسار الطلب #$requestId' : 'مسار الطلب',
      pickupName: pickupName,
      destinationName: destinationName,
    ),
  );
}

class _CustomerRequestRouteMapDialog extends StatefulWidget {
  const _CustomerRequestRouteMapDialog({
    required this.from,
    required this.to,
    required this.title,
    this.pickupName = '',
    this.destinationName = '',
  });

  final LatLng from;
  final LatLng to;
  final String title;
  final String pickupName;
  final String destinationName;

  @override
  State<_CustomerRequestRouteMapDialog> createState() =>
      _CustomerRequestRouteMapDialogState();
}

class _CustomerRequestRouteMapDialogState
    extends State<_CustomerRequestRouteMapDialog> {
  final AppMapController _controller = AppMapController();
  AppMapOverlay _overlay = AppMapOverlay.empty;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pts = await OsrmRouteClient.fetchRoutePoints(widget.from, widget.to);
    final line = (pts != null && pts.length >= 2)
        ? pts
        : [widget.from, widget.to];
    if (!mounted) return;
    setState(() {
      _loading = false;
      _overlay = AppMapOverlay(
        markers: [
          AppMapMarker(
            id: 'from',
            point: widget.from,
            kind: AppMapMarkerKind.pickup,
          ),
          AppMapMarker(
            id: 'to',
            point: widget.to,
            kind: AppMapMarkerKind.destination,
          ),
        ],
        polylines: [
          AppMapPolyline(id: 'route', points: line, width: 6),
        ],
      );
    });
    await _controller.fitPoints(line, padding: 40);
  }

  @override
  void dispose() {
    _controller.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 340,
        height: 320,
        child: Column(
          children: [
            if (widget.pickupName.isNotEmpty || widget.destinationName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${widget.pickupName.isEmpty ? 'الانطلاق' : widget.pickupName}'
                  ' → '
                  '${widget.destinationName.isEmpty ? 'الوجهة' : widget.destinationName}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: AppMapView(
                      controller: _controller,
                      initialCenter: widget.from,
                      initialZoom: 13,
                      overlay: _overlay,
                    ),
                  ),
                  if (_loading)
                    const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إغلاق'),
        ),
      ],
    );
  }
}
