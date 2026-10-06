import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../Driver/Home/view/widgets/driver_screen_shell.dart';
import '../../core/widgets/wallet_view.dart';
import 'customer_wallet_controller.dart';

class CustomerWalletScreen extends StatelessWidget {
  const CustomerWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(CustomerWalletController());

    return DriverScreenShell(
      title: 'محفظتي',
      actions: [
        DriverHeaderIconButton(
          icon: Icons.refresh_rounded,
          onTap: () => c.load(),
        ),
      ],
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Obx(
          () => WalletView(
            loading: c.loading.value,
            error: c.error.value,
            balance: c.balance.value,
            currency: c.currency.value,
            note: c.note.value,
            transactions: c.transactions.toList(),
            onRefresh: c.load,
          ),
        ),
      ),
    );
  }
}
