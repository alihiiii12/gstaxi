import 'package:get/get.dart';

import '../../../core/services/trip_api_service.dart';

class DriverWalletController extends GetxController {
  final loading = true.obs;
  final error = ''.obs;
  final balance = 0.0.obs;
  final currency = 'SYP'.obs;
  final withdrawNote = 'السحب يتم حصراً بواسطة الإدارة'.obs;
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
      final r = await TripApiService.fetchDriverWallet();
      if (!r.ok) {
        error.value = r.message ?? 'تعذر تحميل المحفظة';
        return;
      }
      final data = r.dataMap ?? {};
      final wallet = data['wallet'];
      if (wallet is Map) {
        balance.value =
            double.tryParse('${wallet['balance']}') ?? 0.0;
        currency.value = '${wallet['currency'] ?? 'SYP'}';
      }
      final note = data['withdraw_note']?.toString();
      if (note != null && note.trim().isNotEmpty) {
        withdrawNote.value = note;
      }
      final list = data['transactions'];
      if (list is List) {
        transactions.assignAll([
          for (final e in list)
            if (e is Map) Map<String, dynamic>.from(e),
        ]);
      } else {
        transactions.clear();
      }
    } catch (e) {
      error.value = e.toString();
    } finally {
      loading.value = false;
    }
  }
}
