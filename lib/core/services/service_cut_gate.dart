import 'dart:convert';
import '../../core/constants/snack_bar.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../network/api_endpoints.dart';
import 'app_update_gate.dart';

/// عند تفعيل القطع من السيرفر (`php artisan service:cut`) يمنع استخدام التطبيق.
class ServiceCutGate {
  ServiceCutGate._();

  static const code = 'SERVICE_CUT';

  static bool isServiceCutResponse(int statusCode, String body) {
    if (statusCode != 503) return false;
    try {
      final map = json.decode(body);
      if (map is Map && map['code']?.toString() == code) return true;
    } catch (_) {}
    return false;
  }

  /// يُستدعى من شاشة البداية — إن كان الاتصال مقطوعاً يعرض حواراً دائماً.
  static Future<bool> blockIfServiceCut(BuildContext? context) async {
    try {
      final uri = Uri.parse('${ApiEndpoints.baseUrl}/app/update-info');
      final res = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              ...await AppUpdateGate.authClientHeaders(),
            },
          )
          .timeout(const Duration(seconds: 8));
      if (!isServiceCutResponse(res.statusCode, res.body)) return false;
      String msg = 'تم قطع الاتصال بالخادم مؤقتاً';
      try {
        final map = json.decode(res.body);
        if (map is Map && map['message'] != null) {
          msg = map['message'].toString();
        }
      } catch (_) {}
      await showCutDialog(message: msg);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showCutDialog({required String message}) async {
    final ctx = Get.context;
    if (ctx == null) {
      AppSnackBar.notify('الخدمة متوقفة', message);
      return;
    }
    await showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('تم قطع الاتصال'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogCtx).pop();
                  final still = await blockIfServiceCut(null);
                  if (!still) {
                    // أعيد التشغيل لمسار التطبيق الطبيعي
                    Get.offAllNamed('/');
                  }
                },
                child: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        );
      },
    );
  }
}
