import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

import '../../auth_api/auth_api.dart';
import '../../auth_session.dart';
import '../../subscription_auth.dart';
import '../../../../core/constants/snack_bar.dart';
import '../../../../core/utils/syrian_phone.dart';
import '../../model/auth_otp_purpose.dart';
import '../screen/reset_password_screen.dart';
import 'auth_form_ui.dart';
import 'auth_ui.dart';

class OtpVerifyCard extends StatefulWidget {
  const OtpVerifyCard({
    super.key,
    required this.phoneNumber,
    required this.purpose,
    this.password,
    required this.onBackToLogin,
    this.onResetTokenReady,
  });

  final String phoneNumber;
  final AuthOtpPurpose purpose;

  /// كلمة المرور (بعد التسجيل) — احتياطي إذا لم يُرجع السيرفر توكناً.
  final String? password;

  final VoidCallback onBackToLogin;

  /// عند تمريره تُسلَّم نتيجة التحقق للمضيف ليقلب البطاقة بدل فتح صفحة جديدة.
  final void Function(String phone, String resetToken)? onResetTokenReady;

  @override
  State<OtpVerifyCard> createState() => _OtpVerifyCardState();
}

class _OtpVerifyCardState extends State<OtpVerifyCard> {
  final _controllers = List.generate(4, (_) => TextEditingController());
  final _nodes = List.generate(4, (_) => FocusNode());
  bool _loading = false;
  bool _resending = false;

  String get _normalizedPhone => SyrianPhone.normalize(widget.phoneNumber);

  /// معزول اتجاهياً حتى لا تنتقل علامة + إلى نهاية الرقم داخل نص عربي.
  String get _phoneDisplay =>
      '\u2066${SyrianPhone.toE164(_normalizedPhone)}\u2069';

  String get _code => _controllers.map((c) => c.text).join().trim();

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_code.length != 4) {
      AppSnackBar.error('أدخل الرمز المكون من 4 أرقام');
      return;
    }
    setState(() => _loading = true);

    if (widget.purpose == AuthOtpPurpose.register) {
      await _confirmRegistration();
      return;
    }

    final result = await AuthApi.confirmForgetOtp(
      number: _normalizedPhone,
      code: _code,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    result.fold(
      (e) => AppSnackBar.error(e.message),
      (map) {
        final data = map['data'];
        final token = data is Map ? data['reset_token']?.toString() ?? '' : '';
        if (token.isEmpty) {
          AppSnackBar.error('تعذر متابعة استعادة كلمة المرور');
          return;
        }
        final handler = widget.onResetTokenReady;
        if (handler != null) {
          handler(_normalizedPhone, token);
          return;
        }
        Get.off(
          () => ResetPasswordScreen(
            phoneNumber: _normalizedPhone,
            resetToken: token,
          ),
        );
      },
    );
  }

  Future<void> _confirmRegistration() async {
    final fcm = GetStorage().read<String>('fcm_token');
    final result = await AuthApi.confirmAccount(
      number: _normalizedPhone,
      code: _code,
      fcmToken: fcm,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    await result.fold(
      (e) async => AppSnackBar.error(e.message),
      (session) async {
        if (await AuthSession.completeLogin(session)) {
          AppSnackBar.success('مرحباً بك في سوريا تاكسي');
          return;
        }
        final pwd = widget.password;
        if (pwd == null || pwd.isEmpty) {
          AuthSession.loginFailed();
          return;
        }
        final loginResult = await AuthApi.login(
          number: _normalizedPhone,
          password: pwd,
          fcmToken: fcm,
        );
        if (!mounted) return;
        loginResult.fold(
          (e) {
            if (isDriverSubscriptionBlocked(e)) {
              AppSnackBar.error(driverSubscriptionBlockedMessage(e));
            } else {
              AppSnackBar.error(e.message);
            }
          },
          (loggedIn) async {
            if (await AuthSession.completeLogin(loggedIn)) {
              AppSnackBar.success('مرحباً بك في سوريا تاكسي');
            } else {
              AuthSession.loginFailed();
            }
          },
        );
      },
    );
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    final result = await AuthApi.resendOtp(
      number: _normalizedPhone,
      purpose: widget.purpose.apiPurpose,
    );
    if (!mounted) return;
    setState(() => _resending = false);
    result.fold(
      (e) => AppSnackBar.error(e.message),
      (_) => AppSnackBar.success('تم إرسال الرمز مجدداً عبر SMS'),
    );
  }

  Widget _otpBox(int index) {
    return SizedBox(
      width: 56,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AuthPalette.fieldFill,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AuthPalette.fieldBorder, width: 1.5),
        ),
        child: TextField(
          controller: _controllers[index],
          focusNode: _nodes[index],
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: const TextStyle(
            color: AuthUi.darkCharcoal,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
          decoration: const InputDecoration(
            counterText: '',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            isDense: true,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (v) {
            if (v.isNotEmpty && index < _nodes.length - 1) {
              _nodes[index + 1].requestFocus();
            } else if (v.isEmpty && index > 0) {
              _nodes[index - 1].requestFocus();
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthCard(
      children: [
        AuthCardTitle(
          title: widget.purpose.title,
          subtitle: 'أدخل الرمز المكوّن من 4 أرقام المرسل عبر SMS إلى'
              '\n$_phoneDisplay',
        ),
        Row(
          textDirection: TextDirection.ltr,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [for (var i = 0; i < 4; i++) _otpBox(i)],
        ),
        const SizedBox(height: 18),
        AuthGradientButton(
          label: 'تأكيد الرمز',
          loading: _loading,
          onTap: _confirm,
        ),
        const SizedBox(height: 6),
        AuthLinkRow(
          prefix: 'لم يصلك الكود؟',
          action: _resending ? 'جاري الإرسال…' : 'إعادة الإرسال',
          onTap: _resending ? () {} : _resend,
        ),
      ],
    );
  }
}
