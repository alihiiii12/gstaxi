import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:latlong2/latlong.dart';

class FavoritePlace {
  const FavoritePlace({
    required this.id,
    required this.title,
    required this.point,
  });

  final String id;
  final String title;
  final LatLng point;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'lat': point.latitude,
        'lng': point.longitude,
      };

  factory FavoritePlace.fromJson(Map<String, dynamic> j) => FavoritePlace(
        id: j['id']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        point: LatLng(
          (j['lat'] as num?)?.toDouble() ?? 0,
          (j['lng'] as num?)?.toDouble() ?? 0,
        ),
      );
}

/// مفضلة مواقع (منزل / عمل / مواقف متكررة).
class FavoritePlacesService extends GetxController {
  static const _kKey = 'favorite_map_places_v1';

  final places = <FavoritePlace>[].obs;
  final _box = GetStorage();

  @override
  void onInit() {
    super.onInit();
    _load();
  }

  void _load() {
    final raw = _box.read(_kKey);
    if (raw is! List) return;
    final list = <FavoritePlace>[];
    for (final e in raw) {
      if (e is Map) {
        list.add(FavoritePlace.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    places.assignAll(list);
  }

  Future<void> _persist() async {
    await _box.write(_kKey, places.map((e) => e.toJson()).toList());
  }

  Future<void> add(String title, LatLng point) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    places.add(FavoritePlace(id: id, title: title, point: point));
    await _persist();
  }

  Future<void> remove(String id) async {
    places.removeWhere((e) => e.id == id);
    await _persist();
  }
}
