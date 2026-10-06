import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../widgets/auth_scene.dart';
import '../widgets/reset_password_card.dart';
import 'login_screen.dart';

/// شاشة كلمة المرور الجديدة كصفحة مستقلة (خارج تدفّق بطاقات الدخول).
class ResetPasswordScreen extends StatelessWidget {
  const ResetPasswordScreen({
    super.key,
    required this.phoneNumber,
    required this.resetToken,
  });

  final String phoneNumber;
  final String resetToken;

  @override
  Widget build(BuildContext context) {
    return AuthScene(
      onBack: () => Get.back(),
      card: ResetPasswordCard(
        phoneNumber: phoneNumber,
        resetToken: resetToken,
        onDone: () => Get.offAll(() => const LoginScreen()),
      ),
    );
  }
}
