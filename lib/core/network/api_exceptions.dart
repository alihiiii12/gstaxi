class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException({this.statusCode, required this.message});

  @override
  String toString() => message;
}
