import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

/// طبقة خريطة: نهار / ليل (مثل MAPS.ME).
class MapThemeController extends GetxController {
  static const _kNight = 'map_night_mode';

  final nightMode = false.obs;
  final _box = GetStorage();

  @override
  void onInit() {
    super.onInit();
    nightMode.value = _box.read(_kNight) == true;
  }

  Future<void> setNightMode(bool value) async {
    nightMode.value = value;
    await _box.write(_kNight, value);
  }

  Future<void> toggle() => setNightMode(!nightMode.value);
}
