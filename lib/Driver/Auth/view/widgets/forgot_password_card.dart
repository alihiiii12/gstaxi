import 'package:flutter/material.dart';

import '../../auth_api/auth_api.dart';
import '../../../../core/constants/snack_bar.dart';
import '../../../../core/utils/syrian_phone.dart';
import 'auth_form_ui.dart';

class ForgotPasswordCard extends StatefulWidget {
  const ForgotPasswordCard({
    super.key,
    required this.onBackToLogin,
    required this.onOtpRequired,
  });

  final VoidCallback onBackToLogin;

  /// يُنادى بعد إرسال الرمز لينقلب الكرت إلى بطاقة التحقق.
  final void Function(String phone) onOtpRequired;

  @override
  State<ForgotPasswordCard> createState() => _ForgotPasswordCardState();
}

class _ForgotPasswordCardState extends State<ForgotPasswordCard> {
  final _phoneC = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneC.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final phone = SyrianPhone.normalize(_phoneC.text.trim());
    if (!SyrianPhone.isValid(phone)) {
      AppSnackBar.error('أدخل رقم سوري صحيح (09xxxxxxxx)');
      return;
    }

    setState(() => _loading = true);
    final result = await AuthApi.forgotPassword(number: phone);
    if (!mounted) return;
    setState(() => _loading = false);

    result.fold(
      (e) => AppSnackBar.error(e.message),
      (map) {
        widget.onOtpRequired(phone);
        AppSnackBar.success('تم إرسال رمز التحقق عبر SMS');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      children: [
        const AuthCardTitle(
          title: 'نسيت كلمة المرور',
          subtitle: 'أدخل رقم هاتفك وسنرسل رمز التحقق عبر SMS',
        ),
        AuthField(
          controller: _phoneC,
          hint: '09xxxxxxxx',
          icon: Icons.phone_android_rounded,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        AuthGradientButton(
          label: 'إرسال رمز التأكيد',
          loading: _loading,
          onTap: _sendCode,
        ),
        const SizedBox(height: 10),
        AuthLinkRow(
          prefix: 'تذكرت كلمة المرور؟',
          action: 'تسجيل الدخول',
          onTap: widget.onBackToLogin,
        ),
      ],
    );
  }
}
