import 'package:flutter/material.dart';

import '../../../../core/constants/app_button_dims.dart';
import '../../../../core/constants/app_sizes.dart';

/// ألوان وعناصر مشتركة لشاشات تسجيل الدخول / التسجيل / OTP (مطابقة التصميم).
class AuthUi {
  AuthUi._();

  static const Color primaryYellow = Color(0xFFFFC107);
  static const Color darkCharcoal = Color(0xFF212121);
  static const Color navy = Color(0xFF11215B);

  static const BoxDecoration gradient = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color(0xFFFFD54F),
        Color(0xFFFFC107),
        Color(0xFFFFA000),
      ],
    ),
  );

  static Widget backButton(VoidCallback onTap) {
    return Align(
      alignment: Alignment.centerRight,
      child: IconButton(
        icon: const Icon(Icons.arrow_forward_ios_rounded, color: navy),
        onPressed: onTap,
      ),
    );
  }

  static Widget primaryButton({
    required String label,
    required VoidCallback? onTap,
    bool loading = false,
  }) {
    final h = AppButtonDims.heightLg;
    final r = AppButtonDims.radius + 4;
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: double.infinity,
        height: h,
        decoration: BoxDecoration(
          color: darkCharcoal,
          borderRadius: BorderRadius.circular(r),
          boxShadow: [
            BoxShadow(
              color: darkCharcoal.withValues(alpha: 0.3),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: loading
              ? SizedBox(
                  width: AppSizes.w(24),
                  height: AppSizes.w(24),
                  child: const CircularProgressIndicator(
                    color: primaryYellow,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    color: primaryYellow,
                    fontSize: AppSizes.sp(17),
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }

  /// حقل هاتف سوري (+963 / 09xxxxxxxx).
  static Widget syrianPhoneField({
    required TextEditingController controller,
    String hint = '09xxxxxxxx',
  }) {
    return textField(
      controller: controller,
      hint: hint,
      icon: Icons.phone_android_rounded,
      keyboardType: TextInputType.phone,
      prefixLabel: dialCodeSyria,
    );
  }

  static const String dialCodeSyria = '+963';

  static Widget textField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    bool obscureVisible = false,
    VoidCallback? onToggleObscure,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? prefixLabel,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        textAlign: TextAlign.right,
        textDirection: TextDirection.rtl,
        obscureText: obscure && !obscureVisible,
        keyboardType: keyboardType,
        maxLines: maxLines,
        style: const TextStyle(
          color: navy,
          fontWeight: FontWeight.bold,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: navy.withValues(alpha: 0.45),
            fontSize: 15,
          ),
          suffixIcon: Icon(icon, color: navy, size: 24),
          prefixText: prefixLabel != null ? ' $prefixLabel ' : null,
          prefixStyle: const TextStyle(
            color: navy,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
          prefixIcon: obscure
              ? IconButton(
                  icon: Icon(
                    obscureVisible ? Icons.visibility : Icons.visibility_off,
                    color: navy.withValues(alpha: 0.45),
                    size: 20,
                  ),
                  onPressed: onToggleObscure,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 18,
            horizontal: 20,
          ),
        ),
      ),
    );
  }

  static Widget linkRow({
    required String prefix,
    required String action,
    required VoidCallback onTap,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(prefix, style: TextStyle(color: navy.withValues(alpha: 0.85))),
        TextButton(
          onPressed: onTap,
          child: Text(
            action,
            style: const TextStyle(
              color: navy,
              fontWeight: FontWeight.bold,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

}
