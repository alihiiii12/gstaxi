import 'package:flutter/material.dart';

import '../../model/auth_otp_purpose.dart';
import '../widgets/auth_card_flipper.dart';
import '../widgets/auth_scene.dart';
import '../widgets/forgot_password_card.dart';
import '../widgets/login_card.dart';
import '../widgets/otp_verify_card.dart';
import '../widgets/register_card.dart';
import '../widgets/reset_password_card.dart';

enum AuthCardMode { login, register, forgotPassword, otpVerify, resetPassword }

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.fromSplash = false,
    this.routeAnimation,
  });

  final bool fromSplash;
  final Animation<double>? routeAnimation;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  AuthCardMode _mode = AuthCardMode.login;

  String _phone = '';
  String _resetToken = '';
  String? _registerPassword;
  AuthOtpPurpose _otpPurpose = AuthOtpPurpose.resetPassword;

  late final AnimationController _entryController;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 780),
    );

    _entryFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.28, 1, curve: Curves.easeOut),
      ),
    );

    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _entryController,
        curve: const Interval(0.22, 1, curve: Curves.easeOutCubic),
      ),
    );

    if (widget.fromSplash) {
      // ينتظر حتى يكاد اللوغو يستقرّ في مكانه حتى لا يمرّ فوق البطاقة.
      Future<void>.delayed(const Duration(milliseconds: 560), () {
        if (mounted) _entryController.forward();
      });
    } else {
      _entryController.value = 1;
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _switchTo(AuthCardMode mode) {
    if (_mode == mode) return;
    FocusScope.of(context).unfocus();
    setState(() => _mode = mode);
  }

  void _goToOtp({
    required String phone,
    required AuthOtpPurpose purpose,
    String? password,
  }) {
    FocusScope.of(context).unfocus();
    setState(() {
      _phone = phone;
      _otpPurpose = purpose;
      _registerPassword = password;
      _mode = AuthCardMode.otpVerify;
    });
  }

  void _goToResetPassword(String phone, String token) {
    FocusScope.of(context).unfocus();
    setState(() {
      _phone = phone;
      _resetToken = token;
      _mode = AuthCardMode.resetPassword;
    });
  }

  Widget _cardFor(AuthCardMode mode) {
    switch (mode) {
      case AuthCardMode.login:
        return LoginCard(
          key: const ValueKey(AuthCardMode.login),
          onForgotPassword: () => _switchTo(AuthCardMode.forgotPassword),
          onCreateAccount: () => _switchTo(AuthCardMode.register),
        );
      case AuthCardMode.register:
        return RegisterCard(
          key: const ValueKey(AuthCardMode.register),
          onBackToLogin: () => _switchTo(AuthCardMode.login),
          onOtpRequired: (phone, password) => _goToOtp(
            phone: phone,
            purpose: AuthOtpPurpose.register,
            password: password,
          ),
        );
      case AuthCardMode.forgotPassword:
        return ForgotPasswordCard(
          key: const ValueKey(AuthCardMode.forgotPassword),
          onBackToLogin: () => _switchTo(AuthCardMode.login),
          onOtpRequired: (phone) => _goToOtp(
            phone: phone,
            purpose: AuthOtpPurpose.resetPassword,
          ),
        );
      case AuthCardMode.otpVerify:
        return OtpVerifyCard(
          key: const ValueKey(AuthCardMode.otpVerify),
          phoneNumber: _phone,
          purpose: _otpPurpose,
          password: _registerPassword,
          onBackToLogin: () => _switchTo(AuthCardMode.login),
          onResetTokenReady: _goToResetPassword,
        );
      case AuthCardMode.resetPassword:
        return ResetPasswordCard(
          key: const ValueKey(AuthCardMode.resetPassword),
          phoneNumber: _phone,
          resetToken: _resetToken,
          onDone: () => _switchTo(AuthCardMode.login),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = _mode == AuthCardMode.login;

    return AuthScene(
      heroLogo: true,
      onBack: isLogin ? null : () => _switchTo(AuthCardMode.login),
      card: FadeTransition(
        opacity: _entryFade,
        child: SlideTransition(
          position: _entrySlide,
          child: AuthCardFlipper(child: _cardFor(_mode)),
        ),
      ),
    );
  }
}
