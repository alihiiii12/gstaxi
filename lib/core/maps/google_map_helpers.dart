import 'dart:ui' show Color, Offset;

import 'package:flutter/material.dart' show VoidCallback;
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart' as ll;

export 'map_marker_icons.dart';

/// مساعدات Google Maps للشاشات التي ما زالت تستخدمه (أدمن / مراجعة).
gmaps.LatLng googleLatLngFrom(ll.LatLng p) =>
    gmaps.LatLng(p.latitude, p.longitude);

ll.LatLng latLngFromGoogle(gmaps.LatLng p) =>
    ll.LatLng(p.latitude, p.longitude);

gmaps.Marker gmapsMarker({
  required String id,
  required ll.LatLng point,
  required gmaps.BitmapDescriptor icon,
  double anchorX = 0.5,
  double anchorY = 0.5,
  VoidCallback? onTap,
}) {
  return gmaps.Marker(
    markerId: gmaps.MarkerId(id),
    position: googleLatLngFrom(point),
    icon: icon,
    anchor: Offset(anchorX, anchorY),
    onTap: onTap,
  );
}

gmaps.Polyline gmapsPolyline({
  required String id,
  required List<ll.LatLng> points,
  Color color = const Color(0xFF11215B),
  double width = 5,
  double alpha = 1.0,
}) {
  return gmaps.Polyline(
    polylineId: gmaps.PolylineId(id),
    points: points.map(googleLatLngFrom).toList(),
    color: color.withValues(alpha: alpha),
    width: width.toInt(),
  );
}
