/// فترات استطلاع العميل — احتياطي بعد اعتماد Push للحالات.
abstract final class CustomerPollIntervals {
  /// لا رحلة نشطة — اكتشاف نادر فقط.
  static const idle = Duration(seconds: 30);

  /// Pending/Reserved — Push يغطي الأهم؛ الاستطلاع شبكة أمان.
  static const activeTrip = Duration(seconds: 8);

  /// أثناء Running: التتبع أهم من قائمة الطلبات.
  static const activeTripRunning = Duration(seconds: 15);

  /// تتبع موقع السائق (+ live_meter).
  static const driverTracking = Duration(seconds: 2);

  /// قبل قبول سائق لا يوجد موقع للتتبع.
  static const driverTrackingPending = Duration(seconds: 7);

  static const driverTrackingRunning = Duration(milliseconds: 1000);

  /// انتظار قبول السائق في الشيت.
  static const waitingAccept = Duration(seconds: 5);

  static const notifications = Duration(seconds: 35);

  static const errorBackoff = Duration(seconds: 12);
}
