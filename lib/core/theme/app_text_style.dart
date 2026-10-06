import 'package:flutter/material.dart';

class AppTextStyles {
  AppTextStyles._();

  /// بدون ملف خط مضمّن — نترك خط النظام لعرض العربية بشكل صحيح.
  static const String? fontFamily = null;

  static const headline = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.bold,
  );

  static const title = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w600,
  );

  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
  );

  static const label = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
  );
}
