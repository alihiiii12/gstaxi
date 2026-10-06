import 'package:flutter/widgets.dart';

import 'app_sizes.dart';

/// أبعاد موحّدة للأزرار عبر كل الأجهزة (تصميم مرجعي 375×812).
class AppButtonDims {
  AppButtonDims._();

  static const double heightSmDesign = 46;
  static const double heightMdDesign = 50;
  static const double heightLgDesign = 54;
  static const double radiusDesign = 14;
  static const double horizontalPadDesign = 16;

  static double get heightSm => AppSizes.h(heightSmDesign);
  static double get heightMd => AppSizes.h(heightMdDesign);
  static double get heightLg => AppSizes.h(heightLgDesign);
  static double get radius => AppSizes.w(radiusDesign);
  static double get horizontalPad => AppSizes.w(horizontalPadDesign);

  static Size get minSizeSm => Size(0, heightSm);
  static Size get minSizeMd => Size(0, heightMd);
  static Size get minSizeLg => Size(0, heightLg);
  static Size get minSizeFullMd => Size(double.infinity, heightMd);
  static Size get minSizeFullLg => Size(double.infinity, heightLg);

  static EdgeInsets get paddingMd => EdgeInsets.symmetric(
        horizontal: horizontalPad,
        vertical: 0,
      );
}
