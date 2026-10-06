import 'map_performance_profile.dart';

/// إعدادات ستايل خرائط OSM — مظهر قريب من Waze (تقريب بصري فقط).
abstract final class MapStyleConfig {
  /// نهار — طرق صفراء/برتقالية وخلفية خضراء فاتحة بأسلوب Waze.
  static const dayStyleUrl = 'assets/maps/styles/day.json';

  /// ليل — خلفية داكنة وطرق دافئة بأسلوب Waze الليلي.
  static const nightStyleUrl = 'assets/maps/styles/night.json';

  /// لون مسار التنقّل (أزرق واضح على خريطة الليل/النهار).
  static const routeColor = 0xFF1E88E5;
  static const routeCasingColor = 0xFFFFFFFF;

  /// عرض الخريطة الافتراضي — إمالة أقل على الأجهزة الضعيفة.
  static double get mapDefaultZoom =>
      MapPerformanceProfile.isLowEnd ? 14.0 : 14.4;

  static double get mapDefaultTilt =>
      MapPerformanceProfile.isLowEnd ? 0.0 : 52.0;

  /// متابعة خلف السيارة أثناء الرحلة.
  static double get navFollowZoom =>
      MapPerformanceProfile.isLowEnd ? 16.0 : 17.0;

  static double get navFollowTiltActive =>
      MapPerformanceProfile.isLowEnd ? 28.0 : 58.0;

  static double get navFollowTiltEnRoute =>
      MapPerformanceProfile.isLowEnd ? 22.0 : 55.0;

  static double get navFollowLookAheadActive =>
      MapPerformanceProfile.isLowEnd ? 28.0 : 48.0;

  static double get navFollowLookAheadEnRoute =>
      MapPerformanceProfile.isLowEnd ? 20.0 : 36.0;

  /// OSRM عام — يُفضّل استبداله لاحقاً بـ VPS الخاص.
  static const osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';

  /// كتالوج حزم الأوفلاين (يمكن استضافته على gstaxi.online).
  static const offlineCatalogUrl =
      'https://gstaxi.online/maps/offline/catalog.json';

  static const photonBaseUrl = 'https://photon.komoot.io/api/';

  /// حدود سوريا التقريبية لتحميل أوفلاين.
  static const syriaWest = 35.6;
  static const syriaEast = 42.4;
  static const syriaSouth = 32.3;
  static const syriaNorth = 37.4;
}
