/// قنوات إشعارات أندرويد — يجب أن تطابق AndroidManifest و MainActivity و FcmPushService.
/// صوت القناة لا يتغيّر بعد إنشائها على الجهاز، لذلك تغيير النغمة = معرّف قناة جديد.
class AndroidNotificationChannels {
  AndroidNotificationChannels._();

  /// إشعارات Firebase (حجز مسبق، حالة الرحلة، تنبيهات عامة) — النغمة القصيرة.
  static const String fcmId = 'syriataxi_notify_v3';
  static const String fcmName = 'إشعارات سوريا تاكسي';

  /// طلبات فورية للسائق — أهمية قصوى ونغمة الرنين الكاملة.
  static const String rideOffersId = 'syriataxi_ride_offers_v3';
  static const String rideOffersName = 'طلبات الرحلات';

  /// أسماء ملفات res/raw (بدون الامتداد).
  static const String notifySound = 'gs_notify';
  static const String ringtoneSound = 'gs_ringtone';

  /// قنوات قديمة تُحذف حتى لا تتكرر في إعدادات الإشعارات.
  static const List<String> legacyIds = [
    'syriataxi_high',
    'syriataxi_ride_offers',
    'syriataxi_ride_offers_v2',
  ];

  /// اسم العرض لقناة تتبع الموقع (Geolocator foreground) — المعرّف يُنشئه الحزمة تلقائياً.
  static const String driverOnlineChannelName = 'سائق متصل';
}
