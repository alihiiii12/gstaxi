import 'package:flutter/material.dart';

import '../../../../core/routes/splash_login_transition.dart';
import '../../../../core/widgets/app_logo.dart';
import 'auth_scene_background.dart';

/// هيكل موحّد لشاشات المصادقة: نفس الخلفية، اللوغو فوق، والبطاقة تحته.
class AuthScene extends StatelessWidget {
  const AuthScene({
    super.key,
    required this.card,
    this.heroLogo = false,
    this.onBack,
  });

  final Widget card;

  /// يُفعّل انتقال Hero للوغو (يُستخدم في شاشة الدخول القادمة من السبلاش).
  final bool heroLogo;

  /// عند تمريره يظهر زر رجوع أعلى الشاشة.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final logoWidth = SplashLoginTransition.loginLogoWidth(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AuthSceneBackground.fillColor,
        resizeToAvoidBottomInset: false,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const AuthSceneBackground(),
            AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: keyboardInset),
              child: SafeArea(
                child: Align(
                  alignment: const Alignment(0, -0.32),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(26, 12, 26, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppLogo(
                          heroTag:
                              heroLogo ? SplashLoginTransition.heroTag : null,
                          width: logoWidth,
                        ),
                        const SizedBox(height: 14),
                        card,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (onBack != null)
              SafeArea(
                child: Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4, right: 6),
                    child: IconButton(
                      onPressed: onBack,
                      icon: const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
