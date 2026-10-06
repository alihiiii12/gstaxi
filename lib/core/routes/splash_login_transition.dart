import 'package:flutter/material.dart';

import '../../Driver/Auth/view/screen/login_screen.dart';

/// انتقال من السبلاش إلى تسجيل الدخول:
/// الخلفية ثابتة، واللوغو يطلع لفوق عبر Hero، ثم يظهر كرت الدخول بالنص.
class SplashLoginTransition {
  SplashLoginTransition._();

  static const String heroTag = 'gs_taxi_logo';

  static double splashLogoWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width * 0.64;

  static double loginLogoWidth(BuildContext context) =>
      MediaQuery.sizeOf(context).width * 0.48;

  static void open(BuildContext context) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 820),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        pageBuilder: (context, animation, secondaryAnimation) {
          return LoginScreen(
            fromSplash: true,
            routeAnimation: animation,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return child;
        },
      ),
    );
  }
}
