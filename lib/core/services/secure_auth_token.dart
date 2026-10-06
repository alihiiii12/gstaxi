import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_storage/get_storage.dart';

/// تخزين توكن المصادقة في Android Keystore / التخزين الآمن (VUL-11).
class SecureAuthToken {
  SecureAuthToken._();

  static const _key = 'auth_bearer_token';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static String? _cache;

  static String? get value => _cache;

  static Future<void> init() async {
    try {
      _cache = await _storage.read(key: _key);
    } catch (_) {
      _cache = null;
    }

    // ترحيل من GetStorage إن وُجد توكن قديم.
    final legacy = GetStorage().read('token');
    if ((_cache == null || _cache!.isEmpty) &&
        legacy is String &&
        legacy.trim().isNotEmpty) {
      await write(legacy.trim());
      await GetStorage().remove('token');
    } else if (_cache != null && _cache!.isNotEmpty) {
      await GetStorage().remove('token');
    }
  }

  static Future<void> write(String token) async {
    _cache = token;
    try {
      await _storage.write(key: _key, value: token);
    } catch (_) {}
    // لا تُخزَّن في GetStorage بعد الآن.
    await GetStorage().remove('token');
  }

  static Future<void> clear() async {
    _cache = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {}
    await GetStorage().remove('token');
  }
}
