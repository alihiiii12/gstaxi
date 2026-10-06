import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../utils/app_alert_sound.dart';
import 'trip_payment_panel.dart';

/// شاشة كاملة لعرض نتيجة الرحلة بخط واضح.
class TripCompletionScreen {
  TripCompletionScreen._();

  static const Color _navy = Color(0xFF11215B);
  static const Color _amber = Color(0xFFF5B301);

  /// [paymentRequestId] + [paymentRole]: يعرض قسم طريقة الدفع (محفظة/كاش).
  static Future<void> show({
    required String summary,
    String title = 'انتهت الرحلة',
    String? requestIdLabel,
    int? paymentRequestId,
    TripPaymentRole paymentRole = TripPaymentRole.customer,
  }) async {
    await AppAlertSound.playTripFinished();
    final rootCtx = Get.overlayContext ?? Get.context;
    if (rootCtx == null) return;

    final withPayment = paymentRequestId != null && paymentRequestId > 0;
    final canDismiss = ValueNotifier<bool>(!withPayment);

    await showDialog<void>(
      context: rootCtx,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (dialogCtx) => PopScope(
        canPop: false,
        child: Material(
          color: _navy,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (ctx, constraints) => SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - 64).clamp(0, double.infinity),
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.check_circle_outline,
                            color: _amber, size: 72),
                        const SizedBox(height: 20),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (requestIdLabel != null &&
                            requestIdLabel.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            requestIdLabel,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 16,
                            ),
                          ),
                        ],
                        const Spacer(),
                        const SizedBox(height: 16),
                        Text(
                          summary,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _amber,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            height: 1.35,
                          ),
                        ),
                        if (withPayment) ...[
                          const SizedBox(height: 20),
                          Directionality(
                            textDirection: TextDirection.rtl,
                            child: TripPaymentPanel(
                              requestId: paymentRequestId,
                              role: paymentRole,
                              canDismiss: canDismiss,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        const Spacer(),
                        ValueListenableBuilder<bool>(
                          valueListenable: canDismiss,
                          builder: (_, ok, __) => !ok
                              ? const SizedBox(height: 54)
                              : SizedBox(
                                  height: 54,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _amber,
                                      foregroundColor: _navy,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                    onPressed: () =>
                                        Navigator.of(dialogCtx).pop(),
                                    child: const Text(
                                      'حسناً',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    canDismiss.dispose();
  }
}
