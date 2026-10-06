import 'package:shared_preferences/shared_preferences.dart';

class MyInfoPrefs {
  static void saveInfo({required String name, required String value}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(name, value);
  }

  static void deleteInfo({required String name}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.remove(name);
  }

  static Future<String?> getInfo({required String name}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    String? value = prefs.getString(name);
    return value;
  }

  static Future<bool> checkToken() async {
    String? token = await MyInfoPrefs.getInfo(name: 'token')??"";
    if (token.isNotEmpty) {
      return true;
    } else
      return true;
  }
}
