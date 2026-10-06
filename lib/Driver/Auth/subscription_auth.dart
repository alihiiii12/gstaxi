import '../../core/constants/error_model.dart';

/// حظر تسجيل الدخول لانتهاء اشتراك السائق الشهري.
bool isDriverSubscriptionBlocked(ErrorModel error) {
  if (error.statusCode != 403) return false;
  if (error.code == 'subscription_blocked') return true;
  final msg = error.message;
  return msg.contains('قم بالدفع') || msg.contains('الاشتراك');
}

String driverSubscriptionBlockedMessage(ErrorModel error) {
  if (error.message.trim().isNotEmpty) return error.message;
  return 'قم بالدفع — تجديد الاشتراك الشهري';
}
