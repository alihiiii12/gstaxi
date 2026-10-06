import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../model/auth_otp_purpose.dart';
import '../widgets/auth_scene.dart';
import '../widgets/otp_verify_card.dart';

/// شاشة التحقق كصفحة مستقلة — تُستخدم عندما يُطلب التحقق من خارج شاشة الدخول.
class OtpVerifyScreen extends StatelessWidget {
  const OtpVerifyScreen({
    super.key,
    required this.phoneNumber,
    required this.purpose,
    this.password,
  });

  final String phoneNumber;
  final AuthOtpPurpose purpose;

  /// كلمة المرور (بعد التسجيل) — احتياطي إذا لم يُرجع السيرفر توكناً.
  final String? password;

  @override
  Widget build(BuildContext context) {
    return AuthScene(
      onBack: () => Get.back(),
      card: OtpVerifyCard(
        phoneNumber: phoneNumber,
        purpose: purpose,
        password: password,
        onBackToLogin: () => Get.back(),
      ),
    );
  }
}
