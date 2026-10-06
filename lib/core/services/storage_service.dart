import 'package:get_storage/get_storage.dart';

import 'secure_auth_token.dart';

class StorageService {
  StorageService._();

  static final GetStorage _box = GetStorage();

  /// =========================
  /// INIT
  /// =========================
  static Future<void> init() async {
    await GetStorage.init();
  }

  /// =========================
  /// AUTH
  /// =========================
  static String? get token => SecureAuthToken.value;

  static bool get isLoggedIn =>
      token != null && token!.isNotEmpty;

  static Future<void> saveToken(String token) async {
    await SecureAuthToken.write(token);
  }

  static Future<void> removeToken() async {
    await SecureAuthToken.clear();
  }

  /// =========================
  /// USER INFO
  /// =========================
  static int? get userId => _box.read('user_id');
  static String? get userName => _box.read('user_name');
  static String? get userEmail => _box.read('user_email');

  static Future<void> saveUserInfo({
    required int id,
    required String name,
    required String email,
  }) async {
    await _box.write('user_id', id);
    await _box.write('user_name', name);
    await _box.write('user_email', email);
  }

  static Future<void> clearUserInfo() async {
    await _box.remove('user_id');
    await _box.remove('user_name');
    await _box.remove('user_email');
  }

  /// =========================
  /// LANGUAGE
  /// =========================
  static String get language =>
      _box.read('language') ?? 'ar';

  static Future<void> setLanguage(String lang) async {
    await _box.write('language', lang);
  }

  /// =========================
  /// CURRENCY
  /// =========================
  static String get currency =>
      _box.read('currency') ?? 'USD';

  static Future<void> setCurrency(String value) async {
    await _box.write('currency', value);
  }

  /// =========================
  /// THEME
  /// =========================
  static String get themeMode =>
      _box.read('theme_mode') ?? 'light';

  static Future<void> setThemeMode(String value) async {
    await _box.write('theme_mode', value);
  }

  /// =========================
  /// APP STATE
  /// =========================
  static bool get isFirstOpen =>
      _box.read('first_open') ?? true;

  static Future<void> setFirstOpenFalse() async {
    await _box.write('first_open', false);
  }

  /// =========================
  /// LOGOUT
  /// =========================
  static Future<void> logout() async {
    await _box.erase();
  }
}
