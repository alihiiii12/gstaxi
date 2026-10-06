import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../services/nominatim_reverse_geocode.dart';

/// صف «أيقونة + تسمية + قيمة» يُكمّل الاسم من Nominatim إن كانت القيمة فارغة أو شرطة.
class ResolvedPlaceLabelRow extends StatefulWidget {
  const ResolvedPlaceLabelRow({
    super.key,
    required this.icon,
    required this.label,
    required this.initialValue,
    required this.point,
    required this.iconColor,
  });

  final IconData icon;
  final String label;
  final String initialValue;
  final LatLng? point;
  final Color iconColor;

  @override
  State<ResolvedPlaceLabelRow> createState() => _ResolvedPlaceLabelRowState();
}

class _ResolvedPlaceLabelRowState extends State<ResolvedPlaceLabelRow> {
  late String _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue;
    _maybeResolve();
  }

  @override
  void didUpdateWidget(covariant ResolvedPlaceLabelRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue ||
        oldWidget.point?.latitude != widget.point?.latitude ||
        oldWidget.point?.longitude != widget.point?.longitude) {
      _value = widget.initialValue;
      _maybeResolve();
    }
  }

  Future<void> _maybeResolve() async {
    final pt = widget.point;
    if (pt == null || !looksLikeMissingPlaceLabel(_value)) return;
    final resolved = await NominatimReverseGeocode.displayNameForLatLng(
      pt.latitude,
      pt.longitude,
    );
    if (!mounted) return;
    if (resolved != null && resolved.isNotEmpty) {
      setState(() => _value = resolved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(widget.icon, size: 18, color: widget.iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.label,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
              Text(
                _value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
