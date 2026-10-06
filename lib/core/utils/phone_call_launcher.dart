import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/snack_bar.dart';

/// فتح تطبيق الهاتف للاتصال برقم (راكب أو غيره).
/// يجرّب عدة صيغ لأن `canLaunchUrl(tel:)` يفشل على أجهزة أندرويد كثيرة.
Future<void> launchPhoneCall(String phone) async {
  final digits = _normalizePhone(phone);
  if (digits.isEmpty) {
    AppSnackBar.notify('اتصال', 'لا يوجد رقم هاتف صالح');
    return;
  }

  final candidates = <Uri>[
    Uri(scheme: 'tel', path: digits),
    Uri.parse('tel:$digits'),
    Uri.parse('tel://${Uri.encodeComponent(digits)}'),
  ];

  for (final uri in candidates) {
    for (final mode in const [
      LaunchMode.externalApplication,
      LaunchMode.platformDefault,
    ]) {
      try {
        final launched = await launchUrl(uri, mode: mode);
        if (launched) return;
      } catch (e) {
        debugPrint('[launchPhoneCall] $uri / $mode: $e');
      }
    }
  }

  AppSnackBar.notify(
    'اتصال',
    'تعذّر فتح تطبيق الاتصال. الرقم: $digits',
    duration: const Duration(seconds: 5),
  );
}

String _normalizePhone(String raw) {
  var s = raw.trim();
  // أرقام عربية-هندية → لاتينية
  const eastern = '٠١٢٣٤٥٦٧٨٩';
  const western = '0123456789';
  final buf = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = eastern.indexOf(ch);
    buf.write(i >= 0 ? western[i] : ch);
  }
  s = buf.toString();
  // أبقِ + والأرقام فقط
  s = s.replaceAll(RegExp(r'[^\d+]'), '');
  if (s.startsWith('00')) {
    s = '+${s.substring(2)}';
  }
  // أزل + المكررة داخل الرقم
  if (s.contains('+')) {
    final hasPlus = s.startsWith('+');
    s = s.replaceAll('+', '');
    if (hasPlus) s = '+$s';
  }
  return s;
}
