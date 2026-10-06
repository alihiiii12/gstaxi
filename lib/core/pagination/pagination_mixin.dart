
import 'package:get/get.dart';
import 'package:syriataxi/core/pagination/paginated_response.dart';

import '../network/api_response.dart';

class PaginationController<T> extends GetxController {
  final RxList<T> items = <T>[].obs;

  final RxInt _page = 1.obs;
  final RxBool isLoading = false.obs;
  final RxBool isLoadingMore = false.obs;
  final RxBool hasMore = true.obs;

  /// الدالة اللي رح تمررها من كل API
  late Future<ApiResponse<PaginatedResponse<T>>> Function(int page)
  fetchPage;

  void init({
    required Future<ApiResponse<PaginatedResponse<T>>> Function(int page)
    onFetch,
  }) {
    fetchPage = onFetch;
    fetch(reset: true);
  }

  Future<void> fetch({bool reset = false}) async {
    if (isLoading.value || isLoadingMore.value) return;
    if (!hasMore.value && !reset) return;

    if (reset) {
      _page.value = 1;
      hasMore.value = true;
      items.clear();
      isLoading.value = true;
    } else {
      isLoadingMore.value = true;
    }

    final res = await fetchPage(_page.value);

    if (res.success) {
      final pageData = res.data!;
      items.addAll(pageData.data);
      hasMore.value = pageData.hasMore;
      _page.value++;
    }

    isLoading.value = false;
    isLoadingMore.value = false;
  }

  void refresh() => fetch(reset: true);
}
