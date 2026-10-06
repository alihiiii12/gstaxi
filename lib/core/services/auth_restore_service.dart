import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

import '../../Customer/view/customer_home_screen.dart';
import '../../Driver/Auth/auth_session.dart';
import '../../Driver/Auth/view/screen/change_password.dart';
import '../../Driver/Auth/view/screen/login_screen.dart';
import '../../Driver/Home/view/driver_main_screen.dart';
import '../network/api_endpoints.dart';
import 'secure_auth_token.dart';

/// استعادة جلسة الدخول محلياً — بدون إجبار المستخدم على تسجيل الدخول عند كل فتح للتطبيق.
class AuthRestoreService {
  AuthRestoreService._();

  static const _validatedAtKey = 'session_validated_at';
  static const _minValidationGapMs = 60 * 60 * 1000; // ساعة — تقليل ضغط /user

  static GetStorage get _box => GetStorage();

  static bool get hasSession {
    final token = SecureAuthToken.value;
    return token != null && token.trim().isNotEmpty;
  }

  static String? get storedRole => _box.read<String>('user_roll')?.trim();

  /// عند فتح التطبيق: انتقل للشاشة المناسبة من التخزين المحلي فوراً.
  /// عند عدم وجود جلسة يُفضّل الانتقال من [SplashScreen] عبر Hero.
  static void restoreAndNavigate() {
    if (!hasSession) {
      Get.offAll(() => const LoginScreen(fromSplash: false));
      return;
    }

    final roll = storedRole;
    if (roll == null || roll.isEmpty) {
      Get.offAll(() => const CustomerHomeScreen());
      _refreshProfileInBackground(force: true);
      return;
    }

    _navigateForRole(roll);
    _refreshProfileInBackground();
  }

  static void _navigateForRole(String roll) {
    final needsPwd = _box.read('change_password_needed') == true;
    if (roll == 'Driver') {
      Get.offAll(
        () => needsPwd ? const ChangePasswordScreen() : DriverHomeScreen(),
      );
      return;
    }
    if (AuthSession.isStaffRole(roll)) {
      // جلسة أدمن قديمة في التطبيق — أخرج إلى تسجيل الدخول (الويب فقط).
      // ignore: discarded_futures
      AuthSession.rejectStaffMobileAccess();
      return;
    }
    Get.offAll(() => const CustomerHomeScreen());
  }

  /// تحديث بيانات المستخدم من الخادم — لا يُخرج المستخدم إلا عند 401 صريح.
  static Future<void> _refreshProfileInBackground({bool force = false}) async {
    if (!hasSession) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final last = _box.read<int>(_validatedAtKey) ?? 0;
    if (!force && now - last < _minValidationGapMs) return;

    try {
      final token = (SecureAuthToken.value ?? '').trim();
      if (token.isEmpty) return;
      final res = await http
          .get(
            Uri.parse(ApiEndpoints.currentUser),
            headers: {
              'Accept': 'application/json',
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 401) {
        await AuthSession.handleSessionEnded(
          message: 'تم تسجيل الدخول من جهاز آخر أو انتهت الجلسة.',
        );
        return;
      }

      if (res.statusCode != 200) return;

      final jsonBody = json.decode(res.body);
      if (jsonBody is! Map<String, dynamic>) return;

      final roll = (jsonBody['roll'] ?? jsonBody['Roll'] ?? '').toString();
      if (roll.isNotEmpty) {
        _box.write('user_roll', roll);
        if (AuthSession.isStaffRole(roll)) {
          await AuthSession.rejectStaffMobileAccess();
          return;
        }
      }

      final perms = jsonBody['permissions'];
      if (perms is List) {
        _box.write(
          'staff_permissions',
          perms.map((e) => e.toString()).toList(),
        );
      }

      final driverId = jsonBody['driverId'] ?? jsonBody['driver_id'];
      if (driverId != null) {
        _box.write('driver_id', driverId);
      }

      _box.write(_validatedAtKey, now);
    } catch (_) {
      // شبكة/503 — نُبقي الجلسة المحلية
    }
  }
}
