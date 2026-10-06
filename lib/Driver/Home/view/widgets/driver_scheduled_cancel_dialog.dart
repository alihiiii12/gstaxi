import 'package:flutter/material.dart';
import '../../../../core/constants/snack_bar.dart';
import 'package:get/get.dart';

import '../../../../core/services/trip_api_service.dart';

/// إلغاء حجز مسبق مقبول — يتطلب اعتذاراً يُحفظ في قاعدة البيانات.
Future<bool> showDriverScheduledCancelDialog({
  required int requestId,
  required Future<void> Function() onSuccess,
}) async {
  final apologyC = TextEditingController();
  var sending = false;
  final ok = await Get.dialog<bool>(
    StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('إلغاء الحجز المسبق'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'بعد قبول الحجز، الإلغاء يتطلب تقديم اعتذار للراكب والإدارة (15 حرفاً على الأقل).',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: apologyC,
                maxLines: 4,
                enabled: !sending,
                decoration: const InputDecoration(
                  labelText: 'نص الاعتذار',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: sending ? null : () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          ElevatedButton(
            onPressed: sending
                ? null
                : () async {
                    final text = apologyC.text.trim();
                    if (text.length < 15) {
                      AppSnackBar.notify(
                        'مطلوب',
                        'اكتب اعتذاراً أوضح (15 حرفاً على الأقل).',
                      );
                      return;
                    }
                    setLocal(() => sending = true);
                    try {
                      final r = await TripApiService.driverCancelScheduled(
                        requestId,
                        apology: text,
                      );
                      if (!ctx.mounted) return;
                      if (r.ok) {
                        Navigator.pop(ctx, true);
                      } else {
                        setLocal(() => sending = false);
                        AppSnackBar.notify(
                          'تعذر الإلغاء',
                          r.message ?? 'حاول لاحقاً',
                        );
                      }
                    } catch (e) {
                      setLocal(() => sending = false);
                      AppSnackBar.notify('خطأ', '$e');
                    }
                  },
            child: sending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('إرسال الاعتذار وإلغاء الحجز'),
          ),
        ],
      ),
    ),
    barrierDismissible: false,
  );
  apologyC.dispose();
  if (ok == true) {
    await onSuccess();
    AppSnackBar.notify('تم', 'تم إلغاء الحجز وتسجيل اعتذارك');
    return true;
  }
  return false;
}
