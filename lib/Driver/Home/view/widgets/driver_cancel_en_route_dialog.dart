import 'package:flutter/material.dart';
import '../../../../core/constants/snack_bar.dart';
import 'package:get/get.dart';

import '../../../../core/services/trip_api_service.dart';

/// إلغاء طلب مقبول قبل الوصول للراكب.
Future<bool> showDriverCancelEnRouteDialog({
  required int requestId,
  required Future<void> Function() onSuccess,
}) async {
  final ok = await Get.dialog<bool>(
    AlertDialog(
      title: const Text('إلغاء الطلب'),
      content: const Text(
        'هل تريد إلغاء هذا الطلب قبل الوصول للراكب؟\n'
        'سيُبلَّغ الراكب ويمكنه إرسال طلب جديد.',
      ),
      actions: [
        TextButton(
          onPressed: () => Get.back(result: false),
          child: const Text('تراجع'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade700,
            foregroundColor: Colors.white,
          ),
          onPressed: () async {
            var r = await TripApiService.driverCancelEnRoute(requestId);
            if (!r.ok) {
              r = await TripApiService.abortActiveTrip(requestId);
            }
            if (r.ok) {
              Get.back(result: true);
            } else {
              AppSnackBar.notify(
                'تعذر الإلغاء',
                r.message ?? 'حاول لاحقاً',
              );
            }
          },
          child: const Text('نعم، إلغاء الطلب'),
        ),
      ],
    ),
    barrierDismissible: false,
  );

  if (ok == true) {
    await onSuccess();
    AppSnackBar.notify('تم', 'تم إلغاء الطلب');
    return true;
  }
  return false;
}
