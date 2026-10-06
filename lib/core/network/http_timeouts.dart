import 'dart:convert';

import 'package:http/http.dart' as http;

  /// مهلات موحّدة لطلبات الشبكة — تمنع التعليق الطويل بدون رد.
abstract final class HttpTimeouts {
  /// طلبات API عامة (حجز، رحلة، ملف…).
  static const api = Duration(seconds: 12);

  /// جلب أسعار العداد — مهلة قصيرة حتى لا يعلّق زر التشغيل.
  static const pricing = Duration(seconds: 8);

  /// إنهاء / بدء عداد حر — يحتاج مهلة أطول قليلاً.
  static const finishTrip = Duration(seconds: 22);

  /// استطلاع دوري خفيف (poll-snapshot / active-trip / live meter).
  static const poll = Duration(seconds: 4);

  /// بوابات الإقلاع (update-info / service-cut).
  static const startup = Duration(seconds: 3);

  /// تسجيل الدخول / OTP.
  static const auth = Duration(seconds: 10);

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration timeout = api,
  }) {
    return http.get(url, headers: headers).timeout(timeout);
  }

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = api,
  }) {
    return http
        .post(url, headers: headers, body: body, encoding: encoding)
        .timeout(timeout);
  }

  static Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
    Duration timeout = api,
  }) {
    return http
        .delete(url, headers: headers, body: body, encoding: encoding)
        .timeout(timeout);
  }
}
