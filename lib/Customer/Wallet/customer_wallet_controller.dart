import 'package:get/get.dart';

import '../../core/services/trip_api_service.dart';

class CustomerWalletController extends GetxController {
  final loading = true.obs;
  final error = ''.obs;
  final balance = 0.0.obs;
  final currency = 'SYP'.obs;
  final note = 'تعبئة الرصيد تتم عن طريق الإدارة'.obs;
  final transactions = <Map<String, dynamic>>[].obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    error.value = '';
    try {
      final r = await TripApiService.fetchCustomerWallet();
      if (!r.ok) {
        error.value = r.message ?? 'تعذر تحميل المحفظة';
        return;
      }
      final data = r.dataMap ?? {};
      final wallet = data['wallet'];
      if (wallet is Map) {
        balance.value = double.tryParse('${wallet['balance']}') ?? 0.0;
        currency.value = '${wallet['currency'] ?? 'SYP'}';
      }
      final n = data['topup_note']?.toString();
      if (n != null && n.trim().isNotEmpty) note.value = n;
      final list = data['transactions'];
      transactions.assignAll([
        if (list is List)
          for (final e in list)
            if (e is Map) Map<String, dynamic>.from(e),
      ]);
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
    }
  }
}
