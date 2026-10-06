import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../Driver/Auth/auth_session.dart';
import '../constants/snack_bar.dart';
import '../network/api_endpoints.dart';

/// حذف الحساب من داخل التطبيق (مطلوب App Store / Google Play).
class AccountDeletionService {
  AccountDeletionService._();

  static const privacyPolicyUrl = 'https://gstaxi.online/privacy.html';

  static Future<void> openPrivacyPolicy() async {
    final uri = Uri.parse(privacyPolicyUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      AppSnackBar.error('تعذر فتح سياسة الخصوصية');
    }
  }

  static Future<void> confirmAndDeleteAccount(BuildContext context) async {
    final agreed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('حذف الحساب', textAlign: TextAlign.right),
        content: const Text(
          'سيتم حذف حسابك نهائياً ولن تتمكن من تسجيل الدخول مرة أخرى.\n'
          'إذا كان لديك رحلة نشطة، أكملها أو ألغها أولاً.\n\n'
          'هل أنت متأكد؟',
          textAlign: TextAlign.right,
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Get.back(result: true),
            child: const Text('حذف الحساب'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
    if (agreed != true) return;

    try {
      final res = await http.delete(
        Uri.parse(ApiEndpoints.deleteAccount),
        headers: await ApiEndpoints.headers(),
      );
      final body = json.decode(res.body);
      final map = body is Map<String, dynamic> ? body : <String, dynamic>{};
      final ok = res.statusCode >= 200 &&
          res.statusCode < 300 &&
          (map['success'] == true || map['state'] == true);

      if (!ok) {
        AppSnackBar.error(map['message']?.toString() ?? 'تعذر حذف الحساب');
        return;
      }

      await AuthSession.signOut();
      AppSnackBar.success(map['message']?.toString() ?? 'تم حذف الحساب');
    } catch (e) {
      AppSnackBar.error('تعذر الاتصال بالخادم');
    }
  }
}
