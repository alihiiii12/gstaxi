
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_utils/src/extensions/internacionalization.dart';

import '../constants/shared_pref.dart';
import '../services/secure_auth_token.dart';

class ApiEndpoints {
  /// عنوان واجهة Laravel بالكامل (بدون شرطة مائلة في النهاية).
  ///
  /// `flutter run --dart-define=SYRIATAXI_API_BASE_URL=https://gstaxi.online/api`
  ///
  /// أمثلة:
  /// - إنتاج: https://gstaxi.online/api
  /// - XAMPP محلي (debug): http://192.168.1.114/SyriaTaxi-main/public/api
  /// - Emulator أندرويد: http://10.0.2.2/SyriaTaxi-main/public/api
  static const String baseUrl = String.fromEnvironment(
    'SYRIATAXI_API_BASE_URL',
    defaultValue: 'https://gstaxi.online/api',
  );

  /// جذر الموقع (لصور السائق/السيارة من Laravel public).
  static String get publicRoot =>
      baseUrl.replaceFirst(RegExp(r'/api/?$'), '');

  static String get login => "$baseUrl/login";
  static String get userFcmToken => "$baseUrl/user/fcm-token";
  static String get logout => "$baseUrl/logout";
  static String get deleteAccount => "$baseUrl/account";
  static String get updatepassword => "$baseUrl/user/update";
  static String get currentUser => "$baseUrl/user";
  static String get updateLocation => "$baseUrl/drivers/updateLocation";
  static String get driverGoOffline => "$baseUrl/drivers/go-offline";
  static String get driverMeProfile => "$baseUrl/drivers/me/profile";
  static String get driverPricing => "$baseUrl/drivers/me/pricing";
  static String get driverFreeMeterPricing =>
      "$baseUrl/drivers/me/free-meter-pricing";
  static String get driverReceiveRadius =>
      "$baseUrl/drivers/me/receive-radius";
  static String get pricingZonesMap => "$baseUrl/pricing/zones-map";
  static String get emergencySos => "$baseUrl/emergency/sos";
  static String get emergencySosLive => "$baseUrl/emergency/sos/live";
  static String get emergencyActive => "$baseUrl/emergency/active";
  static String get availableBookings => "$baseUrl/requests/available-bookings";
  static String get storeRequest => "$baseUrl/requests/store";
  static String get carTypesIndex => "$baseUrl/car-types/index";

  static String get customerNotifications => "$baseUrl/customer/notifications";
  static String get customerNotificationsUnread =>
      "$baseUrl/customer/notifications/unread-count";
  static String customerNotificationMarkRead(int id) =>
      "$baseUrl/customer/notifications/$id/read";
  static String get customerUpdateLocation =>
      "$baseUrl/customer/update-location";
  static String get customerGoOffline => "$baseUrl/customer/go-offline";

  static String get immediatePendingRequests => "$baseUrl/requests/immediate-pending";

  /// استطلاع موحّد للسائق (يقلّل ضغط الخادم).
  static String get driverPollSnapshot => "$baseUrl/driver/poll-snapshot";

  /// سائقون قرب الانطلاق قبل إنشاء الطلب الفوري.
  static String nearbyDriversBooking({
    required double pickupLat,
    required double pickupLng,
    required int carTypeId,
    double? destLat,
    double? destLng,
    double? estimatedDurationMinutes,
    double? estimatedTripKm,
  }) {
    final q = <String, String>{
      'pickupLatitude': pickupLat.toString(),
      'pickupLongitude': pickupLng.toString(),
      'carTypeId': carTypeId.toString(),
    };
    if (destLat != null) q['destLatitude'] = destLat.toString();
    if (destLng != null) q['destLongitude'] = destLng.toString();
    if (estimatedDurationMinutes != null && estimatedDurationMinutes > 0) {
      q['estimatedDurationMinutes'] = estimatedDurationMinutes.toString();
    }
    if (estimatedTripKm != null && estimatedTripKm > 0) {
      q['estimatedTripKm'] = estimatedTripKm.toString();
    }
    final uri =
        Uri.parse('$baseUrl/requests/nearby-drivers-booking').replace(
      queryParameters: q,
    );
    return uri.toString();
  }
  static String cancelCustomerRequest(int requestId) =>
      "$baseUrl/requests/$requestId/cancel";
  static String abortActiveTrip(int requestId) =>
      "$baseUrl/requests/$requestId/abort";
  static String userRequests(int userId) => "$baseUrl/requests/user/$userId";
  static String get customerActiveTrip => "$baseUrl/requests/customer/active";

  static String get drivingSummary => "$baseUrl/routing/driving-summary";
  static String immediateStatus(int requestId) =>
      "$baseUrl/requests/$requestId/immediate-status";
  static String expandSearch(int requestId) =>
      "$baseUrl/requests/$requestId/expand-search";
  static String searchTimeout(int requestId) =>
      "$baseUrl/requests/$requestId/search-timeout";
  /// فحص خفيف للوصول إلى الخادم (أي رد HTTP = متصل).
  static String get connectivityProbe => "$publicRoot/favicon.ico";
  static String customerTripTracking(int requestId) =>
      "$baseUrl/requests/$requestId/trip-tracking";
  static String selectDriver(int requestId) =>
      "$baseUrl/requests/$requestId/select-driver";
  static String driverArrived(int requestId) =>
      "$baseUrl/requests/$requestId/driver-arrived";
  static String startTrip(int requestId) =>
      "$baseUrl/requests/$requestId/start";
  static String confirmDriverArrived(int requestId) =>
      "$baseUrl/requests/$requestId/confirm-driver-arrived";
  static String setDestination(int requestId) =>
      "$baseUrl/requests/$requestId/set-destination";

