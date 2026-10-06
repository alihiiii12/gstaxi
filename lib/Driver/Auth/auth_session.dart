import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:flutter/widgets.dart';

import '../../core/constants/error_model.dart';
import '../../core/constants/snack_bar.dart';
import '../../core/services/push_notification_service.dart';
import '../../core/services/secure_auth_token.dart';
import '../Home/controller/driver_location_controller.dart';
import '../Home/service/driver_keepalive_service.dart';
import '../Home/view/driver_main_screen.dart';
import '../../Customer/view/customer_home_screen.dart';
import 'auth_api/auth_api.dart';
import 'model/user_model.dart';
import 'view/screen/change_password.dart';
import 'view/screen/login_screen.dart';

/// حفظ جلسة الدخول والانتقال حسب الدور.
class AuthSession {
  AuthSession._();

  static bool isStaffRole(String? role) {
    final r = role?.trim() ?? '';
    return r == 'Admin' || r == 'Employee';
  }

  /// لوحة التحكم للأدمن/الموظف عبر الويب فقط — لا تُفتح من التطبيق.
  static Future<void> rejectStaffMobileAccess({
    String message =
        'لوحة التحكم متاحة عبر الويب فقط. سجّل الدخول من المتصفح.',
  }) async {
    try {
      await AuthApi.logoutRequest();
    } catch (_) {}
    await clearSessionOnly(keepLoginHint: true);
    Get.offAll(() => const LoginScreen());
    AppSnackBar.warning(message);
  }

  static Future<bool> completeLogin(UserResponseModel response) async {
    try {
      final data = response.data;
      if (data == null || data.token.isEmpty) {
        return false;
      }

      final role = data.roll;
      if (isStaffRole(role)) {
        await rejectStaffMobileAccess();
        return true;
      }

      final box = GetStorage();
      await SecureAuthToken.write(data.token);
      try {
        box.write('user_id', data.id);
        box.write('user_roll', data.roll);
        box.write('user_number', data.number);
        box.write('staff_permissions', data.permissions);
        box.write('change_password_needed', data.changePasswordNeeded);
        box.write(
          'session_validated_at',
          DateTime.now().millisecondsSinceEpoch,
        );
        if (data.driverId != null) {
          box.write('driver_id', data.driverId);
        } else {
          box.remove('driver_id');
        }
      } catch (e, st) {
        // ignore: avoid_print
        print('[AuthSession.completeLogin] storage: $e\n$st');
      }

      // لا ننتظر FCM — فشله لا يجب أن يوقف الدخول أو يسبب crash على iPad.
      Future<void>.microtask(() {
        try {
          // ignore: discarded_futures
          PushNotificationService.instance.registerTokenIfLoggedIn();
        } catch (_) {}
      });

      // الانتقال بعد استقرار الإطار — يمنع crash على iPad عند فتح الخريطة فوراً.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final goDriver = role == 'Driver';
      final needPw = data.changePasswordNeeded;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          try {
            if (goDriver) {
              if (needPw) {
                Get.offAll(() => const ChangePasswordScreen());
              } else {
                Get.offAll(() => const DriverHomeScreen());
              }
              return;
            }
            Get.offAll(() => const CustomerHomeScreen());
          } catch (e, st) {
            // ignore: avoid_print
            print('[AuthSession.navigate] $e\n$st');
          }
        });
      });
      return true;
    } catch (e, st) {
      // ignore: avoid_print
      print('[AuthSession.completeLogin] $e\n$st');
      return false;
    }
  }

  static void loginFailed() {
    AppSnackBar.error('فشل تسجيل الدخول: التوكين غير موجود في رد السيرفر');
  }

  /// خروج صريح فقط — لا يُستدعى عند إغلاق التطبيق أو الخلفية.
  static Future<void> signOut() async {
    if (Get.isRegistered<DriverController>()) {
      final dc = Get.find<DriverController>();
      if (dc.isOnline.value) {
        dc.setDriverAvailability(false);
      }
    }
    await DriverKeepaliveService.stop();
    try {
      await AuthApi.logoutRequest();
    } catch (_) {}
    await clearSessionOnly(keepLoginHint: true);
    Get.offAll(() => const LoginScreen());
  }

  /// مسح الجلسة (مثلاً عند 401 من الخادم).
  static Future<void> clearSessionOnly({bool keepLoginHint = false}) async {
    final box = GetStorage();
    final phone = keepLoginHint ? box.read<String>('user_number') : null;
    await SecureAuthToken.clear();
    await box.remove('user_id');
    await box.remove('driver_id');
    await box.remove('user_roll');
    await box.remove('staff_permissions');
    await box.remove('change_password_needed');
    await box.remove('session_validated_at');
    await box.remove('driver_online_pref');
    if (keepLoginHint && phone != null && phone.isNotEmpty) {
      await box.write('user_number', phone);
    } else {
      await box.remove('user_number');
    }
  }

  /// انتهت الجلسة (دخول من جهاز آخر أو توكن ملغى).
  static Future<void> handleSessionEnded({
    String message = 'انتهت جلستك. سجّل الدخول مرة أخرى.',
  }) async {
    if (Get.isRegistered<DriverController>()) {
      final dc = Get.find<DriverController>();
      if (dc.isOnline.value) {
        dc.setDriverAvailability(false);
      }
    }
    await clearSessionOnly(keepLoginHint: true);
    Get.offAll(() => const LoginScreen());
    AppSnackBar.error(message);
  }

  static bool isSessionConflict(ErrorModel error) =>
      error.statusCode == 409 || error.code == 'session_active_elsewhere';
}
