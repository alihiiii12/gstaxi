class ApiResponse<T> {
  final T? data;
  final String? message;
  final bool success;

  ApiResponse.success(this.data)
      : success = true,
        message = null;

  ApiResponse.error(this.message)
      : success = false,
        data = null;
}
