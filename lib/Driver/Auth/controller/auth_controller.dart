import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../../core/base/base_controller.dart';
import '../../../core/constants/snack_bar.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/services/secure_auth_token.dart';
import '../../../core/services/app_update_gate.dart';
import '../auth_api/auth_api.dart';
import '../auth_session.dart';
import '../subscription_auth.dart';
import '../../../core/utils/syrian_phone.dart';
import '../model/auth_otp_purpose.dart';
import '../view/screen/otp_verify_screen.dart';
import '../../Home/view/driver_main_screen.dart';
import '../../../Customer/view/customer_home_screen.dart';

class DriverAuthController extends BaseController {
  // حقول السائق
  final numberC = TextEditingController();
  final passwordC = TextEditingController();
  final newPasswordC = TextEditingController(); // لتغيير كلمة السر لاحقاً
  final  passwordController = TextEditingController();

  RxString token = "".obs;
  static String? savedToken;
  bool _loginInFlight = false;

  @override
  void onInit() {
    super.onInit();
    final box = GetStorage();
    token.value = SecureAuthToken.value ?? '';
    final savedNumber = box.read<String>('user_number');
    if (savedNumber != null && savedNumber.isNotEmpty) {
      numberC.text = savedNumber;
    }
  }

  Future<void> login() async {
    if (_loginInFlight || isLoading.value) return;

    if (numberC.text.trim().isEmpty || passwordC.text.isEmpty) {
      AppSnackBar.error("يرجى إدخال رقم الهاتف وكلمة المرور");
      return;
    }

    _loginInFlight = true;
    startLoading();

    final phone = SyrianPhone.normalize(numberC.text.trim());
    final fcm = GetStorage().read<String>('fcm_token');

    if (kDebugMode) {
      debugPrint('[Auth] login → ${ApiEndpoints.login} number=$phone');
    }

    try {
      final result = await AuthApi.login(
        number: phone,
        password: passwordC.text,
        fcmToken: fcm,
      );

      await result.fold(
        (error) async {
          if (kDebugMode) {
            debugPrint(
              '[Auth] login failed ${error.statusCode} code=${error.code} msg=${error.message}',
            );
          }
          if (error.code == 'update_required' ||
              error.statusCode == 426 ||
              (error.downloadUrl != null &&
                  error.downloadUrl!.trim().isNotEmpty)) {
            await AppUpdateGate.showFromLoginError(
              message: error.message,
              downloadUrl: error.downloadUrl,
              code: error.code,
            );
            return;
          }
          if (AuthSession.isSessionConflict(error)) {
            AppSnackBar.error(error.message);
            return;
          }
          if (isDriverSubscriptionBlocked(error)) {
            AppSnackBar.error(driverSubscriptionBlockedMessage(error));
            return;
          }
          if (error.statusCode == 403 &&
              (error.code == 'phone_not_verified' ||
                  error.message.contains('تأكيد'))) {
            Get.to(
              () => OtpVerifyScreen(
                phoneNumber: phone,
                purpose: AuthOtpPurpose.register,
                password: passwordC.text,
              ),
            );
            return;
          }
          AppSnackBar.error(error.message);
        },
        (success) async {
          if (kDebugMode) {
            debugPrint('[Auth] login ok roll=${success.data?.roll}');
          }
          if (!await AuthSession.completeLogin(success)) {
            AuthSession.loginFailed();
          }
        },
      );
    } finally {
      _loginInFlight = false;
      stopLoading();
    }
  }

  void submitPassword() async {

    if (passwordController.text.length < 6) {
      AppSnackBar.error("كلمة السر يجب أن تكون 6 أحرف على الأقل");
      return;
    }
    if (passwordController.text.isEmpty) {
      AppSnackBar.error("يرجى إدخال كلمة سر جديدة");
      return;
    }
    final box = GetStorage();
    final token = SecureAuthToken.value ?? '';

    if (token.isEmpty) {
      AppSnackBar.error("خطأ: التوكين غير موجود. يرجى تسجيل الدخول.");
      return;
    }

    isLoading.value = true;

    var response = await AuthApi.updatepassword(
      password: passwordController.text,
      token: token,
    );

    isLoading.value = false;

    if (response.statusCode == 200) {
      AppSnackBar.success("تم تغيير كلمة السر بنجاح");
      box.write('change_password_needed', false);
      final roll = box.read('user_roll')?.toString() ?? '';
      if (AuthSession.isStaffRole(roll)) {
        await AuthSession.rejectStaffMobileAccess();
      } else if (roll == 'Driver') {
        Get.offAll(() => DriverHomeScreen());
      } else {
        Get.offAll(() => const CustomerHomeScreen());
      }
    } else {
      AppSnackBar.error("فشل التغيير: ${response.statusCode}");
    }
  }



  @override
  void onClose() {
    numberC.dispose();
    passwordC.dispose();
    newPasswordC.dispose();
    super.onClose();
  }
}