import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controller/auth_controller.dart';
import 'auth_form_ui.dart';

class LoginCard extends StatelessWidget {
  const LoginCard({
    super.key,
    required this.onForgotPassword,
    required this.onCreateAccount,
  });

  final VoidCallback onForgotPassword;
  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(DriverAuthController());

    return AuthCard(
      children: [
        AuthField(
          controller: controller.numberC,
          hint: 'رقم الهاتف أو الاسم',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.text,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: controller.passwordC,
          hint: 'كلمة المرور',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => controller.login(),
        ),
        const SizedBox(height: 16),
        Obx(
          () => AuthGradientButton(
            label: 'تسجيل الدخول',
            loading: controller.isLoading.value,
            onTap: controller.login,
          ),
        ),
        const SizedBox(height: 6),
        AuthTextLink(
          label: 'نسيت كلمة المرور؟',
          onTap: onForgotPassword,
        ),
        AuthLinkRow(
          prefix: 'ليس لديك حساب؟',
          action: 'إنشاء حساب',
          onTap: onCreateAccount,
        ),
      ],
    );
  }
}
