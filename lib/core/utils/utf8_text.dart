import 'dart:convert';

import 'package:http/http.dart' as http;

/// تفكيك JSON من استجابة HTTP بـ UTF-8 دائماً (يتجنب mojibake عند غياب charset).
dynamic decodeJsonUtf8(http.Response res) {
  return json.decode(utf8Body(res));
}

String utf8Body(http.Response res) {
  try {
    return utf8.decode(res.bodyBytes);
  } catch (_) {
    return res.body;
  }
}

/// يصلح نصاً عُرِض كـ mojibake بعد قراءة UTF-8 على أنه Latin-1/cp1252.
String repairUtf8Mojibake(String input) {
  final s = input.trim();
  if (s.isEmpty) return input;
  // علامات شائعة: Ù Ø Â Ã من تفسير خاطئ لبايتات عربية.
  final looksBroken = s.contains('Ù') ||
      s.contains('Ø') ||
      s.contains('Ã') ||
      s.contains('Â');
  if (!looksBroken) return input;
  try {
    final repaired = utf8.decode(latin1.encode(s), allowMalformed: false);
    if (repaired.contains(RegExp(r'[\u0600-\u06FF]'))) {
      return repaired;
    }
  } catch (_) {}
  return input;
}
