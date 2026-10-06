import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:latlong2/latlong.dart';

class RecentDestination {
  const RecentDestination({
    required this.title,
    required this.point,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final LatLng point;

  Map<String, dynamic> toJson() => {
        'title': title,
        'subtitle': subtitle,
        'lat': point.latitude,
        'lng': point.longitude,
      };

  factory RecentDestination.fromJson(Map<String, dynamic> j) =>
      RecentDestination(
        title: j['title']?.toString() ?? '',
        subtitle: j['subtitle']?.toString() ?? '',
        point: LatLng(
          (j['lat'] as num?)?.toDouble() ?? 0,
          (j['lng'] as num?)?.toDouble() ?? 0,
        ),
      );
}

/// سجل آخر الوجهات المختارة (راكب + سائق).
class RecentDestinationsService extends GetxController {
  static const _kKey = 'recent_destinations_v1';
  static const _maxItems = 10;

  final items = <RecentDestination>[].obs;
  final _box = GetStorage();

  static RecentDestinationsService ensure() {
    if (Get.isRegistered<RecentDestinationsService>()) {
      return Get.find<RecentDestinationsService>();
    }
    return Get.put(RecentDestinationsService(), permanent: true);
  }

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    final raw = _box.read(_kKey);
    if (raw is! List) return;
    final list = <RecentDestination>[];
    for (final e in raw) {
      if (e is Map) {
        final item = RecentDestination.fromJson(Map<String, dynamic>.from(e));
        if (item.title.trim().isNotEmpty &&
            item.point.latitude.abs() > 0.01) {
          list.add(item);
        }
      }
    }
    items.assignAll(list);
  }

  Future<void> _persist() async {
    await _box.write(_kKey, items.map((e) => e.toJson()).toList());
  }

  Future<void> add({
    required String title,
    required LatLng point,
    String subtitle = '',
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) return;
    if (point.latitude.abs() < 0.01 && point.longitude.abs() < 0.01) return;

    items.removeWhere(
      (e) =>
          e.title == cleanTitle ||
          ((e.point.latitude - point.latitude).abs() < 1e-4 &&
              (e.point.longitude - point.longitude).abs() < 1e-4),
    );
    items.insert(
      0,
      RecentDestination(
        title: cleanTitle,
        subtitle: subtitle.trim(),
        point: point,
      ),
    );
    if (items.length > _maxItems) {
      items.removeRange(_maxItems, items.length);
    }
    await _persist();
  }

  Future<void> clear() async {
    items.clear();
    await _persist();
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    await _persist();
  }
}
