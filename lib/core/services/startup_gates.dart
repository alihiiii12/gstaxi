import 'dart:convert';

import 'package:flutter/material.dart';

import '../network/api_endpoints.dart';
import '../network/http_timeouts.dart';
import 'app_update_gate.dart';
import 'service_cut_gate.dart';

/// فحص إقلاع واحد لـ `/app/update-info` بدل طلبين متتاليين (قطع الخدمة + التحديث).
abstract final class StartupGates {
  /// يعيد `true` إذا يجب إيقاف التنقّل (قطع أو تحديث إجباري).
  static Future<bool> blockIfNeeded(BuildContext? context) async {
    try {
      final build = await AppUpdateGate.buildNumber();
      final uri = Uri.parse('${ApiEndpoints.baseUrl}/app/update-info').replace(
        queryParameters: {'app_build': '$build'},
      );
      final res = await HttpTimeouts.get(
        uri,
        headers: {
          'Accept': 'application/json',
          ...await AppUpdateGate.authClientHeaders(),
        },
        timeout: HttpTimeouts.startup,
      );

      if (ServiceCutGate.isServiceCutResponse(res.statusCode, res.body)) {
        String msg = 'تم قطع الاتصال بالخادم مؤقتاً';
        try {
          final map = json.decode(res.body);
          if (map is Map && map['message'] != null) {
            msg = map['message'].toString();
          }
        } catch (_) {}
        await ServiceCutGate.showCutDialog(message: msg);
        return true;
      }

      if (res.statusCode < 200 || res.statusCode >= 300) return false;

      final decoded = json.decode(res.body);
      if (decoded is! Map) return false;
      final data = decoded['data'];
      if (data is! Map) return false;
      if (data['update_required'] != true) return false;

      final url = AppUpdateGate.sanitizeDownloadUrl(
        data['download_url']?.toString(),
      );
      final msg = data['message']?.toString() ??
          'نسخة التطبيق قديمة. يرجى التحديث للمتابعة.';
      await AppUpdateGate.showUpdateDialog(
        message: msg,
        downloadUrl: url,
        barrierDismissible: false,
      );
      return true;
    } catch (_) {
      // لا نمنع الدخول عند فشل الشبكة أثناء الإقلاع.
      return false;
    }
  }
}
