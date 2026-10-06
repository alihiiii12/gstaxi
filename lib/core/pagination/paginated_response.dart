class PaginatedResponse<T> {
  final List<T> data;
  final int currentPage;
  final int lastPage;
  final bool hasMore;

  PaginatedResponse({
    required this.data,
    required this.currentPage,
    required this.lastPage,
  }) : hasMore = currentPage < lastPage;

  factory PaginatedResponse.fromJson(
      Map<String, dynamic> json,
      T Function(Map<String, dynamic>) fromJson,
      ) {
    final dataList = (json['data'] as List)
        .map((e) => fromJson(e))
        .toList();

    return PaginatedResponse<T>(
      data: dataList,
      currentPage: json['current_page'],
      lastPage: json['last_page'],
    );
  }
}
