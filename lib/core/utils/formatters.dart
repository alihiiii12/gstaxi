import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/storage_service.dart';

class AppFormatters {
  AppFormatters._();

  // =========================
  // 🔢 NUMBER & CURRENCY
  // =========================

  /// تنسيق رقم عادي (1,234)
  static String number(
      num value, {
        int decimal = 0,
      }) {
    return NumberFormat.decimalPattern()
        .format(value.toDouble());
  }

  /// تنسيق عملة حسب العملة المخزنة
  static String currency(
      num value, {
        String? currencyCode,
        int decimal = 2,
      }) {
    final code = currencyCode ?? StorageService.currency;

    return NumberFormat.currency(
      symbol: code,
      decimalDigits: decimal,
    ).format(value);
  }

  /// تنسيق سعر بسيط (بدون رمز)
  static String price(num value) {
    return number(value);
  }

  // =========================
  // 📅 DATE & TIME
  // =========================

  /// yyyy-MM-dd
  static String date(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  /// dd/MM/yyyy
  static String dateSlash(DateTime date) {
    return DateFormat('dd/MM/yyyy').format(date);
  }

  /// HH:mm
  static String time(DateTime date) {
    return DateFormat('HH:mm').format(date);
  }

  /// تاريخ + وقت
  static String dateTime(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm').format(date);
  }

  /// تحليل تواريخ الخادم — موعد الحجز يُخزَّن ويُرسل بتوقيت سوريا (بدون إزاحة مزدوجة).
  static DateTime? parseApiDateTime(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;

    final normalized =
        s.contains('T') ? s : s.replaceFirst(RegExp(r'\s+'), 'T');
    final parsed = DateTime.tryParse(normalized);
    if (parsed == null) return null;

    // `yyyy-MM-dd HH:mm:ss` من الخادم = وقت سوريا المحلي
    final isNaiveLocal = !parsed.isUtc &&
        !RegExp(r'[zZ]|[+-]\d{2}:?\d{2}$').hasMatch(s);
    if (isNaiveLocal) {
      return DateTime(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      );
    }

    // بيانات قديمة: Z مع وقوع الوقت كتوقيت سوريا مخزّن خطأً كـ UTC
    if (parsed.isUtc && s.endsWith('Z')) {
      return DateTime(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      );
    }

    if (parsed.isUtc) return parsed.toLocal();
    return parsed;
  }

  /// صيغة مختصرة لموعد الرحلة (نفس منطق parseApiDateTime).
  static String scheduledTripDateTimeCompact(String raw) {
    final dt = parseApiDateTime(raw);
    if (dt == null) {
      final s = raw.trim();
      return s.isEmpty ? '—' : s;
    }
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}/${dt.month}/${dt.day} $h:$m';
  }

  /// يوم الأسبوع + التاريخ + الوقت لبطاقات الطلبات (بدون اعتماد على `initializeDateFormatting`).
  static String arabicWeekdayDateTime(DateTime dt) {
    const days = <String>[
      'الاثنين',
      'الثلاثاء',
      'الأربعاء',
      'الخميس',
      'الجمعة',
      'السبت',
      'الأحد',
    ];
    final wd = days[dt.weekday - 1];
    final d =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    final t =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$wd، $d — $t';
  }

  /// عرض موعد الطلب أو وقت الإنشاء بصيغة مقروءة.
  static String requestCardDateTimeDisplay(String raw) {
    final dt = parseApiDateTime(raw);
    if (dt == null) {
      final s = raw.trim();
      return s.isEmpty ? '—' : s;
    }
    return arabicWeekdayDateTime(dt);
  }

  // =========================
  // ☎️ PHONE
  // =========================

  /// تنظيف رقم الهاتف (إزالة الفراغات)
  static String sanitizePhone(String phone) {
    return phone.replaceAll(RegExp(r'\s+'), '');
  }

  /// عرض رقم الهاتف بشكل جميل
  static String formatPhone(String phone) {
    final clean = sanitizePhone(phone);

    if (clean.length < 7) return clean;

    return clean.replaceAllMapped(
      RegExp(r'(\d{3})(\d{3})(\d+)'),
          (m) => '${m[1]} ${m[2]} ${m[3]}',
    );
  }

  // =========================
  // 🔐 TEXT MASKING
  // =========================

  /// إخفاء الإيميل (a***@mail.com)
  static String maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return email;

    final name = parts[0];
    if (name.length <= 2) return email;

    return '${name[0]}***@${parts[1]}';
  }

  /// إخفاء رقم البطاقة
  static String maskCard(String card) {
    if (card.length < 4) return card;
    return '**** **** **** ${card.substring(card.length - 4)}';
  }

  // =========================
  // 🧼 STRING CLEANERS
  // =========================

  /// إزالة المسافات الزائدة
  static String trim(String text) {
    return text.trim();
  }

  /// إزالة أي حروف غير رقمية
  static String onlyNumbers(String text) {
    return text.replaceAll(RegExp(r'\D'), '');
  }

  // =========================
  // ✍️ INPUT FORMATTERS
  // =========================

  /// أرقام فقط
  static List<TextInputFormatter> numbersOnly = [
    FilteringTextInputFormatter.digitsOnly,
  ];

  /// رقم عشري
  static TextInputFormatter decimalOnly({
    int decimalRange = 2,
  }) {
    return FilteringTextInputFormatter.allow(
      RegExp(r'^\d+\.?\d{0,' + decimalRange.toString() + '}'),
    );
  }

  /// بدون مسافات
  static List<TextInputFormatter> noSpaces = [
    FilteringTextInputFormatter.deny(RegExp(r'\s')),
  ];

  /// أحرف فقط
  static List<TextInputFormatter> lettersOnly = [
    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\u0600-\u06FF ]')),
  ];

  /// طول محدد
  static TextInputFormatter maxLength(int length) {
    return LengthLimitingTextInputFormatter(length);
  }

  /// رقم هاتف
  static List<TextInputFormatter> phoneInput = [
    FilteringTextInputFormatter.allow(RegExp(r'[0-9+]')),
    LengthLimitingTextInputFormatter(15),
  ];
}
