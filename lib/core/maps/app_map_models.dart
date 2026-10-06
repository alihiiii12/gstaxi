import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

enum AppMapMarkerKind {
  driver,
  taxi,
  passenger,
  pickup,
  destination,
  sos,
}

class AppMapMarker {
  const AppMapMarker({
    required this.id,
    required this.point,
    required this.kind,
    this.rotation = 0,
  });

  final String id;
  final LatLng point;
  final AppMapMarkerKind kind;
  final double rotation;
}

class AppMapPolyline {
  const AppMapPolyline({
    required this.id,
    required this.points,
    this.color = const Color(0xFF1E88E5),
    this.width = 7,
    this.alpha = 0.95,
    this.cased = true,
  });

  final String id;
  final List<LatLng> points;
  final Color color;
  final double width;
  final double alpha;

  /// إطار أبيض تحت المسار (شكل تنقّل MAPS.ME).
  final bool cased;
}

class AppMapOverlay {
  const AppMapOverlay({
    this.markers = const [],
    this.polylines = const [],
  });

  final List<AppMapMarker> markers;
  final List<AppMapPolyline> polylines;

  static const empty = AppMapOverlay();
}