  /// الراكب تحرّك قبل وصول السائق — `latitude`, `longitude`.
  static String updatePickup(int requestId) =>
      "$baseUrl/requests/$requestId/update-pickup";

  /// ردّ الراكب على «هل أنت جاهز للرحلة؟» (حجز مسبق) — `ready: true|false`.
  static String scheduledPassengerReady(int requestId) =>
      "$baseUrl/requests/$requestId/scheduled-passenger-ready";

  /// بعد إشعار «السائق مشغول»: `action`: wait | cancel.
  static String scheduledPassengerWaitOrCancel(int requestId) =>
      "$baseUrl/requests/$requestId/scheduled-passenger-wait-or-cancel";

  /// ردّ السائق: بدء الرحلة أو «ليس الآن» (تأجيل) — `action`: start | defer.
  static String scheduledDriverResponse(int requestId) =>
      "$baseUrl/requests/$requestId/scheduled-driver-response";

  static String get driverNotifications => "$baseUrl/driver/notifications";
  static String get driverNotificationsUnread =>
      "$baseUrl/driver/notifications/unread-count";
  static String driverNotificationMarkRead(int id) =>
      "$baseUrl/driver/notifications/$id/read";
  static String get driverWallet => "$baseUrl/driver/wallet";
  static String get customerWallet => "$baseUrl/customer/wallet";
  static String tripPayment(int requestId) =>
      "$baseUrl/requests/$requestId/payment";
  static String tripPay(int requestId) => "$baseUrl/requests/$requestId/pay";

  static String get complaintsStore => "$baseUrl/complaints";
  static String complaintsForRequest(int requestId) =>
      "$baseUrl/complaints/request/$requestId";

  static String acceptBooking(int requestId) => "$baseUrl/requests/$requestId/accept";

  /// رفض الطلب الفوري من السائق (إلغاء الطلب وإشعار الزبون لإعادة الإرسال أو اختيار سائق آخر).
  static String driverDeclineImmediate(int requestId) =>
      "$baseUrl/requests/$requestId/driver-decline-immediate";

  /// رفض حجز مسبق معلّق (قبل القبول) — يُفرَّغ السائق ويُشعر الزبون لاختيار سائق آخر.
  static String driverDeclineScheduled(int requestId) =>
      "$baseUrl/requests/$requestId/driver-decline-scheduled";

  /// إلغاء حجز مسبق مقبول مع اعتذار إلزامي.
  static String driverCancelScheduled(int requestId) =>
      "$baseUrl/requests/$requestId/driver-cancel-scheduled";
  static String driverCancelEnRoute(int requestId) =>
      "$baseUrl/requests/$requestId/driver-cancel-en-route";
  static String finishTrip(int requestId) => "$baseUrl/requests/$requestId/finish";
  static String reportLiveMeter(int requestId) =>
      "$baseUrl/requests/$requestId/live-meter";
  static String get startFreeMeter => "$baseUrl/requests/free-meter/start";

  static String driverTrips(int driverId) => "$baseUrl/requests/driver/$driverId/trips";
  static String driverRequests(int driverId) => "$baseUrl/requests/driver/$driverId";

  /// التحقق من كوبون الخصم (يحتاج code + userId + originalPrice في JSON).
  static String get discountValidate => "$baseUrl/discounts/validate";
  static String get pricingZoneQuote => "$baseUrl/pricing/zone-quote";

  /// مسارات قديمة من مشروع آخر — احذفها عند عدم الاستخدام
  static final String register = "$baseUrl/register";
  static final String registerCustomer = "$baseUrl/register-customer";
  static final String categories = "$baseUrl/lists/categories";
  static final String teachers = "$baseUrl/lists/teachers";
  static final String forgetPassword = "$baseUrl/forget-password";
  static final String forgetPasswordReset = "$baseUrl/forget-password/reset";
  static final String store = "$baseUrl/store";
  static final String banner = "$baseUrl/banners";
  static final String products = "$baseUrl/product";
  static final String myOrders = "$baseUrl/client/All.My.orders";
  static final String favorites = "$baseUrl/client/favorites";
  static final String confirmAccount = "$baseUrl/confirm-account";
  static final String confirmForget = "$baseUrl/forget-password/check-code";
  static final String resendCode = "$baseUrl/confirmation-code/resend";
  static final String getProfile = "$baseUrl/account/get-profile";
  static final String updateProfile = "$baseUrl/account/update-profile";
  static final String updatePassword = "$baseUrl/account/update-password";
  static final String redeemVoucher = "$baseUrl/redeem-voucher";

  static Future<String?> getToken() async {
    return SecureAuthToken.value;
  }

  static String? _cachedCurrency;
  static String? _cachedLang;

  static Future<Map<String, String>> headers() async {
    final token = SecureAuthToken.value ?? '';
    final lang = Get.locale?.languageCode ?? 'ar';
    if (_cachedCurrency == null || _cachedLang != lang) {
      _cachedCurrency = await MyInfoPrefs.getInfo(name: 'currency') ?? 'USD';
      _cachedLang = lang;
    }
    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Accept-Language': lang,
      'Accept-Currency': _cachedCurrency ?? 'USD',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// يصفّر كاش العملة/اللغة بعد تغيير الإعدادات.
  static void invalidateHeadersCache() {
    _cachedCurrency = null;
    _cachedLang = null;
  }

  /// رفع multipart — بدون Content-Type ليضبط الحدود تلقائياً.
  static Future<Map<String, String>> headersMultipart() async {
    final h = await headers();
    h.remove('Content-Type');
    return h;
  }
}
