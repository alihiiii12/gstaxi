import 'package:flutter/material.dart';

import '../../../../core/constants/app_images.dart';

/// خلفية مشتركة للسبلاش وتسجيل الدخول — نفس القصّ والتمركز حتى لا تقفز الصورة.
class AuthSceneBackground extends StatelessWidget {
  const AuthSceneBackground({super.key});

  static const Color fillColor = Color(0xFFFCC309);

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: fillColor,
      child: Image(
        image: AssetImage(AppImages.splashBg),
        fit: BoxFit.cover,
        alignment: Alignment.center,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }
}
