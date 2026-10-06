import 'package:flutter/material.dart';

import '../../auth_api/auth_api.dart';
import '../../../../core/constants/snack_bar.dart';
import '../../../../core/utils/syrian_phone.dart';
import 'auth_form_ui.dart';

class RegisterCard extends StatefulWidget {
  const RegisterCard({
    super.key,
    required this.onBackToLogin,
    required this.onOtpRequired,
  });

  final VoidCallback onBackToLogin;

  /// يُنادى بعد إرسال الرمز لينقلب الكرت إلى بطاقة التحقق.
  final void Function(String phone, String password) onOtpRequired;

  @override
  State<RegisterCard> createState() => _RegisterCardState();
}

class _RegisterCardState extends State<RegisterCard> {
  final _fullNameC = TextEditingController();
  final _phoneC = TextEditingController();
  final _passC = TextEditingController();
  final _confirmC = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _fullNameC.dispose();
    _phoneC.dispose();
    _passC.dispose();
    _confirmC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _fullNameC.text.trim();
    final phone = SyrianPhone.normalize(_phoneC.text.trim());
    final pass = _passC.text;
    final confirm = _confirmC.text;

    if (name.length < 3) {
      AppSnackBar.error('أدخل الاسم الثلاثي');
      return;
    }
    if (!SyrianPhone.isValid(phone)) {
      AppSnackBar.error('أدخل رقم سوري صحيح (09xxxxxxxx)');
      return;
    }
    if (pass.length < 6) {
      AppSnackBar.error('كلمة المرور 6 أحرف على الأقل');
      return;
    }
    if (pass != confirm) {
      AppSnackBar.error('تأكيد كلمة المرور غير متطابق');
      return;
    }

    setState(() => _loading = true);
    final result = await AuthApi.registerCustomer(
      fullName: name,
      number: phone,
      password: pass,
      passwordConfirmation: confirm,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    result.fold(
      (e) => AppSnackBar.error(e.message),
      (map) {
        widget.onOtpRequired(phone, pass);
        AppSnackBar.success('تم إرسال رمز التحقق عبر SMS');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      children: [
        const AuthCardTitle(title: 'إنشاء حساب جديد'),
        AuthField(
          controller: _fullNameC,
          hint: 'الاسم الثلاثي',
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: _phoneC,
          hint: '09xxxxxxxx',
          icon: Icons.phone_android_rounded,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: _passC,
          hint: 'كلمة المرور',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: _confirmC,
          hint: 'تأكيد كلمة المرور',
          icon: Icons.lock_reset_rounded,
          isPassword: true,
        ),
        const SizedBox(height: 16),
        AuthGradientButton(
          label: 'إنشاء الحساب',
          loading: _loading,
          onTap: _submit,
        ),
        const SizedBox(height: 10),
        AuthLinkRow(
          prefix: 'لديك حساب بالفعل؟',
          action: 'تسجيل الدخول',
          onTap: widget.onBackToLogin,
        ),
      ],
    );
  }
}
