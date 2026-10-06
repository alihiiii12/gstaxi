import 'package:latlong2/latlong.dart';

/// مركز افتراضي (دمشق) عند عدم توفر GPS صالح.
const LatLng kDefaultMapCenter = LatLng(33.5138, 36.2765);

bool isFiniteLatLng(LatLng? p) {
  if (p == null) return false;
  return p.latitude.isFinite &&
      p.longitude.isFinite &&
      p.latitude >= -90 &&
      p.latitude <= 90 &&
      p.longitude >= -180 &&
      p.longitude <= 180;
}

LatLng safeLatLng(
  double? lat,
  double? lng, {
  LatLng fallback = kDefaultMapCenter,
}) {
  if (lat != null &&
      lng != null &&
      lat.isFinite &&
      lng.isFinite &&
      lat >= -90 &&
      lat <= 90 &&
      lng >= -180 &&
      lng <= 180) {
    return LatLng(lat, lng);
  }
  return fallback;
}

LatLng safeLatLngFrom(LatLng? p, {LatLng fallback = kDefaultMapCenter}) {
  if (isFiniteLatLng(p)) return p!;
  return fallback;
}
