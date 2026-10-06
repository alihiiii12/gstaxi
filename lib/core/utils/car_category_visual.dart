import 'package:flutter/material.dart';

/// أيقونات/صور فئات المركبة في واجهة الراكب والإدارة.
class CarCategoryVisual {
  CarCategoryVisual._();

  static const String airConditionedAsset = 'images/car_category_ac.png';
  static const String economyAsset = 'images/car_category_economy.png';

  static String _name(Map<String, dynamic> ct) =>
      (ct['name'] ?? ct['Name'] ?? '').toString().trim();

  static bool isAirConditionedCategory(Map<String, dynamic> ct) {
    final name = _name(ct).toLowerCase();
    if (name.contains('مكيف') ||
        name.contains('مكّيف') ||
        name.contains('air') ||
        name.contains('a/c') ||
        name.contains('ac ')) {
      return true;
    }
    final badge = (ct['customer_badge'] ?? ct['customerBadge'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return badge == 'ac' ||
        badge == 'air' ||
        badge.contains('aircond') ||
        badge.contains('conditioned');
  }

  static bool isEconomyCategory(Map<String, dynamic> ct) {
    if (isAirConditionedCategory(ct)) return false;
    final name = _name(ct).toLowerCase();
    if (name.contains('اقتصاد') ||
        name.contains('عادي') ||
        name.contains('economy') ||
        name.contains('standard') ||
        name.contains('normal')) {
      return true;
    }
    final badge = (ct['customer_badge'] ?? ct['customerBadge'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    return badge == 'economy' || badge == 'standard' || badge == 'normal';
  }

  static String? categoryImageAsset(Map<String, dynamic> ct) {
    if (isAirConditionedCategory(ct)) return airConditionedAsset;
    if (isEconomyCategory(ct)) return economyAsset;
    return null;
  }

  static IconData badgeIcon(Map<String, dynamic> ct) {
    final badge = (ct['customer_badge'] ?? ct['customerBadge'] ?? '')
        .toString()
        .toLowerCase();
    if (badge.contains('suv')) return Icons.airport_shuttle_rounded;
    if (badge.contains('premium') || badge.contains('vip')) {
      return Icons.work_rounded;
    }
    return Icons.directions_car_rounded;
  }

  static Color badgeColor(Map<String, dynamic> ct) {
    final badge = (ct['customer_badge'] ?? ct['customerBadge'] ?? '')
        .toString()
        .toLowerCase();
    if (badge.contains('suv')) return Colors.blue.shade700;
    if (badge.contains('premium') || badge.contains('vip')) {
      return Colors.brown.shade700;
    }
    return Colors.redAccent.shade700;
  }

  static Widget _categoryImage(
    String asset, {
    required double width,
    required double height,
    required Map<String, dynamic> ct,
    required double fallbackIconSize,
  }) {
    return Image.asset(
      asset,
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Icon(
        badgeIcon(ct),
        color: badgeColor(ct),
        size: fallbackIconSize,
      ),
    );
  }

  /// بطاقة اختيار الفئة — صور حقيقية للاقتصادي والمكيفة.
  static Widget pickerGraphic(
    Map<String, dynamic> ct, {
    double iconSize = 22,
  }) {
    final asset = categoryImageAsset(ct);
    if (asset != null) {
      return _categoryImage(
        asset,
        width: iconSize * 2.1,
        height: iconSize * 1.05,
        ct: ct,
        fallbackIconSize: iconSize,
      );
    }
    return Icon(
      badgeIcon(ct),
      color: badgeColor(ct),
      size: iconSize,
    );
  }

  /// قائمة الإدارة — نفس المنطق بحجم أكبر.
  static Widget listGraphic(
    Map<String, dynamic> ct, {
    double size = 28,
  }) {
    final asset = categoryImageAsset(ct);
    if (asset != null) {
      return _categoryImage(
        asset,
        width: size * 2.2,
        height: size,
        ct: ct,
        fallbackIconSize: size,
      );
    }
    return Icon(badgeIcon(ct), color: badgeColor(ct), size: size);
  }

  static bool usesCategoryPhoto(Map<String, dynamic> ct) =>
      categoryImageAsset(ct) != null;
}
