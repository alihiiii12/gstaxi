import 'dart:convert';
import '../../core/constants/snack_bar.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_endpoints.dart';

/// فحص إصدار التطبيق وإظهار نافذة التحديث عند الحاجة.
class AppUpdateGate {
  AppUpdateGate._();

  /// يطابق `version:` في pubspec (الجزء بعد +) — احتياط إن فشل package_info.
  static const int embeddedBuild = 22;

  /// رابط متجر أبل — حدّثه عند توفر التطبيق على App Store.
  static const String iosStoreUrl =
      'https://apps.apple.com/app/id0000000000';

  static const String androidApkUrl =
      'https://gstaxi.online/downloads/gstaxi.apk';

  static PackageInfo? _info;

  static Future<PackageInfo> packageInfo() async {
    return _info ??= await PackageInfo.fromPlatform();
  }

  static Future<int> buildNumber() async {
    try {
      final p = await packageInfo();
      final n = int.tryParse(p.buildNumber) ?? 0;
      if (n > 0) return n;
    } catch (_) {}
    return embeddedBuild;
  }

  /// ينظّف رابط التحميل؛ إن كان فارغاً يعيد رابط APK الافتراضي.
  static String sanitizeDownloadUrl(String? raw) {
    final u = (raw ?? '').trim();
    if (u.isEmpty) return androidApkUrl;
    final uri = Uri.tryParse(u);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return androidApkUrl;
    }
    return u;
  }

  static Future<Map<String, String>> authClientHeaders() async {
    final build = await buildNumber();
    String version = '1.0.7';
    try {
      version = (await packageInfo()).version;
    } catch (_) {}
    return {
      'X-App-Build': '$build',
      'X-App-Version': version,
    };
  }

  /// يُستدعى من شاشة البداية — إن وُجد تحديث إجباري يعرض حواراً ولا يكمل التنقّل.
  static Future<bool> blockIfUpdateRequired(BuildContext? context) async {
    try {
      final build = await buildNumber();
      final uri = Uri.parse('${ApiEndpoints.baseUrl}/app/update-info').replace(
        queryParameters: {'app_build': '$build'},
      );
      final res = await http
          .get(uri, headers: {
            'Accept': 'application/json',
            ...await authClientHeaders(),
          })
          .timeout(const Duration(seconds: 8));
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final map = json.decode(res.body) as Map<String, dynamic>;
      final data = map['data'];
      if (data is! Map) return false;
      final required = data['update_required'] == true;
      if (!required) return false;
      final url = sanitizeDownloadUrl(data['download_url']?.toString());
      final msg = data['message']?.toString() ??
          'نسخة التطبيق قديمة. يرجى التحديث للمتابعة.';
      await showUpdateDialog(
        message: msg,
        downloadUrl: url,
        barrierDismissible: false,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> showUpdateDialog({
    required String message,
    required String downloadUrl,
    bool barrierDismissible = true,
  }) async {
    final ctx = Get.context;
    if (ctx == null) {
      AppSnackBar.notify('تحديث مطلوب', message);
      return;
    }
    await showDialog<void>(
      context: ctx,
      barrierDismissible: barrierDismissible,
      builder: (c) => AlertDialog(
        title: const Text('تحديث التطبيق'),
        content: Text(message),
        actions: [
          if (barrierDismissible)
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('لاحقاً'),
            ),
          FilledButton(
            onPressed: () async {
              final u = downloadUrl.trim();
              if (u.isEmpty) return;
              final uri = Uri.tryParse(u);
              if (uri == null) return;
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: const Text('تحميل التحديث'),
          ),
        ],
      ),
    );
  }

  static Future<void> showFromLoginError({
    required String message,
    String? downloadUrl,
    String? code,
  }) async {
    final isUpdate = code == 'update_required' ||
        message.contains('قديمة') ||
        message.contains('حدّث') ||
        message.contains('حدث التطبيق') ||
        (downloadUrl != null && downloadUrl.isNotEmpty);
    if (!isUpdate) {
      AppSnackBar.notify('تنبيه', message);
      return;
    }
    // استخرج الرابط من النص إن لم يأتِ منفصلاً.
    var url = downloadUrl?.trim() ?? '';
    if (url.isEmpty) {
      final m = RegExp(r'https?://\S+').firstMatch(message);
      url = m?.group(0) ?? 'https://gstaxi.online/downloads/gstaxi.apk';
    }
    await showUpdateDialog(message: message, downloadUrl: sanitizeDownloadUrl(url));
  }
}
