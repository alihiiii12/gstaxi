import 'package:latlong2/latlong.dart';

/// محطة/وجهة ضمن مسار متعدد (مرتّبة من الأولى للأخيرة).
class TripStop {
  const TripStop({
    required this.point,
    required this.label,
  });

  final LatLng point;
  final String label;

  Map<String, dynamic> toJson() => {
        'lat': point.latitude,
        'lng': point.longitude,
        'name': label,
      };

  static TripStop? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final lat = (m['lat'] ?? m['latitude']) as num?;
    final lng = (m['lng'] ?? m['longitude']) as num?;
    if (lat == null || lng == null) return null;
    final name = (m['name'] ?? m['label'] ?? '').toString().trim();
    return TripStop(
      point: LatLng(lat.toDouble(), lng.toDouble()),
      label: name.isEmpty ? 'وجهة' : name,
    );
  }

  static List<TripStop> listFromJson(dynamic raw) {
    if (raw is! List) return const [];
    final out = <TripStop>[];
    for (final e in raw) {
      final s = fromJson(e);
      if (s != null) out.add(s);
    }
    return out;
  }

  /// عرض المسار: التل ← المزة ← التل
  static String routeLabel(List<TripStop> stops) {
    if (stops.isEmpty) return '';
    return stops.map((s) => s.label).join(' ← ');
  }
}
