import 'package:flutter/material.dart';

import '../../auth_api/auth_api.dart';
import '../../../../core/constants/snack_bar.dart';
import 'auth_form_ui.dart';

class ResetPasswordCard extends StatefulWidget {
  const ResetPasswordCard({
    super.key,
    required this.phoneNumber,
    required this.resetToken,
    required this.onDone,
  });

  final String phoneNumber;
  final String resetToken;

  /// يُنادى بعد نجاح التغيير للعودة إلى بطاقة تسجيل الدخول.
  final VoidCallback onDone;

  @override
  State<ResetPasswordCard> createState() => _ResetPasswordCardState();
}

class _ResetPasswordCardState extends State<ResetPasswordCard> {
  final _passC = TextEditingController();
  final _confirmC = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _passC.dispose();
    _confirmC.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _passC.text;
    final confirm = _confirmC.text;
    if (pass.length < 6) {
      AppSnackBar.error('كلمة المرور 6 أحرف على الأقل');
      return;
    }
    if (pass != confirm) {
      AppSnackBar.error('تأكيد كلمة المرور غير متطابق');
      return;
    }

    setState(() => _loading = true);
    final result = await AuthApi.resetPasswordAfterOtp(
      number: widget.phoneNumber,
      resetToken: widget.resetToken,
      password: pass,
      passwordConfirmation: confirm,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    result.fold(
      (e) => AppSnackBar.error(e.message),
      (_) {
        AppSnackBar.success('تم تغيير كلمة المرور');
        widget.onDone();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      children: [
        const AuthCardTitle(
          title: 'كلمة المرور الجديدة',
          subtitle: 'اختر كلمة مرور قوية ثم سجّل الدخول',
        ),
        AuthField(
          controller: _passC,
          hint: 'كلمة المرور الجديدة',
          icon: Icons.lock_rounded,
          isPassword: true,
        ),
        const SizedBox(height: 12),
        AuthField(
          controller: _confirmC,
          hint: 'تأكيد كلمة المرور',
          icon: Icons.lock_outline_rounded,
          isPassword: true,
        ),
        const SizedBox(height: 16),
        AuthGradientButton(
          label: 'حفظ وتسجيل الدخول',
          loading: _loading,
          onTap: _submit,
        ),
        const SizedBox(height: 6),
        AuthLinkRow(
          prefix: 'تغيّرت فكرتك؟',
          action: 'رجوع لتسجيل الدخول',
          onTap: widget.onDone,
        ),
      ],
    );
  }
}
