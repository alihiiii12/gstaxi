import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../core/widgets/wallet_view.dart';
import '../../../Home/view/widgets/driver_screen_shell.dart';
import '../../controller/driver_wallet_controller.dart';

class DriverWalletScreen extends StatelessWidget {
  const DriverWalletScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(DriverWalletController());

    return DriverScreenShell(
      title: 'المحفظة',
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
            note: c.withdrawNote.value,
            transactions: c.transactions.toList(),
            onRefresh: c.load,
          ),
        ),
      ),
    );
  }
}
