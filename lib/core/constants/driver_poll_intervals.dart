/// فترات استطلاع السائق — احتياطي بعد اعتماد Push للحالات.
abstract final class DriverPollIntervals {
  /// أونلاين بدون رحلة — الطلبات الفورية تأتي غالباً عبر FCM.
  static const idleOnline = Duration(seconds: 12);

  /// أثناء رحلة محجوزة/جارية.
  static const activeTrip = Duration(seconds: 8);

  static const notifications = Duration(seconds: 45);

  static const minGap = Duration(milliseconds: 2500);

  static const locationSyncMin = Duration(seconds: 12);

  /// رفع لقطة العداد الحي — أقرب لعداد الراكب.
  static const liveMeterUploadMin = Duration(milliseconds: 800);

  static const errorBackoff = Duration(seconds: 15);
}
