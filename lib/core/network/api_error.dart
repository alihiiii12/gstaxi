class ApiError {
  final String message;
  final Map<String, List<String>>? errors;
  final int? statusCode;

  ApiError({
    required this.message,
    this.errors,
    this.statusCode,
  });

  factory ApiError.fromJson(dynamic json, {int? statusCode}) {
    return ApiError(
      message: json['message'] ?? 'Something went wrong',
      errors: json['errors'] != null
          ? Map<String, List<String>>.from(
        json['errors'].map(
              (k, v) => MapEntry(
            k,
            List<String>.from(v),
          ),
        ),
      )
          : null,
      statusCode: statusCode,
    );
  }
}
