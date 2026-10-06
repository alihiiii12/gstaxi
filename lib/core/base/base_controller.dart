import 'package:get/get.dart';
import '../network/api_response.dart';

abstract class BaseController extends GetxController {
  final isLoading = false.obs;
  final error = ''.obs;

  void startLoading() {
    isLoading.value = true;
    error.value = '';
  }

  void stopLoading() {
    isLoading.value = false;
  }

  void setError(String msg) {
    error.value = msg;
  }

  /// =========================
  /// 🔥 EXECUTOR الموحد
  /// =========================


}
